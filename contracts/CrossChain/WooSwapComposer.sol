// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

// OpenZeppelin Contracts
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// Local Contracts
import {IWETH} from "../interfaces/IWETH.sol";
import {IWooCrossChainRouterV3} from "../interfaces/CrossChain/IWooCrossChainRouterV3.sol";
import {IWooRouterV2} from "../interfaces/IWooRouterV2.sol";
import {IStargateRouter} from "../interfaces/Stargate/IStargateRouter.sol";
import {INonceCounter} from "../interfaces/WOOFiDex/INonceCounter.sol";
import {ISgInfo} from "../interfaces/CrossChain/ISgInfo.sol";
import {IWooSwapComposer} from "../interfaces/CrossChain/IWooSwapComposer.sol";
import {IWooSwapReceiver} from "../interfaces/CrossChain/IWooSwapReceiver.sol";

import {TransferHelper} from "../libraries/TransferHelper.sol";
import {SafeCall} from "../libraries/SafeCall.sol";

/// @title cross chain router implementation, version 3.
/// @notice Router for stateless execution of cross chain swap against WOOFi or 1inch swap.
/// @custom:stargate-contracts https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
contract WooSwapComposer is IWooSwapComposer, Ownable, Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCall for address;
    using SafeCall for address payable;

    /* ----- Constants ----- */

    address public constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ----- Variables ----- */

    INonceCounter public nonceCounter;
    IWooRouterV2 public wooRouter;
    ISgInfo public sgInfo;

    address public immutable weth;
    address public feeAddr;
    uint256 public bridgeSlippage; // 1 in 10000th: default 1%

    uint16 public srcExternalFeeRate; // unit: 0.1 bps (1e6 = 100%, 25 = 2.5 bps)
    uint16 public dstExternalFeeRate; // unit: 0.1 bps (1e6 = 100%, 25 = 2.5 bps)
    uint256 public constant FEE_BASE = 1e5;

    uint256 private dstGasReserve = 40000;

    mapping(uint16 => address) public wooCrossComposers; // chainId => WooSwapComposer address

    receive() external payable {}

    constructor(
        address _weth,
        address _nonceCounter,
        address _wooRouter,
        address _sgInfo
    ) {
        weth = _weth;
        nonceCounter = INonceCounter(_nonceCounter);
        wooRouter = IWooRouterV2(_wooRouter);
        sgInfo = ISgInfo(_sgInfo);

        bridgeSlippage = 100;

        srcExternalFeeRate = 25;
        dstExternalFeeRate = 25;
    }

    /* ----- Functions ----- */

    function swap(
        address payable composeTo,
        LocalSwapInfos memory infoWOOFi,
        Src1inch calldata info1inch
    ) external payable returns (uint256 realToAmount) {
        require(infoWOOFi.fromToken != address(0), "WooSwapComposer: !fromToken");
        require(infoWOOFi.toToken != address(0), "WooSwapComposer: !toToken");
        require(composeTo != address(0), "WooSwapComposer: !to");

        uint256 msgValue = 0;
        if (infoWOOFi.fromToken == ETH_PLACEHOLDER_ADDR) {
            require(msg.value >= infoWOOFi.fromAmount, "WooSwapComposer: !msg.value");
            msgValue = msg.value; // TODO in code review: double check whether to use: infoWOOFi.fromAmount
        } else {
            TransferHelper.safeTransferFrom(infoWOOFi.fromToken, msg.sender, address(this), infoWOOFi.fromAmount);
            TransferHelper.safeApprove(infoWOOFi.fromToken, address(wooRouter), infoWOOFi.fromAmount);
        }

        if (info1inch.swapRouter == address(0)) {
            realToAmount = wooRouter.swap{value: msg.value}(
                infoWOOFi.fromToken,
                infoWOOFi.toToken,
                infoWOOFi.fromAmount,
                infoWOOFi.minToAmount,
                composeTo,
                infoWOOFi.rebateTo
            );
        } else {
            realToAmount = wooRouter.externalSwap{value: msg.value}(
                info1inch.swapRouter,
                info1inch.swapRouter,
                infoWOOFi.fromToken,
                infoWOOFi.toToken,
                infoWOOFi.fromAmount,
                infoWOOFi.minToAmount,
                composeTo,
                info1inch.data
            );
        }

        _safeCallLocalCompose(composeTo, infoWOOFi.toToken, realToAmount, infoWOOFi.payload);
    }

    function crossSwap(
        address payable to,
        SrcInfos memory srcInfos,
        DstInfos calldata dstInfos,
        Src1inch calldata src1inch,
        Dst1inch calldata dst1inch
    ) external payable whenNotPaused nonReentrant {
        require(srcInfos.fromToken != address(0), "WooSwapComposer: !srcInfos.fromToken");
        require(
            dstInfos.toToken != address(0) && dstInfos.toToken != sgInfo.sgETHs(dstInfos.chainId),
            "WooSwapComposer: !dstInfos.toToken"
        );
        require(to != address(0), "WooSwapComposer: !to");

        uint256 msgValue = msg.value;
        uint256 bridgeAmount;
        uint256 fee = 0;

        {
            // Step 1: transfer
            if (srcInfos.fromToken == ETH_PLACEHOLDER_ADDR) {
                require(srcInfos.fromAmount <= msgValue, "WooSwapComposer: !srcInfos.fromAmount");
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
                require(srcInfos.fromAmount == srcInfos.minBridgeAmount, "WooSwapComposer: !srcInfos.minBridgeAmount");
                bridgeAmount = srcInfos.fromAmount;
            }

            require(
                bridgeAmount <= IERC20(srcInfos.bridgeToken).balanceOf(address(this)),
                "WooSwapComposer: !bridgeAmount"
            );
        }

        // Step 3: deduct the swap fee
        bridgeAmount -= fee;

        // Step 4: cross chain swap by StargateRouter
        uint256 refId = nonceCounter.increment(dstInfos.chainId);
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
        bytes memory srcAddr, // srcAddress
        uint256, // nonce
        address bridgedToken,
        uint256 amountLD,
        bytes memory payload
    ) external {
        require(msg.sender == sgInfo.sgRouter(), "WooSwapComposer: INVALID_CALLER");

        // make sure the same order to abi.encode when decode payload
        (
            uint256 refId,
            address to,
            address toToken,
            uint256 minToAmount,
            Dst1inch memory dst1inch,
            bytes memory composePayload
        ) = abi.decode(payload, (uint256, address, address, uint256, Dst1inch, bytes));

        // toToken won't be SGETH, and bridgedToken won't be ETH_PLACEHOLDER_ADDR
        if (bridgedToken == sgInfo.sgETHs(sgInfo.sgChainIdLocal())) {
            // bridgedToken is SGETH, received native token
            _handleNativeReceived(
                ComposeInfo(
                    refId,
                    to,
                    address(uint160(bytes20(srcAddr))),
                    toToken,
                    bridgedToken,
                    amountLD,
                    minToAmount,
                    dst1inch,
                    composePayload
                )
            );
        } else {
            // bridgedToken is not SGETH, received ERC20 token
            _handleERC20Received(
                ComposeInfo(
                    refId,
                    to,
                    address(uint160(bytes20(srcAddr))),
                    toToken,
                    bridgedToken,
                    amountLD,
                    minToAmount,
                    dst1inch,
                    composePayload
                )
            );
        }
    }

    function quoteLayerZeroFee(
        address to,
        DstInfos calldata dstInfos,
        Dst1inch calldata dst1inch
    ) external view returns (uint256, uint256) {
        uint256 refId = nonceCounter.outboundNonce(dstInfos.chainId) + 1;
        bytes memory payload = abi.encode(
            refId,
            to,
            dstInfos.toToken,
            dstInfos.minToAmount,
            dst1inch,
            dstInfos.composePayload
        );
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
        require(feeAddr != address(0), "WooSwapComposer: !feeAddr");
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
        require(
            sgInfo.sgPoolIds(sgInfo.sgChainIdLocal(), srcInfos.bridgeToken) > 0,
            "WooSwapComposer: !srcInfos.bridgeToken"
        );
        require(sgInfo.sgPoolIds(dstInfos.chainId, dstInfos.bridgeToken) > 0, "WooSwapComposer: !dstInfos.bridgeToken");

        bytes memory payload = abi.encode(
            refId,
            to,
            dstInfos.toToken,
            dstInfos.minToAmount,
            dst1inch,
            dstInfos.composePayload
        );

        uint256 dstMinBridgeAmount = (bridgeAmount * (10000 - bridgeSlippage)) / 10000;
        bytes memory dstWooCrossChainRouter = abi.encodePacked(wooCrossComposers[dstInfos.chainId]);

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
            payable(_msgSender()), // rebate address
            bridgeAmount, // swap amount on src chain
            dstMinBridgeAmount, // min received amount on dst chain
            obj, // config: dstGasForCall, dstAirdropNativeAmount, dstReceiveAirdropNativeTokenAddr
            dstWooCrossChainRouter, // smart contract to call on dst chain
            payload // payload to piggyback
        );
    }

    function _handleNativeReceived(ComposeInfo memory info) internal {
        uint256 bridgedAmount = info.bridgedAmount;

        if (info.toToken == ETH_PLACEHOLDER_ADDR) {
            // Not needed anymore
            // TransferHelper.safeTransferETH(to, bridgedAmount);
            _safeCallCrossCompose(info, bridgedAmount);
            emit WooCrossSwapOnDstChain(
                info.refId,
                _msgSender(),
                info.to,
                weth,
                bridgedAmount,
                info.toToken,
                ETH_PLACEHOLDER_ADDR,
                info.minToAmount,
                bridgedAmount,
                info.dst1inch.swapRouter == address(0) ? 0 : 1,
                0
            );
            return;
        }

        // Swap required!
        IWETH(weth).deposit{value: bridgedAmount}();

        if (info.dst1inch.swapRouter != address(0)) {
            uint256 fee = (bridgedAmount * dstExternalFeeRate) / FEE_BASE;
            bridgedAmount -= fee;
            TransferHelper.safeApprove(weth, address(wooRouter), bridgedAmount);
            try
                wooRouter.externalSwap(
                    info.dst1inch.swapRouter,
                    info.dst1inch.swapRouter,
                    weth,
                    info.toToken,
                    bridgedAmount,
                    info.minToAmount,
                    payable(info.to),
                    info.dst1inch.data
                )
            returns (uint256 realToAmount) {
                _safeCallCrossCompose(info, realToAmount);

                emit WooCrossSwapOnDstChain(
                    info.refId,
                    _msgSender(),
                    info.to,
                    weth,
                    bridgedAmount,
                    info.toToken,
                    info.toToken,
                    info.minToAmount,
                    realToAmount,
                    info.dst1inch.swapRouter == address(0) ? 0 : 1,
                    fee
                );
            } catch {
                TransferHelper.safeApprove(weth, address(wooRouter), 0);
                TransferHelper.safeTransfer(weth, info.to, bridgedAmount);

                _safeCallCrossCompose(info, bridgedAmount);

                emit WooCrossSwapOnDstChain(
                    info.refId,
                    _msgSender(),
                    info.to,
                    weth,
                    bridgedAmount,
                    info.toToken,
                    weth,
                    info.minToAmount,
                    info.bridgedAmount,
                    info.dst1inch.swapRouter == address(0) ? 0 : 1,
                    0
                );
            }
        } else {
            TransferHelper.safeApprove(weth, address(wooRouter), info.bridgedAmount);
            try
                wooRouter.swap(weth, info.toToken, info.bridgedAmount, info.minToAmount, payable(info.to), info.to)
            returns (uint256 realToAmount) {
                _safeCallCrossCompose(info, realToAmount);
                emit WooCrossSwapOnDstChain(
                    info.refId,
                    _msgSender(),
                    info.to,
                    weth,
                    info.bridgedAmount,
                    info.toToken,
                    info.toToken,
                    info.minToAmount,
                    realToAmount,
                    info.dst1inch.swapRouter == address(0) ? 0 : 1,
                    0
                );
            } catch {
                TransferHelper.safeApprove(weth, address(wooRouter), 0);
                TransferHelper.safeTransfer(weth, info.to, bridgedAmount);

                _safeCallCrossCompose(info, bridgedAmount);

                emit WooCrossSwapOnDstChain(
                    info.refId,
                    _msgSender(),
                    info.to,
                    weth,
                    bridgedAmount,
                    info.toToken,
                    weth,
                    info.minToAmount,
                    bridgedAmount,
                    info.dst1inch.swapRouter == address(0) ? 0 : 1,
                    0
                );
            }
        }
    }

    function _handleERC20Received(ComposeInfo memory info) internal {
        uint256 bridgedAmount = info.bridgedAmount;

        if (info.toToken == info.bridgedToken) {
            TransferHelper.safeTransfer(info.bridgedToken, info.to, bridgedAmount);

            _safeCallCrossCompose(info, bridgedAmount);

            emit WooCrossSwapOnDstChain(
                info.refId,
                _msgSender(),
                info.to,
                info.bridgedToken,
                bridgedAmount,
                info.toToken,
                info.toToken,
                info.minToAmount,
                bridgedAmount,
                info.dst1inch.swapRouter == address(0) ? 0 : 1,
                0
            );
        } else {
            // Deduct the external swap fee
            uint256 fee = (bridgedAmount * dstExternalFeeRate) / FEE_BASE;
            bridgedAmount -= fee;

            TransferHelper.safeApprove(info.bridgedToken, address(wooRouter), bridgedAmount);
            if (info.dst1inch.swapRouter != address(0)) {
                try
                    wooRouter.externalSwap(
                        info.dst1inch.swapRouter,
                        info.dst1inch.swapRouter,
                        info.bridgedToken,
                        info.toToken,
                        bridgedAmount,
                        info.minToAmount,
                        payable(info.to),
                        info.dst1inch.data
                    )
                returns (uint256 realToAmount) {
                    _safeCallCrossCompose(info, realToAmount);

                    emit WooCrossSwapOnDstChain(
                        info.refId,
                        _msgSender(),
                        info.to,
                        info.bridgedToken,
                        bridgedAmount,
                        info.toToken,
                        info.toToken,
                        info.minToAmount,
                        realToAmount,
                        info.dst1inch.swapRouter == address(0) ? 0 : 1,
                        fee
                    );
                } catch {
                    bridgedAmount += fee;
                    TransferHelper.safeTransfer(info.bridgedToken, info.to, bridgedAmount);

                    _safeCallCrossCompose(info, bridgedAmount);

                    emit WooCrossSwapOnDstChain(
                        info.refId,
                        _msgSender(),
                        info.to,
                        info.bridgedToken,
                        bridgedAmount,
                        info.toToken,
                        info.bridgedToken,
                        info.minToAmount,
                        bridgedAmount,
                        info.dst1inch.swapRouter == address(0) ? 0 : 1,
                        0
                    );
                }
            } else {
                try
                    wooRouter.swap(
                        info.bridgedToken,
                        info.toToken,
                        bridgedAmount,
                        info.minToAmount,
                        payable(info.to),
                        info.to
                    )
                returns (uint256 realToAmount) {
                    _safeCallCrossCompose(info, realToAmount);
                    emit WooCrossSwapOnDstChain(
                        info.refId,
                        _msgSender(),
                        info.to,
                        info.bridgedToken,
                        bridgedAmount,
                        info.toToken,
                        info.toToken,
                        info.minToAmount,
                        realToAmount,
                        info.dst1inch.swapRouter == address(0) ? 0 : 1,
                        0
                    );
                } catch {
                    TransferHelper.safeTransfer(info.bridgedToken, info.to, bridgedAmount);
                    _safeCallCrossCompose(info, bridgedAmount);
                    emit WooCrossSwapOnDstChain(
                        info.refId,
                        _msgSender(),
                        info.to,
                        info.bridgedToken,
                        bridgedAmount,
                        info.toToken,
                        info.bridgedToken,
                        info.minToAmount,
                        bridgedAmount,
                        info.dst1inch.swapRouter == address(0) ? 0 : 1,
                        0
                    );
                }
            }
        }
    }

    function _safeCallLocalCompose(
        address payable composeTo,
        address toToken,
        uint256 amount,
        bytes memory payload
    ) internal {
        bytes memory callData = abi.encodeWithSelector(
            IWooSwapReceiver.wsLocalReceive.selector,
            toToken,
            amount,
            payload
        );

        uint256 externalGas = gasleft() - dstGasReserve;
        uint256 msgValue = 0;
        if (toToken == ETH_PLACEHOLDER_ADDR) {
            externalGas -= amount;
            msgValue += amount;
        }

        (bool safeCallSuccess, bytes memory reason) = composeTo.safeCall(externalGas, msgValue, 150, callData); // hardcode to 150 bytes for return value
        if (!safeCallSuccess) {
            emit WooSwapLocalComposeFailed(msg.sender, composeTo, toToken, amount, reason);
        }
    }

    function _safeCallCrossCompose(ComposeInfo memory info, uint256 amount) internal {
        bytes memory callData = abi.encodeWithSelector(
            IWooSwapReceiver.wsCrossReceive.selector,
            sgInfo.sgChainIdLocal(),
            info.srcAddr,
            info.refId,
            info.toToken,
            amount,
            info.composePayload
        );

        uint256 externalGas = gasleft() - dstGasReserve;
        uint256 msgValue = 0;
        if (info.toToken == ETH_PLACEHOLDER_ADDR) {
            externalGas -= amount;
            msgValue += amount;
        }

        (bool safeCallSuccess, bytes memory reason) = info.to.safeCall(externalGas, msgValue, 150, callData); // hardcode to 150 bytes for return value
        if (!safeCallSuccess) {
            emit WooSwapCrossComposeFailed(info.refId, info.srcAddr, info.to, info.toToken, amount, reason);
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
        require(_wooRouter != address(0), "WooSwapComposer: !_wooRouter");
        wooRouter = IWooRouterV2(_wooRouter);
    }

    function setBridgeSlippage(uint256 _bridgeSlippage) external onlyOwner {
        require(_bridgeSlippage <= 10000, "WooSwapComposer: !_bridgeSlippage");
        bridgeSlippage = _bridgeSlippage;
    }

    function setWooCrossRouter(uint16 _chainId, address _crossRouter) external onlyOwner {
        require(_crossRouter != address(0), "WooSwapComposer: !_crossRouter");
        wooCrossComposers[_chainId] = _crossRouter;
    }

    function setDstGasReserve(uint256 _dstGasReserve) external onlyOwner {
        dstGasReserve = _dstGasReserve;
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
