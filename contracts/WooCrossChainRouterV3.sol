// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

// OpenZeppelin Contracts
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// Local Contracts
import {IWETH} from "./interfaces/IWETH.sol";
import {IWooCrossChainRouterV3} from "./interfaces/IWooCrossChainRouterV3.sol";
import {IWooRouterV2} from "./interfaces/IWooRouterV2.sol";
import {IStargateEthVault} from "./interfaces/Stargate/IStargateEthVault.sol";
import {IStargateRouter} from "./interfaces/Stargate/IStargateRouter.sol";
import {ILzApp} from "./interfaces/LayerZero/ILzApp.sol";

import {TransferHelper} from "./libraries/TransferHelper.sol";

/// @title cross chain router implementation, version 3.
/// @notice Router for stateless execution of cross chain swap against WOOFi or 1inch swap.
/// @custom:stargate-contracts https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
contract WooCrossChainRouterV3 is IWooCrossChainRouterV3, Ownable, Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ----- Constants ----- */

    address public constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ----- Variables ----- */

    IWooRouterV2 public wooRouter;
    IStargateRouter public stargateRouter;

    address public immutable weth;
    address public feeAddr;
    uint256 public bridgeSlippage; // 1 in 10000th: default 1%
    uint256 public dstGasForSwapCall;
    uint256 public dstGasForNoSwapCall;

    uint16 public sgChainIdLocal; // Stargate chainId on local chain
    uint16 public srcExternalFeeRate; // unit: 0.1 bps (1e6 = 100%, 25 = 2.5 bps)
    uint16 public dstExternalFeeRate; // unit: 0.1 bps (1e6 = 100%, 25 = 2.5 bps)
    uint256 public constant FEE_BASE = 1e5;

    mapping(uint16 => address) public wooCrossRouters; // chainId => WooCrossChainRouterV3 address
    mapping(uint16 => address) public sgETHs; // chainId => SGETH token address
    mapping(uint16 => mapping(address => uint256)) public sgPoolIds; // chainId => token address => Stargate poolId

    receive() external payable {}

    constructor(
        address _weth,
        address _wooRouter,
        address _stargateRouter,
        uint16 _sgChainIdLocal
    ) {
        weth = _weth;
        wooRouter = IWooRouterV2(_wooRouter);
        stargateRouter = IStargateRouter(_stargateRouter);
        sgChainIdLocal = _sgChainIdLocal;

        bridgeSlippage = 100;
        dstGasForSwapCall = 660000;
        dstGasForNoSwapCall = 80000;

        srcExternalFeeRate = 25;
        dstExternalFeeRate = 25;

        _initSgETHs();
        _initSgPoolIds();
    }

    function _initSgETHs() internal {
        // Ethereum
        sgETHs[101] = 0x72E2F4830b9E45d52F80aC08CB2bEC0FeF72eD9c;
        // Arbitrum
        sgETHs[110] = 0x82CbeCF39bEe528B5476FE6d1550af59a9dB6Fc0;
        // Optimism
        sgETHs[111] = 0xb69c8CBCD90A39D8D3d3ccf0a3E968511C3856A0;
        // Linea
        sgETHs[183] = 0x224D8Fd7aB6AD4c6eb4611Ce56EF35Dec2277F03;
        // Base
        sgETHs[184] = 0x224D8Fd7aB6AD4c6eb4611Ce56EF35Dec2277F03;
    }

    function _initSgPoolIds() internal {
        // poolId > 0 means able to be bridge token
        // Ethereum
        sgPoolIds[101][0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 1; // USDC
        sgPoolIds[101][0xdAC17F958D2ee523a2206206994597C13D831ec7] = 2; // USDT
        sgPoolIds[101][0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 13; // WETH
        sgPoolIds[101][0x4691937a7508860F876c9c0a2a617E7d9E945D4B] = 20; // WOO
        // BNB Chain
        sgPoolIds[102][0x55d398326f99059fF775485246999027B3197955] = 2; // USDT
        sgPoolIds[102][0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56] = 5; // BUSD
        sgPoolIds[102][0x4691937a7508860F876c9c0a2a617E7d9E945D4B] = 20; // WOO
        // Avalanche
        sgPoolIds[106][0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E] = 1; // USDC
        sgPoolIds[106][0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7] = 2; // USDT
        sgPoolIds[106][0xaBC9547B534519fF73921b1FBA6E672b5f58D083] = 20; // WOO
        // Polygon
        sgPoolIds[109][0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174] = 1; // USDC
        sgPoolIds[109][0xc2132D05D31c914a87C6611C10748AEb04B58e8F] = 2; // USDT
        sgPoolIds[109][0x1B815d120B3eF02039Ee11dC2d33DE7aA4a8C603] = 20; // WOO
        // Arbitrum
        sgPoolIds[110][0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8] = 1; // USDC
        sgPoolIds[110][0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9] = 2; // USDT
        sgPoolIds[110][0x82aF49447D8a07e3bd95BD0d56f35241523fBab1] = 13; // WETH
        sgPoolIds[110][0xcAFcD85D8ca7Ad1e1C6F82F651fA15E33AEfD07b] = 20; // WOO
        // Optimism
        sgPoolIds[111][0x7F5c764cBc14f9669B88837ca1490cCa17c31607] = 1; // USDC
        sgPoolIds[111][0x4200000000000000000000000000000000000006] = 13; // WETH
        sgPoolIds[111][0x871f2F2ff935FD1eD867842FF2a7bfD051A5E527] = 20; // WOO
        // Fantom
        sgPoolIds[112][0x04068DA6C83AFCFA0e13ba15A6696662335D5B75] = 1; // USDC
        sgPoolIds[112][0x6626c47c00F1D87902fc13EECfaC3ed06D5E8D8a] = 20; // WOO
        // Linea
        sgPoolIds[183][0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f] = 13; // WETH
        // Base
        sgPoolIds[184][0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA] = 1; // USDC
        sgPoolIds[184][0x4200000000000000000000000000000000000006] = 13; // WETH
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
        require(srcInfos.fromToken != address(0), "WooCrossChainRouterV3: !srcInfos.fromToken");
        require(
            dstInfos.toToken != address(0) && dstInfos.toToken != sgETHs[dstInfos.chainId],
            "WooCrossChainRouterV3: !dstInfos.toToken"
        );
        require(to != address(0), "WooCrossChainRouterV3: !to");

        uint256 msgValue = msg.value;
        uint256 bridgeAmount;
        uint256 fee = 0;

        {
            // Step 1: transfer
            if (srcInfos.fromToken == ETH_PLACEHOLDER_ADDR) {
                require(srcInfos.fromAmount <= msgValue, "WooCrossChainRouterV3: !srcInfos.fromAmount");
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
                    "WooCrossChainRouterV3: !srcInfos.minBridgeAmount"
                );
                bridgeAmount = srcInfos.fromAmount;
            }

            require(
                bridgeAmount <= IERC20(srcInfos.bridgeToken).balanceOf(address(this)),
                "WooCrossChainRouterV3: !bridgeAmount"
            );
        }

        // Step 3: deduct the swap fee
        bridgeAmount -= fee;

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
        require(msg.sender == address(stargateRouter), "WooCrossChainRouterV3: INVALID_CALLER");

        // make sure the same order to abi.encode when decode payload
        (uint256 refId, address to, address toToken, uint256 minToAmount, Dst1inch memory dst1inch) = abi.decode(
            payload,
            (uint256, address, address, uint256, Dst1inch)
        );

        // toToken won't be SGETH, and bridgedToken won't be ETH_PLACEHOLDER_ADDR
        if (bridgedToken == sgETHs[sgChainIdLocal]) {
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
        IStargateRouter.lzTxObj memory obj = _getLzTxObj(to, dstInfos);
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
        require(feeAddr != address(0), "WooCrossChainRouterV3: !feeAddr");
        uint256 amount = _generalBalanceOf(token, address(this));
        if (amount > 0) {
            if (token == ETH_PLACEHOLDER_ADDR) {
                TransferHelper.safeTransferETH(feeAddr, amount);
            } else {
                TransferHelper.safeTransfer(token, feeAddr, amount);
            }
        }
    }

    function _getDstGasForCall(DstInfos memory dstInfos) internal view returns (uint256) {
        return (dstInfos.toToken == dstInfos.bridgeToken) ? dstGasForNoSwapCall : dstGasForSwapCall;
    }

    function _getAdapterParams(
        address to,
        address oft,
        uint256 dstGasForCall,
        DstInfos memory dstInfos
    ) internal view returns (bytes memory) {
        // OFT src logic: require(providedGasLimit >= minGasLimit)
        // uint256 minGasLimit = minDstGasLookup[_dstChainId][_type] + dstGasForCall;
        // _type: 0(send), 1(send_and_call)
        uint256 providedGasLimit = ILzApp(oft).minDstGasLookup(dstInfos.chainId, 1) + dstGasForCall;

        // https://layerzero.gitbook.io/docs/evm-guides/advanced/relayer-adapter-parameters#airdrop
        return
            abi.encodePacked(
                uint16(2), // version: 2 is able to airdrop native token on destination but 1 is not
                providedGasLimit, // gasAmount: destination transaction gas for LayerZero to delivers
                dstInfos.airdropNativeAmount, // nativeForDst: airdrop native token amount
                to // addressOnDst: address to receive airdrop native token on destination
            );
    }

    function _getLzTxObj(address to, DstInfos memory dstInfos) internal view returns (IStargateRouter.lzTxObj memory) {
        uint256 dstGasForCall = _getDstGasForCall(dstInfos);

        return IStargateRouter.lzTxObj(dstGasForCall, dstInfos.airdropNativeAmount, abi.encodePacked(to));
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
        require(sgPoolIds[sgChainIdLocal][srcInfos.bridgeToken] > 0, "WooCrossChainRouterV3: !srcInfos.bridgeToken");
        require(sgPoolIds[dstInfos.chainId][dstInfos.bridgeToken] > 0, "WooCrossChainRouterV3: !dstInfos.bridgeToken");

        bytes memory payload = abi.encode(refId, to, dstInfos.toToken, dstInfos.minToAmount, dst1inch);

        uint256 dstMinBridgeAmount = (bridgeAmount * (10000 - bridgeSlippage)) / 10000;
        bytes memory dstWooCrossChainRouter = abi.encodePacked(wooCrossRouters[dstInfos.chainId]);

        IStargateRouter.lzTxObj memory obj = _getLzTxObj(to, dstInfos);

        if (srcInfos.bridgeToken == weth) {
            IWETH(weth).withdraw(bridgeAmount);
            msgValue += bridgeAmount;
        } else {
            TransferHelper.safeApprove(srcInfos.bridgeToken, address(stargateRouter), bridgeAmount);
        }

        stargateRouter.swap{value: msgValue}(
            dstInfos.chainId, // dst chain id
            sgPoolIds[sgChainIdLocal][srcInfos.bridgeToken], // bridge token's pool id on src chain
            sgPoolIds[dstInfos.chainId][dstInfos.bridgeToken], // bridge token's pool id on dst chain
            payable(_msgSender()), // rebate address
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
        } else {
            if (dst1inch.swapRouter != address(0)) {
                IWETH(weth).deposit{value: bridgedAmount}();
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
                        bridgedAmount,
                        toToken,
                        toToken,
                        minToAmount,
                        realToAmount,
                        dst1inch.swapRouter == address(0) ? 0 : 1,
                        fee
                    );
                } catch {
                    IWETH(weth).withdraw(bridgedAmount);
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
                }
            } else {
                try
                    wooRouter.swap{value: bridgedAmount}(
                        ETH_PLACEHOLDER_ADDR,
                        toToken,
                        bridgedAmount,
                        minToAmount,
                        payable(to),
                        to
                    )
                returns (uint256 realToAmount) {
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
                }
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
            // Deduct the external swap fee
            uint256 fee = (bridgedAmount * dstExternalFeeRate) / FEE_BASE;
            bridgedAmount -= fee;

            TransferHelper.safeApprove(bridgedToken, address(wooRouter), bridgedAmount);
            if (dst1inch.swapRouter != address(0)) {
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
        require(_wooRouter != address(0), "WooCrossChainRouterV3: !_wooRouter");
        wooRouter = IWooRouterV2(_wooRouter);
    }

    function setStargateRouter(address _stargateRouter) external onlyOwner {
        require(_stargateRouter != address(0), "WooCrossChainRouterV3: !_stargateRouter");
        stargateRouter = IStargateRouter(_stargateRouter);
    }

    function setBridgeSlippage(uint256 _bridgeSlippage) external onlyOwner {
        require(_bridgeSlippage <= 10000, "WooCrossChainRouterV3: !_bridgeSlippage");
        bridgeSlippage = _bridgeSlippage;
    }

    function setDstGasForSwapCall(uint256 _dstGasForSwapCall) external onlyOwner {
        dstGasForSwapCall = _dstGasForSwapCall;
    }

    function setDstGasForNoSwapCall(uint256 _dstGasForNoSwapCall) external onlyOwner {
        dstGasForNoSwapCall = _dstGasForNoSwapCall;
    }

    function setSgChainIdLocal(uint16 _sgChainIdLocal) external onlyOwner {
        sgChainIdLocal = _sgChainIdLocal;
    }

    function setWooCrossRouter(uint16 _chainId, address _crossRouter) external onlyOwner {
        require(_crossRouter != address(0), "WooCrossChainRouterV3: !_crossRouter");
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
