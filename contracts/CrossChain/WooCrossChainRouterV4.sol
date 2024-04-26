// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

// OpenZeppelin Contracts
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// Uniswap Periphery Contracts
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

// Local Contracts
import {IWETH} from "../interfaces/IWETH.sol";
import {IWooCrossChainRouterV4} from "../interfaces/CrossChain/IWooCrossChainRouterV4.sol";
import {IWooRouterV2} from "../interfaces/IWooRouterV2.sol";
import {IStargateRouter} from "../interfaces/Stargate/IStargateRouter.sol";
import {ISgInfo} from "../interfaces/CrossChain/ISgInfo.sol";

/// @title cross chain router implementation, version 4.
/// @notice Router for stateless execution of cross chain swap against WOOFi or 1inch swap.
/// @custom:stargate-contracts https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
contract WooCrossChainRouterV4 is IWooCrossChainRouterV4, Ownable, Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ----- Constants ----- */

    address public constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ----- Variables ----- */

    IWooRouterV2 public wooRouter;
    ISgInfo public sgInfo;

    address public immutable weth;
    address public feeAddr;
    uint256 public bridgeSlippage; // 1 in 10000th: default 1%

    uint16 public srcExternalFeeRate; // unit: 0.1 bps (1e6 = 100%, 25 = 2.5 bps)
    uint16 public dstExternalFeeRate; // unit: 0.1 bps (1e6 = 100%, 25 = 2.5 bps)
    uint256 public constant FEE_BASE = 1e5;

    mapping(uint16 => address) public wooCrossRouters; // chainId => WooCrossChainRouterV4 address

    receive() external payable {}

    constructor(
        address _weth,
        address _wooRouter,
        address _sgInfo
    ) {
        weth = _weth;
        wooRouter = IWooRouterV2(_wooRouter);
        sgInfo = ISgInfo(_sgInfo);

        bridgeSlippage = 100;

        srcExternalFeeRate = 25;
        dstExternalFeeRate = 25;
    }

    /* ----- Functions ----- */

    function crossSwap(
        uint256 refId,
        address payable to,
        SrcInfos memory srcInfos,
        DstInfos calldata dstInfos,
        Src1inch calldata src1inch,
        Dst1inch calldata dst1inch
    ) external payable whenNotPaused nonReentrant {
        require(to != address(0), "WooCrossChainRouterV4: !to");
        require(srcInfos.fromToken != address(0), "WooCrossChainRouterV4: !srcInfos.fromToken");
        require(
            dstInfos.toToken != address(0) && dstInfos.toToken != sgInfo.sgETHs(dstInfos.chainId),
            "WooCrossChainRouterV4: !dstInfos.toToken"
        );
        require(
            sgInfo.sgPoolIds(sgInfo.sgChainIdLocal(), srcInfos.bridgeToken) > 0,
            "WooCrossChainRouterV4: !srcInfos.bridgeToken"
        );
        require(
            sgInfo.sgPoolIds(dstInfos.chainId, dstInfos.bridgeToken) > 0,
            "WooCrossChainRouterV4: !dstInfos.bridgeToken"
        );

        uint256 msgValue = msg.value;
        uint256 bridgeAmount;
        uint256 fee = 0;

        {
            // Step 1: transfer
            if (srcInfos.fromToken == ETH_PLACEHOLDER_ADDR) {
                require(srcInfos.fromAmount <= msgValue, "WooCrossChainRouterV4: !srcInfos.fromAmount");
                srcInfos.fromToken = weth;
                IWETH(weth).deposit{value: srcInfos.fromAmount}();
                msgValue -= srcInfos.fromAmount;
            } else {
                TransferHelper.safeTransferFrom(srcInfos.fromToken, msg.sender, address(this), srcInfos.fromAmount);
            }

            // Step 2: local swap by 1inch router
            if (srcInfos.fromToken != srcInfos.bridgeToken) {
                TransferHelper.safeApprove(srcInfos.fromToken, address(wooRouter), srcInfos.fromAmount);
                if (src1inch.swapRouter != address(0)) {
                    // external swap via 1inch
                    bridgeAmount = wooRouter.externalSwap(
                        src1inch.swapRouter,
                        src1inch.swapRouter,
                        srcInfos.fromToken,
                        srcInfos.bridgeToken,
                        srcInfos.fromAmount,
                        srcInfos.minBridgeAmount,
                        payable(address(this)),
                        src1inch.data
                    );
                    fee = (bridgeAmount * srcExternalFeeRate) / FEE_BASE;
                } else {
                    // swap via WOOFi
                    bridgeAmount = wooRouter.swap(
                        srcInfos.fromToken,
                        srcInfos.bridgeToken,
                        srcInfos.fromAmount,
                        srcInfos.minBridgeAmount,
                        payable(address(this)),
                        to
                    );
                }
            } else {
                require(
                    srcInfos.fromAmount == srcInfos.minBridgeAmount,
                    "WooCrossChainRouterV4: !srcInfos.minBridgeAmount"
                );
                bridgeAmount = srcInfos.fromAmount;
            }

            require(
                bridgeAmount <= IERC20(srcInfos.bridgeToken).balanceOf(address(this)),
                "WooCrossChainRouterV4: !bridgeAmount"
            );
        }

        // Step 3: deduct the swap fee
        bridgeAmount -= fee;
        require(bridgeAmount >= srcInfos.minBridgeAmount, "WooCrossChainRouterV4: !srcInfos.minBridgeAmount");

        // Step 4: cross chain swap by StargateRouter
        _bridgeByStargate(refId, to, msgValue, bridgeAmount, srcInfos, dstInfos, dst1inch);

        emit WooCrossSwapOnSrcChain(
            refId,
            _msgSender(),
            to,
            srcInfos.fromToken,
            srcInfos.fromAmount,
            srcInfos.bridgeToken,
            srcInfos.minBridgeAmount,
            bridgeAmount,
            src1inch.swapRouter == address(0) ? 0 : 1,
            fee
        );
    }

    function sgReceive(
        uint16, // srcChainId
        bytes memory, // srcAddress
        uint256, // nonce
        address bridgedToken,
        uint256 amountLD,
        bytes memory payload
    ) external {
        require(msg.sender == sgInfo.sgRouter(), "WooCrossChainRouterV4: INVALID_CALLER");

        // make sure the same order to abi.encode when decode payload
        (uint256 refId, address to, address toToken, uint256 minToAmount, Dst1inch memory dst1inch) = abi.decode(
            payload,
            (uint256, address, address, uint256, Dst1inch)
        );

        // toToken won't be SGETH, and bridgedToken won't be ETH_PLACEHOLDER_ADDR
        if (bridgedToken == sgInfo.sgETHs(sgInfo.sgChainIdLocal())) {
            // bridgedToken is SGETH, received native token
            _handleNativeReceived(refId, to, toToken, amountLD, minToAmount, dst1inch);
        } else {
            // bridgedToken is not SGETH, received ERC20 token
            _handleERC20Received(refId, to, toToken, bridgedToken, amountLD, minToAmount, dst1inch);
        }
    }

    function quoteLayerZeroFee(
        uint256 refId,
        address to,
        DstInfos calldata dstInfos,
        Dst1inch calldata dst1inch
    ) external view returns (uint256, uint256) {
        bytes memory payload = abi.encode(refId, to, dstInfos.toToken, dstInfos.minToAmount, dst1inch);
        IStargateRouter.lzTxObj memory obj = IStargateRouter.lzTxObj(
            dstInfos.dstGasForCall,
            dstInfos.airdropNativeAmount,
            abi.encodePacked(to)
        );
        IStargateRouter stargateRouter = IStargateRouter(sgInfo.sgRouter());
        return
            stargateRouter.quoteLayerZeroFee(
                dstInfos.chainId,
                1, // https://stargateprotocol.gitbook.io/stargate/developers/function-types
                obj.dstNativeAddr,
                payload,
                obj
            );
    }

    /// @dev OKAY to be public method
    function claimFee(address token) external nonReentrant {
        require(feeAddr != address(0), "WooCrossChainRouterV4: !feeAddr");
        uint256 amount = _generalBalanceOf(token, address(this));
        if (amount > 0) {
            if (token == ETH_PLACEHOLDER_ADDR) {
                TransferHelper.safeTransferETH(feeAddr, amount);
            } else {
                TransferHelper.safeTransfer(token, feeAddr, amount);
            }
        }
    }

    function _bridgeByStargate(
        uint256 refId,
        address payable to,
        uint256 msgValue,
        uint256 bridgeAmount,
        SrcInfos memory srcInfos,
        DstInfos calldata dstInfos,
        Dst1inch calldata dst1inch
    ) internal {
        bytes memory payload = abi.encode(refId, to, dstInfos.toToken, dstInfos.minToAmount, dst1inch);

        uint256 dstMinBridgeAmount = (bridgeAmount * (10000 - bridgeSlippage)) / 10000;
        bytes memory dstWooCrossChainRouter = abi.encodePacked(wooCrossRouters[dstInfos.chainId]);

        IStargateRouter.lzTxObj memory obj = IStargateRouter.lzTxObj(
            dstInfos.dstGasForCall,
            dstInfos.airdropNativeAmount,
            abi.encodePacked(to)
        );
        IStargateRouter stargateRouter = IStargateRouter(sgInfo.sgRouter());

        if (srcInfos.bridgeToken == weth) {
            IWETH(weth).withdraw(bridgeAmount);
            msgValue += bridgeAmount;
        } else {
            TransferHelper.safeApprove(srcInfos.bridgeToken, sgInfo.sgRouter(), bridgeAmount);
        }

        stargateRouter.swap{value: msgValue}(
            dstInfos.chainId, // dst chain id
            sgInfo.sgPoolIds(sgInfo.sgChainIdLocal(), srcInfos.bridgeToken), // bridge token's pool id on src chain
            sgInfo.sgPoolIds(dstInfos.chainId, dstInfos.bridgeToken), // bridge token's pool id on dst chain
            payable(tx.origin), // rebate address
            bridgeAmount, // swap amount on src chain
            dstMinBridgeAmount, // min received amount on dst chain
            obj, // config: dstGasForCall, dstAirdropNativeAmount, dstReceiveAirdropNativeTokenAddr
            dstWooCrossChainRouter, // smart contract to call on dst chain
            payload // payload to piggyback
        );
    }

    function _handleNativeReceived(
        uint256 refId,
        address to,
        address toToken,
        uint256 bridgedAmount,
        uint256 minToAmount,
        Dst1inch memory dst1inch
    ) internal {
        address msgSender = _msgSender();

        if (toToken == ETH_PLACEHOLDER_ADDR) {
            // Directly transfer ETH
            TransferHelper.safeTransferETH(to, bridgedAmount);
            emit WooCrossSwapOnDstChain(
                refId,
                msgSender,
                to,
                weth,
                bridgedAmount,
                toToken,
                ETH_PLACEHOLDER_ADDR,
                minToAmount,
                bridgedAmount,
                dst1inch.swapRouter == address(0) ? 0 : 1,
                0
            );
            return;
        }

        if (toToken == weth) {
            TransferHelper.safeTransfer(weth, to, bridgedAmount);
            emit WooCrossSwapOnDstChain(
                refId,
                msgSender,
                to,
                weth,
                bridgedAmount,
                toToken,
                weth,
                minToAmount,
                bridgedAmount,
                dst1inch.swapRouter == address(0) ? 0 : 1,
                0
            );
            return;
        }

        // Swap required!
        IWETH(weth).deposit{value: bridgedAmount}();

        if (dst1inch.swapRouter != address(0)) {
            uint256 fee = (bridgedAmount * dstExternalFeeRate) / FEE_BASE;
            uint256 swapAmount = bridgedAmount - fee;
            TransferHelper.safeApprove(weth, address(wooRouter), swapAmount);
            try
                wooRouter.externalSwap(
                    dst1inch.swapRouter,
                    dst1inch.swapRouter,
                    weth,
                    toToken,
                    swapAmount,
                    minToAmount,
                    payable(to),
                    dst1inch.data
                )
            returns (uint256 realToAmount) {
                emit WooCrossSwapOnDstChain(
                    refId,
                    msgSender,
                    to,
                    weth,
                    swapAmount,
                    toToken,
                    toToken,
                    minToAmount,
                    realToAmount,
                    dst1inch.swapRouter == address(0) ? 0 : 1,
                    fee
                );
            } catch {
                TransferHelper.safeApprove(weth, address(wooRouter), 0);
                TransferHelper.safeTransfer(weth, to, bridgedAmount);
                emit WooCrossSwapOnDstChain(
                    refId,
                    msgSender,
                    to,
                    weth,
                    bridgedAmount,
                    toToken,
                    weth,
                    minToAmount,
                    bridgedAmount,
                    dst1inch.swapRouter == address(0) ? 0 : 1,
                    0
                );
            }
        } else {
            TransferHelper.safeApprove(weth, address(wooRouter), bridgedAmount);
            try wooRouter.swap(weth, toToken, bridgedAmount, minToAmount, payable(to), to) returns (
                uint256 realToAmount
            ) {
                emit WooCrossSwapOnDstChain(
                    refId,
                    msgSender,
                    to,
                    weth,
                    bridgedAmount,
                    toToken,
                    toToken,
                    minToAmount,
                    realToAmount,
                    dst1inch.swapRouter == address(0) ? 0 : 1,
                    0
                );
            } catch {
                TransferHelper.safeApprove(weth, address(wooRouter), 0);
                TransferHelper.safeTransfer(weth, to, bridgedAmount);
                emit WooCrossSwapOnDstChain(
                    refId,
                    msgSender,
                    to,
                    weth,
                    bridgedAmount,
                    toToken,
                    weth,
                    minToAmount,
                    bridgedAmount,
                    dst1inch.swapRouter == address(0) ? 0 : 1,
                    0
                );
            }
        }
    }

    function _handleERC20Received(
        uint256 refId,
        address to,
        address toToken,
        address bridgedToken,
        uint256 bridgedAmount,
        uint256 minToAmount,
        Dst1inch memory dst1inch
    ) internal {
        address msgSender = _msgSender();

        if (toToken == bridgedToken) {
            TransferHelper.safeTransfer(bridgedToken, to, bridgedAmount);
            emit WooCrossSwapOnDstChain(
                refId,
                msgSender,
                to,
                bridgedToken,
                bridgedAmount,
                toToken,
                toToken,
                minToAmount,
                bridgedAmount,
                dst1inch.swapRouter == address(0) ? 0 : 1,
                0
            );
        } else {
            if (dst1inch.swapRouter != address(0)) {
                uint256 fee = (bridgedAmount * dstExternalFeeRate) / FEE_BASE;
                bridgedAmount -= fee;
                TransferHelper.safeApprove(bridgedToken, address(wooRouter), bridgedAmount);
                try
                    wooRouter.externalSwap(
                        dst1inch.swapRouter,
                        dst1inch.swapRouter,
                        bridgedToken,
                        toToken,
                        bridgedAmount,
                        minToAmount,
                        payable(to),
                        dst1inch.data
                    )
                returns (uint256 realToAmount) {
                    emit WooCrossSwapOnDstChain(
                        refId,
                        msgSender,
                        to,
                        bridgedToken,
                        bridgedAmount,
                        toToken,
                        toToken,
                        minToAmount,
                        realToAmount,
                        dst1inch.swapRouter == address(0) ? 0 : 1,
                        fee
                    );
                } catch {
                    TransferHelper.safeApprove(bridgedToken, address(wooRouter), 0);
                    bridgedAmount += fee;
                    TransferHelper.safeTransfer(bridgedToken, to, bridgedAmount);
                    emit WooCrossSwapOnDstChain(
                        refId,
                        msgSender,
                        to,
                        bridgedToken,
                        bridgedAmount,
                        toToken,
                        bridgedToken,
                        minToAmount,
                        bridgedAmount,
                        dst1inch.swapRouter == address(0) ? 0 : 1,
                        0
                    );
                }
            } else {
                TransferHelper.safeApprove(bridgedToken, address(wooRouter), bridgedAmount);
                try wooRouter.swap(bridgedToken, toToken, bridgedAmount, minToAmount, payable(to), to) returns (
                    uint256 realToAmount
                ) {
                    emit WooCrossSwapOnDstChain(
                        refId,
                        msgSender,
                        to,
                        bridgedToken,
                        bridgedAmount,
                        toToken,
                        toToken,
                        minToAmount,
                        realToAmount,
                        dst1inch.swapRouter == address(0) ? 0 : 1,
                        0
                    );
                } catch {
                    TransferHelper.safeApprove(bridgedToken, address(wooRouter), 0);
                    TransferHelper.safeTransfer(bridgedToken, to, bridgedAmount);
                    emit WooCrossSwapOnDstChain(
                        refId,
                        msgSender,
                        to,
                        bridgedToken,
                        bridgedAmount,
                        toToken,
                        bridgedToken,
                        minToAmount,
                        bridgedAmount,
                        dst1inch.swapRouter == address(0) ? 0 : 1,
                        0
                    );
                }
            }
        }
    }

    function _generalBalanceOf(address token, address who) internal view returns (uint256) {
        return token == ETH_PLACEHOLDER_ADDR ? who.balance : IERC20(token).balanceOf(who);
    }

    /* ----- Owner & Admin Functions ----- */

    function setFeeAddr(address _feeAddr) external onlyOwner {
        feeAddr = _feeAddr;
    }

    function setWooRouter(address _wooRouter) external onlyOwner {
        require(_wooRouter != address(0), "WooCrossChainRouterV4: !_wooRouter");
        wooRouter = IWooRouterV2(_wooRouter);
    }

    function setBridgeSlippage(uint256 _bridgeSlippage) external onlyOwner {
        require(_bridgeSlippage <= 10000, "WooCrossChainRouterV4: !_bridgeSlippage");
        bridgeSlippage = _bridgeSlippage;
    }

    function setWooCrossRouter(uint16 _chainId, address _crossRouter) external onlyOwner {
        require(_crossRouter != address(0), "WooCrossChainRouterV4: !_crossRouter");
        wooCrossRouters[_chainId] = _crossRouter;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        if (stuckToken == ETH_PLACEHOLDER_ADDR) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, msg.sender, amount);
        }
    }
}
