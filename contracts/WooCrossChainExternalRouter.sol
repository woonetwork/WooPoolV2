// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

// OpenZeppelin Contracts
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// Local Contracts
import {IWETH} from "./interfaces/IWETH.sol";
import {IWooCrossChainExternalRouter} from "./interfaces/IWooCrossChainExternalRouter.sol";
import {IWooCrossChainRouterV2} from "./interfaces/IWooCrossChainRouterV2.sol";
import {IWooRouterV2} from "./interfaces/IWooRouterV2.sol";
import {IStargateEthVault} from "./interfaces/Stargate/IStargateEthVault.sol";
import {IStargateRouter} from "./interfaces/Stargate/IStargateRouter.sol";
import {ILzApp} from "./interfaces/LayerZero/ILzApp.sol";

import {TransferHelper} from "./libraries/TransferHelper.sol";

/// @title cross chain router implementation.
/// @notice Router for stateless execution of cross chain swap against 1inch swap.
/// @custom:stargate-contracts https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
contract WooCrossChainExternalRouter is IWooCrossChainExternalRouter, Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ----- Constants ----- */

    address public constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ----- Variables ----- */

    IWooCrossChainRouterV2 public crossRouter;
    IWooRouterV2 public wooRouter;
    IStargateRouter public stargateRouter;

    address public immutable weth;
    uint256 public bridgeSlippage; // 1 in 10000th: default 1%
    uint256 public dstGasForSwapCall;
    uint256 public dstGasForNoSwapCall;

    uint16 public sgChainIdLocal; // Stargate chainId on local chain

    mapping(uint16 => address) public wooCrossExternalRouters; // chainId => WooCrossChainExternalRouter address
    mapping(uint16 => address) public sgETHs; // chainId => SGETH token address
    mapping(uint16 => mapping(address => uint256)) public sgPoolIds; // chainId => token address => Stargate poolId

    EnumerableSet.AddressSet private directBridgeTokens;

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
    }

    function _initSgPoolIds() internal {
        // poolId > 0 means able to be bridge token
        // Ethereum
        sgPoolIds[101][0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 1; // USDC
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
    }

    /* ----- Functions ----- */

    function crossExternalSwap(
        uint256 refId,
        address payable to,
        SrcInfos memory srcInfos,
        DstInfos calldata dstInfos,
        Src1inch calldata src1inch,
        Dst1inch calldata dst1inch
    ) external payable nonReentrant {
        require(srcInfos.fromToken != address(0), "WooCrossChainExternalRouter: !srcInfos.fromToken");
        require(
            dstInfos.toToken != address(0) && dstInfos.toToken != sgETHs[dstInfos.chainId],
            "WooCrossChainExternalRouter: !dstInfos.toToken"
        );
        require(to != address(0), "WooCrossChainExternalRouter: !to");

        uint256 msgValue = msg.value;
        uint256 bridgeAmount;

        {
            // Step 1: transfer
            if (srcInfos.fromToken == ETH_PLACEHOLDER_ADDR) {
                require(srcInfos.fromAmount <= msgValue, "WooCrossChainExternalRouter: !srcInfos.fromAmount");
                srcInfos.fromToken = weth;
                IWETH(weth).deposit{value: srcInfos.fromAmount}();
                msgValue -= srcInfos.fromAmount;
            } else {
                TransferHelper.safeTransferFrom(srcInfos.fromToken, msg.sender, address(this), srcInfos.fromAmount);
            }

            // Step 2: local swap by 1inch router
            if (!directBridgeTokens.contains(srcInfos.fromToken) && srcInfos.fromToken != srcInfos.bridgeToken) {
                TransferHelper.safeApprove(srcInfos.fromToken, address(wooRouter), srcInfos.fromAmount);
                if (src1inch.swapRouter != address(0)) {
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
                    "WooCrossChainExternalRouter: !srcInfos.minBridgeAmount"
                );
                bridgeAmount = srcInfos.fromAmount;
            }

            require(
                bridgeAmount <= IERC20(srcInfos.bridgeToken).balanceOf(address(this)),
                "WooCrossChainExternalRouter: !bridgeAmount"
            );
        }

        // Step 3: cross chain swap by StargateRouter
        _bridgeByStargate(refId, to, msgValue, bridgeAmount, srcInfos, dstInfos, dst1inch);

        emit WooCrossSwapOnSrcChain(
            refId,
            _msgSender(),
            to,
            srcInfos.fromToken,
            srcInfos.fromAmount,
            srcInfos.minBridgeAmount,
            bridgeAmount,
            src1inch.swapRouter == address(0) ? 0 : 1
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
        require(msg.sender == address(stargateRouter), "WooCrossChainExternalRouter: INVALID_CALLER");

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

    function allDirectBridgeTokens() external view returns (address[] memory) {
        uint256 length = directBridgeTokens.length();
        address[] memory tokens = new address[](length);
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                tokens[i] = directBridgeTokens.at(i);
            }
        }
        return tokens;
    }

    function allDirectBridgeTokensLength() external view returns (uint256) {
        return directBridgeTokens.length();
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
        require(
            sgPoolIds[sgChainIdLocal][srcInfos.bridgeToken] > 0,
            "WooCrossChainExternalRouter: !srcInfos.bridgeToken"
        );
        require(
            sgPoolIds[dstInfos.chainId][dstInfos.bridgeToken] > 0,
            "WooCrossChainExternalRouter: !dstInfos.bridgeToken"
        );

        bytes memory payload = abi.encode(refId, to, dstInfos.toToken, dstInfos.minToAmount, dst1inch);

        uint256 dstMinBridgeAmount = (bridgeAmount * (10000 - bridgeSlippage)) / 10000;
        bytes memory dstWooCrossChainRouter = abi.encodePacked(wooCrossExternalRouters[dstInfos.chainId]);

        IStargateRouter.lzTxObj memory obj = _getLzTxObj(to, dstInfos);

        if (srcInfos.bridgeToken == weth) {
            IWETH(weth).withdraw(bridgeAmount);
            address sgETH = sgETHs[sgChainIdLocal];
            IStargateEthVault(sgETH).deposit{value: bridgeAmount}(); // logic from Stargate RouterETH.sol
            TransferHelper.safeApprove(sgETH, address(stargateRouter), bridgeAmount);
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
                dst1inch.swapRouter == address(0) ? 0 : 1
            );
        } else {
            if (dst1inch.swapRouter != address(0)) {
                try
                    wooRouter.externalSwap{value: bridgedAmount}(
                        dst1inch.swapRouter,
                        dst1inch.swapRouter,
                        ETH_PLACEHOLDER_ADDR,
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
                        weth,
                        bridgedAmount,
                        toToken,
                        toToken,
                        minToAmount,
                        realToAmount,
                        dst1inch.swapRouter == address(0) ? 0 : 1
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
                        dst1inch.swapRouter == address(0) ? 0 : 1
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
                        dst1inch.swapRouter == address(0) ? 0 : 1
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
                        dst1inch.swapRouter == address(0) ? 0 : 1
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
                dst1inch.swapRouter == address(0) ? 0 : 1
            );
        } else {
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
                        dst1inch.swapRouter == address(0) ? 0 : 1
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
                        dst1inch.swapRouter == address(0) ? 0 : 1
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
                        dst1inch.swapRouter == address(0) ? 0 : 1
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
                        dst1inch.swapRouter == address(0) ? 0 : 1
                    );
                }
            }
        }
    }

    /* ----- Owner & Admin Functions ----- */

    function setWooRouter(address _wooRouter) external onlyOwner {
        require(_wooRouter != address(0), "WooCrossChainExternalRouter: !_wooRouter");
        wooRouter = IWooRouterV2(_wooRouter);
    }

    function setStargateRouter(address _stargateRouter) external onlyOwner {
        require(_stargateRouter != address(0), "WooCrossChainExternalRouter: !_stargateRouter");
        stargateRouter = IStargateRouter(_stargateRouter);
    }

    function setBridgeSlippage(uint256 _bridgeSlippage) external onlyOwner {
        require(_bridgeSlippage <= 10000, "WooCrossChainExternalRouter: !_bridgeSlippage");
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

    function setWooCrossExternalRouter(uint16 chainId, address wooCrossExternalRouter) external onlyOwner {
        require(wooCrossExternalRouter != address(0), "WooCrossChainExternalRouter: !wooCrossExternalRouter");
        wooCrossExternalRouters[chainId] = wooCrossExternalRouter;
    }

    function addDirectBridgeToken(address token) external onlyOwner {
        bool success = directBridgeTokens.add(token);
        require(success, "WooCrossChainExternalRouter: token exist");
    }

    function removeDirectBridgeToken(address token) external onlyOwner {
        bool success = directBridgeTokens.remove(token);
        require(success, "WooCrossChainExternalRouter: token not exist");
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
