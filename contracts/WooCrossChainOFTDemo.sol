// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

// OpenZeppelin Contracts
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IOFTV2} from "@layerzerolabs/solidity-examples/contracts/token/oft/v2/IOFTV2.sol";

// Local Contracts
import "./interfaces/IWETH.sol";
import "./interfaces/IWooCrossChainRouterV2.sol";
import "./interfaces/IWooRouterV2.sol";
import "./interfaces/Stargate/IStargateEthVault.sol";
import "./interfaces/Stargate/IStargateRouter.sol";
import {ICommonOFT, IOFTWithFee} from "./interfaces/LayerZero/IOFTWithFee.sol";

import "./libraries/TransferHelper.sol";

/// @title WOOFi cross chain router implementation.
/// @notice Router for stateless execution of cross chain swap against WOOFi private pool.
/// @custom:stargate-contracts https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
contract WooCrossChainOFTDemo is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    event WooCrossSwapOnSrcChain(
        uint256 indexed refId,
        address indexed sender,
        address indexed to,
        address fromToken,
        uint256 fromAmount,
        uint256 minBridgeAmount,
        uint256 realBridgeAmount
    );

    event WooCrossSwapOnDstChain(
        uint256 indexed refId,
        address indexed sender,
        address indexed to,
        address bridgedToken,
        uint256 bridgedAmount,
        address toToken,
        address realToToken,
        uint256 minToAmount,
        uint256 realToAmount
    );

    /* ----- Constants ----- */

    address public constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ----- Variables ----- */

    IWooRouterV2 public wooRouter;

    address public immutable weth;
    uint256 public bridgeSlippage; // 1 in 10000th: default 1%
    uint256 public dstGasForSwapCall;
    uint256 public dstGasForNoSwapCall;

    // uint256 public dstGas; // for lz delivers the dst txn

    uint16 public sgChainIdLocal; // Stargate chainId on local chain

    mapping(uint16 => address) public wooCrossChainRouters; // chainId => WooCrossChainRouter address
    mapping(uint16 => address) public sgETHs; // chainId => SGETH token address
    mapping(uint16 => mapping(address => uint256)) public sgPoolIds; // chainId => token address => Stargate poolId

    EnumerableSet.AddressSet private directBridgeTokens;

    mapping(uint16 => mapping(address => bool)) public isProxyOFT;
    mapping(uint16 => mapping(address => bool)) public allowOnOFTReceived;

    receive() external payable {}

    constructor(
        address _weth,
        address _wooRouter,
        uint16 _sgChainIdLocal
    ) {
        wooRouter = IWooRouterV2(_wooRouter);

        weth = _weth;
        bridgeSlippage = 100;
        dstGasForSwapCall = 360000;
        dstGasForNoSwapCall = 80000;

        sgChainIdLocal = _sgChainIdLocal;

        _initSgETHs();
        _initSgPoolIds();
        _initIsProxyOFT();
        _initAllowOnOFTReceived();
    }

    /* ----- Functions ----- */

    function crossSwap(
        uint256 refId,
        address oft,
        uint16 dstChainId,
        address to,
        uint256 amountToSwap,
        address toToken,
        uint256 minToAmount,
        uint256 nativeForDst
    ) external payable nonReentrant {
        uint256 minAmount = (amountToSwap * (10000 - bridgeSlippage)) / 10000;

        bytes memory payload = abi.encode(refId, to, toToken, minToAmount);
        bytes memory adapterParams;
        {
            uint256 dstGas = IOFTWithFee(oft).minDstGasLookup(dstChainId, 1) + dstGasForSwapCall;
            adapterParams = abi.encodePacked(uint16(2), dstGas, nativeForDst, to);
        }

        ICommonOFT.LzCallParams memory callParams = ICommonOFT.LzCallParams(
            payable(msg.sender),
            address(0),
            adapterParams
        );

        if (isProxyOFT[sgChainIdLocal][oft]) {
            address token = IOFTV2(oft).token();
            TransferHelper.safeTransferFrom(token, msg.sender, address(this), amountToSwap);
            TransferHelper.safeApprove(token, oft, amountToSwap);
        } else {
            TransferHelper.safeTransferFrom(oft, msg.sender, address(this), amountToSwap);
        }

        bytes32 dstWooCrossChainRouter = bytes32(uint256(uint160(wooCrossChainRouters[dstChainId])));
        IOFTWithFee(oft).sendAndCall{value: msg.value}(
            address(this),
            dstChainId,
            dstWooCrossChainRouter,
            amountToSwap,
            minAmount,
            payload,
            uint64(dstGasForSwapCall),
            callParams
        );
    }

    function onOFTReceived(
        uint16 srcChainId,
        bytes memory, // srcAddress
        uint64, // nonce
        bytes32 from,
        uint256 amountLD,
        bytes memory payload
    ) external {
        address oft = _msgSender();
        require(allowOnOFTReceived[sgChainIdLocal][oft], "WooCrossChainRouterV2: INVALID_CALLER");
        require(
            wooCrossChainRouters[srcChainId] == address(uint160(uint256(from))),
            "WooCrossChainRouterV2: INVALID_FROM"
        );
        // msgSender should be OFT address if requires above is passed

        // make sure the same order to _encodePayload() when decode payload
        (uint256 refId, address to, address toToken, uint256 minToAmount) = abi.decode(
            payload,
            (uint256, address, address, uint256)
        );

        address bridgedToken;
        if (isProxyOFT[sgChainIdLocal][oft]) {
            bridgedToken = IOFTV2(oft).token();
        } else {
            bridgedToken = oft;
        }

        // workaround for stack too deep
        uint256 bridgedAmount = amountLD;

        if (toToken == bridgedToken) {
            TransferHelper.safeTransfer(bridgedToken, to, bridgedAmount);
            emit WooCrossSwapOnDstChain(
                refId,
                msg.sender,
                to,
                bridgedToken,
                bridgedAmount,
                toToken,
                toToken,
                minToAmount,
                bridgedAmount
            );
        } else {
            TransferHelper.safeApprove(bridgedToken, address(wooRouter), bridgedAmount);
            try wooRouter.swap(bridgedToken, toToken, bridgedAmount, minToAmount, payable(to), to) returns (
                uint256 realToAmount
            ) {
                emit WooCrossSwapOnDstChain(
                    refId,
                    msg.sender,
                    to,
                    bridgedToken,
                    bridgedAmount,
                    toToken,
                    toToken,
                    minToAmount,
                    realToAmount
                );
            } catch {
                TransferHelper.safeTransfer(bridgedToken, to, bridgedAmount);
                emit WooCrossSwapOnDstChain(
                    refId,
                    msg.sender,
                    to,
                    bridgedToken,
                    bridgedAmount,
                    toToken,
                    bridgedToken,
                    minToAmount,
                    bridgedAmount
                );
            }
        }
    }

    function quoteLayerZeroFee(
        uint256 refId,
        address oft,
        uint16 dstChainId,
        address to,
        uint256 amountToSwap,
        address toToken,
        uint256 minToAmount,
        uint256 nativeForDst
    ) external view returns (uint256, uint256) {
        bytes memory payload = abi.encode(refId, to, toToken, minToAmount);
        uint256 dstGas = IOFTWithFee(oft).minDstGasLookup(dstChainId, 1) + dstGasForSwapCall;
        bytes memory adapterParams = abi.encodePacked(uint16(2), dstGas, nativeForDst, to);

        bool useZro = false;
        bytes32 toAddress = bytes32(uint256(uint160(to)));
        return
            IOFTWithFee(oft).estimateSendAndCallFee(
                dstChainId,
                toAddress,
                amountToSwap,
                payload,
                uint64(dstGasForSwapCall),
                useZro,
                adapterParams
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
        // BNB Chain
        sgPoolIds[102][0x55d398326f99059fF775485246999027B3197955] = 2; // USDT
        sgPoolIds[102][0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56] = 5; // BUSD
        // Avalanche
        sgPoolIds[106][0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E] = 1; // USDC
        sgPoolIds[106][0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7] = 2; // USDT
        // Polygon
        sgPoolIds[109][0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174] = 1; // USDC
        sgPoolIds[109][0xc2132D05D31c914a87C6611C10748AEb04B58e8F] = 2; // USDT
        // Arbitrum
        sgPoolIds[110][0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8] = 1; // USDC
        sgPoolIds[110][0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9] = 2; // USDT
        sgPoolIds[110][0x82aF49447D8a07e3bd95BD0d56f35241523fBab1] = 13; // WETH
        // Optimism
        sgPoolIds[111][0x7F5c764cBc14f9669B88837ca1490cCa17c31607] = 1; // USDC
        sgPoolIds[111][0x4200000000000000000000000000000000000006] = 13; // WETH
        // Fantom
        sgPoolIds[112][0x04068DA6C83AFCFA0e13ba15A6696662335D5B75] = 1; // USDC
    }

    function _initIsProxyOFT() internal {
        // Avalanche: BTCbProxyOFT
        isProxyOFT[106][0x2297aEbD383787A160DD0d9F71508148769342E3] = true;
    }

    function _initAllowOnOFTReceived() internal {
        // Ethereum: BTCbOFT
        allowOnOFTReceived[101][0x2297aEbD383787A160DD0d9F71508148769342E3] = true;
        // BNB Chain: BTCbOFT
        allowOnOFTReceived[102][0x2297aEbD383787A160DD0d9F71508148769342E3] = true;
        // Avalanche: BTCbProxyOFT
        allowOnOFTReceived[106][0x2297aEbD383787A160DD0d9F71508148769342E3] = true;
        // Polygon: BTCbOFT
        allowOnOFTReceived[109][0x2297aEbD383787A160DD0d9F71508148769342E3] = true;
        // Arbitrum: BTCbOFT
        allowOnOFTReceived[110][0x2297aEbD383787A160DD0d9F71508148769342E3] = true;
        // Optimism: BTCbOFT
        allowOnOFTReceived[111][0x2297aEbD383787A160DD0d9F71508148769342E3] = true;
    }

    /* ----- Owner & Admin Functions ----- */

    function setWooRouter(address _wooRouter) external onlyOwner {
        require(_wooRouter != address(0), "WooCrossChainRouterV2: !_wooRouter");
        wooRouter = IWooRouterV2(_wooRouter);
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

    function setSgChainIdLocal(uint16 _sgChainIdLocal) external onlyOwner {
        sgChainIdLocal = _sgChainIdLocal;
    }

    function setWooCrossChainRouter(uint16 chainId, address wooCrossChainRouter) external onlyOwner {
        require(wooCrossChainRouter != address(0), "WooCrossChainRouterV2: !wooCrossChainRouter");
        wooCrossChainRouters[chainId] = wooCrossChainRouter;
    }

    function setSgETH(uint16 chainId, address token) external onlyOwner {
        require(token != address(0), "WooCrossChainRouterV2: !token");
        sgETHs[chainId] = token;
    }

    function setSgPoolId(
        uint16 chainId,
        address token,
        uint256 poolId
    ) external onlyOwner {
        sgPoolIds[chainId][token] = poolId;
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
