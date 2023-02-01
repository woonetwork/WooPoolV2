// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

// OpenZeppelin Contracts
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// Local Contracts
import "./interfaces/IWooCrossChainRouterV2.sol";
import "./interfaces/IWooRouterV2.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/Stargate/IStargateRouter.sol";

import "./libraries/TransferHelper.sol";

/// @title WOOFi cross chain router implementation.
/// @notice Router for stateless execution of cross chain swap against WOOFi private pool.
/// @custom:stargate-contracts https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
contract WooCrossChainRouterV2 is IWooCrossChainRouterV2, Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ----- Constants ----- */

    address public constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ----- Variables ----- */

    IWooRouterV2 public wooRouter;
    IStargateRouter public stargateRouter;

    address public override weth;
    uint256 public override bridgeSlippage; // 1 in 10000th: default 1%
    uint256 public override dstGasForSwapCall;
    uint256 public override dstGasForNoSwapCall;

    uint16 public override sglChainId; // Stargate Local ChainId

    mapping(uint16 => address) public override wooCrossChainRouters; // chainId => WooCrossChainRouter address
    mapping(uint16 => address) public override sgETHs; // chainId => SGETH token address

    EnumerableSet.AddressSet private directBridgeTokens;

    receive() external payable {}

    constructor(
        address _weth,
        address _wooRouter,
        address _stargateRouter,
        uint16 _sglChainId
    ) {
        wooRouter = IWooRouterV2(_wooRouter);
        stargateRouter = IStargateRouter(_stargateRouter);

        weth = _weth;
        bridgeSlippage = 100;
        dstGasForSwapCall = 360000;
        dstGasForNoSwapCall = 80000;

        sglChainId = _sglChainId;

        _initSGETHs();
    }

    /* ----- Functions ----- */

    /** 
        Example Params:
        OP(Optimism) -> ETH(Optimism) -> ETH(Arbitrum)
        srcInfos.chainId = 111
        srcInfos.poolId = 13
        srcInfos.fromToken = OP(Optimism)
        srcInfos.bridgeToken = ETH(Optimism)

        dstInfos.chainId = 110
        dstInfos.poolId = 13
        dstInfos.toToken = ETH(Arbitrum)
        dstInfos.bridgeToken = ETH(Arbitrum)
    */
    function crossSwap(
        uint256 refId,
        address payable to,
        SrcInfos memory srcInfos,
        DstInfos memory dstInfos
    ) external payable override {
        require(srcInfos.fromToken != address(0), "WooCrossChainRouterV2: !srcInfos.fromToken");
        require(dstInfos.toToken != address(0), "WooCrossChainRouterV2: !dstInfos.toToken");
        require(to != address(0), "WooCrossChainRouterV2: !to");

        address msgSender = _msgSender();
        uint256 msgValue = msg.value;
        uint256 bridgeAmount;

        {
            // Step 1: transfer
            if (srcInfos.fromToken == ETH_PLACEHOLDER_ADDR) {
                require(srcInfos.fromAmount <= msgValue, "WooCrossChainRouterV2: !srcInfos.fromAmount");
                srcInfos.fromToken = weth;
                IWETH(srcInfos.fromToken).deposit{value: srcInfos.fromAmount}();
                msgValue -= srcInfos.fromAmount;
            } else {
                TransferHelper.safeTransferFrom(srcInfos.fromToken, msg.sender, address(this), srcInfos.fromAmount);
            }

            // Step 2: local swap by WooRouter or not
            // 1.WOO is directBridgeToken, path(always) WOO(Arbitrum) => WOO(BSC)
            // 2.WOO not the directBridgeToken, path(maybe): WOO(Arbitrum) -> ETH(Arbitrum) => ETH(BSC) -> WOO(BSC)
            // 3.Ethereum no WOOFi liquidity, tokens(WOO, ETH, USDC) always will be bridged directly without swap
            if (!directBridgeTokens.contains(srcInfos.fromToken) && srcInfos.fromToken != srcInfos.bridgeToken) {
                TransferHelper.safeApprove(srcInfos.fromToken, address(wooRouter), srcInfos.fromAmount);
                bridgeAmount = wooRouter.swap(
                    srcInfos.fromToken,
                    srcInfos.bridgeToken,
                    srcInfos.fromAmount,
                    srcInfos.minBridgeAmount,
                    payable(address(this)),
                    to
                );
            } else {
                require(
                    srcInfos.fromAmount == srcInfos.minBridgeAmount,
                    "WooCrossChainRouterV2: !srcInfos.minBridgeAmount"
                );
                bridgeAmount = srcInfos.fromAmount;
            }
            require(
                bridgeAmount <= IERC20(srcInfos.bridgeToken).balanceOf(address(this)),
                "WooCrossChainRouterV2: !bridgeAmount"
            );
        }

        {
            // Step 3: cross chain swap by StargateRouter
            bytes memory payload = _encodePayload(refId, to, dstInfos);

            uint256 dstMinBridgeAmount = (bridgeAmount * (10000 - bridgeSlippage)) / 10000;
            bytes memory dstWooCrossChainRouter = abi.encodePacked(wooCrossChainRouters[dstInfos.chainId]);

            IStargateRouter.lzTxObj memory obj = _getLzTxObj(to, dstInfos);

            TransferHelper.safeApprove(srcInfos.bridgeToken, address(stargateRouter), bridgeAmount);
            stargateRouter.swap{value: msgValue}(
                dstInfos.chainId, // dst chain id
                srcInfos.poolId, // bridge token's pool id on src chain
                dstInfos.poolId, // bridge token's pool id on dst chain
                payable(msgSender), // rebate address
                bridgeAmount, // swap amount on src chain
                dstMinBridgeAmount, // min received amount on dst chain
                obj, // config: dstGasForCall, dstAirdropNativeAmount, dstReceiveAirdropNativeTokenAddr
                dstWooCrossChainRouter, // smart contract to call on dst chain
                payload // payload to piggyback
            );
        }

        emit WooCrossSwapOnSrcChain(
            refId,
            msgSender,
            to,
            srcInfos.fromToken,
            srcInfos.fromAmount,
            srcInfos.minBridgeAmount,
            bridgeAmount
        );
    }

    function sgReceive(
        uint16, // srcChainId
        bytes memory, // srcAddress
        uint256, // nonce
        address bridgedToken,
        uint256 amountLD,
        bytes memory payload
    ) external override {
        require(msg.sender == address(stargateRouter), "WooCrossChainRouterV2: INVALID_CALLER");

        (uint256 refId, address to, address toToken, uint256 minToAmount) = _decodePayload(payload);

        // When bridged by ETH, the bridgedToken will be SGETH ERC20 address and send native token to address(this)
        if (toToken == ETH_PLACEHOLDER_ADDR && bridgedToken == sgETHs[sglChainId]) {
            TransferHelper.safeTransferETH(to, amountLD);
            emit WooCrossSwapOnDstChain(
                refId,
                msg.sender,
                to,
                ETH_PLACEHOLDER_ADDR,
                amountLD,
                toToken,
                ETH_PLACEHOLDER_ADDR,
                minToAmount,
                amountLD
            );
            return;
        }

        if (toToken == bridgedToken) {
            TransferHelper.safeTransfer(bridgedToken, to, amountLD);
            emit WooCrossSwapOnDstChain(
                refId,
                msg.sender,
                to,
                bridgedToken,
                amountLD,
                toToken,
                bridgedToken,
                minToAmount,
                amountLD
            );
            return;
        }

        if (bridgedToken == sgETHs[sglChainId]) {
            // Bridged by ETH, and toToken is not ETH, holding ETH assets, require swap to toToken
            try
                wooRouter.swap{value: amountLD}(ETH_PLACEHOLDER_ADDR, toToken, amountLD, minToAmount, payable(to), to)
            returns (uint256 realToAmount) {
                emit WooCrossSwapOnDstChain(
                    refId,
                    msg.sender,
                    to,
                    ETH_PLACEHOLDER_ADDR,
                    amountLD,
                    toToken,
                    toToken,
                    minToAmount,
                    realToAmount
                );
            } catch {
                TransferHelper.safeTransferETH(to, amountLD);
                emit WooCrossSwapOnDstChain(
                    refId,
                    msg.sender,
                    to,
                    ETH_PLACEHOLDER_ADDR,
                    amountLD,
                    toToken,
                    ETH_PLACEHOLDER_ADDR,
                    minToAmount,
                    amountLD
                );
            }
        } else {
            // Bridged by ERC20 token, holding ERC20 token assets, require swap to toToken(can be ETH)
            // TODO: Discuss this situation: bridgedToken(BUSD), toToken(USDT), not support stable coin swap now on WooRouter
            // Waste gas by code below?
            TransferHelper.safeApprove(bridgedToken, address(wooRouter), amountLD);
            try wooRouter.swap(bridgedToken, toToken, amountLD, minToAmount, payable(to), to) returns (
                uint256 realToAmount
            ) {
                emit WooCrossSwapOnDstChain(
                    refId,
                    msg.sender,
                    to,
                    bridgedToken,
                    amountLD,
                    toToken,
                    toToken,
                    minToAmount,
                    realToAmount
                );
            } catch {
                TransferHelper.safeTransfer(bridgedToken, to, amountLD);
                emit WooCrossSwapOnDstChain(
                    refId,
                    msg.sender,
                    to,
                    bridgedToken,
                    amountLD,
                    toToken,
                    bridgedToken,
                    minToAmount,
                    amountLD
                );
            }
        }
    }

    function quoteLayerZeroFee(
        uint256 refId,
        address to,
        DstInfos memory dstInfos
    ) external view override returns (uint256, uint256) {
        bytes memory payload = _encodePayload(refId, to, dstInfos);

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

    function allDirectBridgeTokens() external view override returns (address[] memory) {
        uint256 length = directBridgeTokens.length();
        address[] memory tokens = new address[](length);
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                tokens[i] = directBridgeTokens.at(i);
            }
        }
        return tokens;
    }

    function allDirectBridgeTokensLength() external view override returns (uint256) {
        return directBridgeTokens.length();
    }

    function _initSGETHs() internal {
        sgETHs[101] = 0x72E2F4830b9E45d52F80aC08CB2bEC0FeF72eD9c;
        sgETHs[110] = 0x82CbeCF39bEe528B5476FE6d1550af59a9dB6Fc0;
        sgETHs[111] = 0xb69c8CBCD90A39D8D3d3ccf0a3E968511C3856A0;
    }

    function _getLzTxObj(address to, DstInfos memory dstInfos) internal view returns (IStargateRouter.lzTxObj memory) {
        uint256 dstGasForCall = (dstInfos.toToken == dstInfos.bridgeToken) ? dstGasForNoSwapCall : dstGasForSwapCall;

        return IStargateRouter.lzTxObj(dstGasForCall, dstInfos.airdropNativeAmount, abi.encodePacked(to));
    }

    function _encodePayload(
        uint256 refId,
        address to,
        DstInfos memory dstInfos
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                refId, // reference id
                to, // address for receive tokens
                dstInfos.toToken, // to token on dst chain
                dstInfos.minToAmount // minToAmount on dst chain
            );
    }

    function _decodePayload(bytes memory payload)
        internal
        pure
        returns (
            uint256,
            address,
            address,
            uint256
        )
    {
        return abi.decode(payload, (uint256, address, address, uint256));
    }

    /* ----- Owner & Admin Functions ----- */

    function setWooRouter(address _wooRouter) external onlyOwner {
        require(_wooRouter != address(0), "WooCrossChainRouterV2: !_wooRouter");
        wooRouter = IWooRouterV2(_wooRouter);
    }

    function setStargateRouter(address _stargateRouter) external onlyOwner {
        require(_stargateRouter != address(0), "WooCrossChainRouterV2: !_stargateRouter");
        stargateRouter = IStargateRouter(_stargateRouter);
    }

    function setBridgeSlippage(uint256 _bridgeSlippage) external onlyOwner {
        require(_bridgeSlippage <= 10000, "WooCrossChainRouterV2: !_bridgeSlippage");
        bridgeSlippage = _bridgeSlippage;
    }

    function setDstGasForSwapCall(uint256 _dstGasForSwapCall) external onlyOwner {
        dstGasForSwapCall = _dstGasForSwapCall;
    }

    function setDstGasForNoSwapCall(uint256 _dstGasForNoSwapCall) external onlyOwner {
        dstGasForNoSwapCall = _dstGasForNoSwapCall;
    }

    function setSGLChainId(uint16 _sglChainId) external onlyOwner {
        sglChainId = _sglChainId;
    }

    function setWooCrossChainRouter(uint16 chainId, address wooCrossChainRouter) external onlyOwner {
        require(wooCrossChainRouter != address(0), "WooCrossChainRouterV2: !wooCrossChainRouter");
        wooCrossChainRouters[chainId] = wooCrossChainRouter;
    }

    function setSGETH(uint16 chainId, address token) external onlyOwner {
        sgETHs[chainId] = token;
    }

    function addDirectBridgeToken(address token) external onlyOwner {
        bool success = directBridgeTokens.add(token);
        require(success, "WooCrossChainRouterV2: token exist");
    }

    function removeDirectBridgeToken(address token) external onlyOwner {
        bool success = directBridgeTokens.remove(token);
        require(success, "WooCrossChainRouterV2: token not exist");
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
