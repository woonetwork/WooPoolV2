// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

// OpenZeppelin Contracts
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// Uniswap Periphery
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

// Local Contracts
import {IStargateRouter} from "../interfaces/Stargate/IStargateRouter.sol";
import {INonceCounter} from "../interfaces/WOOFiDex/INonceCounter.sol";
import {IWOOFiDexCrossChainRouter} from "../interfaces/WOOFiDex/IWOOFiDexCrossChainRouter.sol";
import {IWOOFiDexVault} from "../interfaces/WOOFiDex/IWOOFiDexVault.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IWooRouterV2} from "../interfaces/IWooRouterV2.sol";

/// @title WOOFi Dex Router for Cross Chain and Same Chain Swap to Deposit
/// @custom:stargate-contracts https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses
contract WOOFiDexCrossChainRouter is IWOOFiDexCrossChainRouter, Ownable, Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ----- Constants ----- */

    address public constant NATIVE_PLACEHOLDER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public constant MAX_BRIDGE_SLIPPAGE = 10000;

    /* ----- Variables ----- */

    INonceCounter public nonceCounter;
    IWooRouterV2 public wooRouter;
    IStargateRouter public stargateRouter;

    address public immutable weth;
    uint256 public bridgeSlippage; // default 0.2%
    uint256 public dstGasForSwapCall;
    uint256 public dstGasForNoSwapCall;

    uint16 public sgChainIdLocal; // stargate chainId on local chain

    mapping(uint16 => address) public woofiDexCrossChainRouters; // chainId => WOOFiDexCrossChainRouter address
    mapping(uint16 => mapping(address => address)) public woofiDexVaults; // chainId => token address => WOOFiDexVault address
    mapping(uint16 => address) public sgETHs; // chainId => SGETH token address
    mapping(uint16 => mapping(address => uint256)) public sgPoolIds; // chainId => token address => Stargate poolId

    EnumerableSet.AddressSet private directBridgeTokens;

    receive() external payable {}

    constructor(
        address _weth,
        address _nonceCounter,
        address _wooRouter,
        address _stargateRouter,
        uint16 _sgChainIdLocal
    ) {
        nonceCounter = INonceCounter(_nonceCounter);
        wooRouter = IWooRouterV2(_wooRouter);
        stargateRouter = IStargateRouter(_stargateRouter);

        weth = _weth;
        bridgeSlippage = 20;
        dstGasForSwapCall = 750000;
        dstGasForNoSwapCall = 450000;

        sgChainIdLocal = _sgChainIdLocal;

        _initSgETHs();
        _initSgPoolIds();
    }

    /* ----- Functions ----- */

    function crossSwap(
        address payable to,
        SrcInfos calldata srcInfos,
        DstInfos calldata dstInfos,
        DstVaultDeposit calldata dstVaultDeposit
    ) external payable whenNotPaused nonReentrant {
        require(to != address(0), "WOOFiDexCrossChainRouter: to not allow");
        require(srcInfos.fromToken != address(0), "WOOFiDexCrossChainRouter: srcInfos.fromToken not allow");
        require(
            dstInfos.toToken != address(0) && dstInfos.toToken != sgETHs[dstInfos.chainId],
            "WOOFiDexCrossChainRouter: dstInfos.toToken not allow"
        );
        require(
            woofiDexVaults[dstInfos.chainId][dstInfos.toToken] != address(0),
            "WOOFiDexCrossChainRouter: dstInfos.chainId not allow"
        );

        address sender = _msgSender();
        uint256 nativeAmount = msg.value;
        uint256 bridgeAmount;

        {
            address srcFromToken = srcInfos.fromToken;
            if (srcFromToken == NATIVE_PLACEHOLDER) {
                require(srcInfos.fromAmount <= nativeAmount, "WOOFiDexCrossChainRouter: nativeAmount not enough");
                srcFromToken = weth;
                IWETH(weth).deposit{value: srcInfos.fromAmount}();
                nativeAmount -= srcInfos.fromAmount;
            } else {
                TransferHelper.safeTransferFrom(srcFromToken, sender, address(this), srcInfos.fromAmount);
            }

            if (!directBridgeTokens.contains(srcFromToken) && srcFromToken != srcInfos.bridgeToken) {
                TransferHelper.safeApprove(srcFromToken, address(wooRouter), srcInfos.fromAmount);
                bridgeAmount = wooRouter.swap(
                    srcFromToken,
                    srcInfos.bridgeToken,
                    srcInfos.fromAmount,
                    srcInfos.minBridgeAmount,
                    payable(address(this)),
                    to
                );
            } else {
                require(
                    srcInfos.fromAmount == srcInfos.minBridgeAmount,
                    "WOOFiDexCrossChainRouter: srcInfos.minBridgeAmount incorrect"
                );
                bridgeAmount = srcInfos.fromAmount;
            }

            require(
                bridgeAmount <= IERC20(srcInfos.bridgeToken).balanceOf(address(this)),
                "WOOFiDexCrossChainRouter: bridgeAmount exceed balance"
            );
        }

        uint256 nonce = nonceCounter.increment(dstInfos.chainId);
        {
            uint256 dstMinBridgedAmount = (bridgeAmount * (MAX_BRIDGE_SLIPPAGE - bridgeSlippage)) / MAX_BRIDGE_SLIPPAGE;
            bytes memory payload = abi.encode(nonce, to, dstInfos.toToken, dstInfos.minToAmount, dstVaultDeposit);
            _bridgeByStargate(to, nativeAmount, bridgeAmount, dstMinBridgedAmount, payload, srcInfos, dstInfos);
        }

        emit WOOFiDexCrossSwapOnSrcChain(
            dstInfos.chainId,
            nonce,
            sender,
            to,
            srcInfos.fromToken,
            srcInfos.fromAmount,
            srcInfos.bridgeToken,
            srcInfos.minBridgeAmount,
            bridgeAmount
        );
    }

    function sgReceive(
        uint16 srcChainId,
        bytes memory, // srcAddress
        uint256, // nonce
        address bridgedToken,
        uint256 bridgedAmount,
        bytes memory payload
    ) external {
        address sender = _msgSender();
        require(sender == address(stargateRouter), "WOOFiDexCrossChainRouter: invalid sender");

        (uint256 nonce, address to, address toToken, uint256 minToAmount, DstVaultDeposit memory dstVaultDeposit) = abi
            .decode(payload, (uint256, address, address, uint256, DstVaultDeposit));
        address woofiDexVault = woofiDexVaults[sgChainIdLocal][toToken];

        _handleERC20Received(
            srcChainId,
            nonce,
            sender,
            to,
            bridgedToken,
            bridgedAmount,
            toToken,
            minToAmount,
            woofiDexVault,
            dstVaultDeposit
        );
    }

    function quoteLayerZeroFee(
        address to,
        DstInfos calldata dstInfos,
        DstVaultDeposit calldata dstVaultDeposit
    ) external view returns (uint256 nativeAmount, uint256 zroAmount) {
        uint256 nonce = nonceCounter.outboundNonce(dstInfos.chainId) + 1;
        bytes memory payload = abi.encode(nonce, to, dstInfos.toToken, dstInfos.minToAmount, dstVaultDeposit);

        // only bridge via Stargate
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

    function _initSgETHs() internal {
        sgETHs[101] = 0x72E2F4830b9E45d52F80aC08CB2bEC0FeF72eD9c; // Ethereum
        sgETHs[110] = 0x82CbeCF39bEe528B5476FE6d1550af59a9dB6Fc0; // Arbitrum
        sgETHs[111] = 0xb69c8CBCD90A39D8D3d3ccf0a3E968511C3856A0; // Optimism
        sgETHs[183] = 0x224D8Fd7aB6AD4c6eb4611Ce56EF35Dec2277F03; // Linea
        sgETHs[184] = 0x224D8Fd7aB6AD4c6eb4611Ce56EF35Dec2277F03; // Base
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

    function _getDstGasForCall(DstInfos memory dstInfos) internal view returns (uint256) {
        return (dstInfos.toToken == dstInfos.bridgedToken) ? dstGasForNoSwapCall : dstGasForSwapCall;
    }

    function _getLzTxObj(address to, DstInfos memory dstInfos) internal view returns (IStargateRouter.lzTxObj memory) {
        uint256 dstGasForCall = _getDstGasForCall(dstInfos);

        return IStargateRouter.lzTxObj(dstGasForCall, dstInfos.airdropNativeAmount, abi.encodePacked(to));
    }

    function _bridgeByStargate(
        address payable to,
        uint256 nativeAmount,
        uint256 bridgeAmount,
        uint256 dstMinBridgedAmount,
        bytes memory payload,
        SrcInfos calldata srcInfos,
        DstInfos calldata dstInfos
    ) internal {
        // avoid stack too deep
        PoolIds memory poolIds;
        {
            poolIds = PoolIds(
                sgPoolIds[sgChainIdLocal][srcInfos.bridgeToken],
                sgPoolIds[dstInfos.chainId][dstInfos.bridgedToken]
            );
        }
        require(poolIds.src > 0, "WOOFiDexCrossChainRouter: poolIds.src not exist");
        require(poolIds.dst > 0, "WOOFiDexCrossChainRouter: poolIds.dst not exist");

        if (srcInfos.bridgeToken == weth) {
            IWETH(weth).withdraw(bridgeAmount);
            nativeAmount += bridgeAmount;
        } else {
            TransferHelper.safeApprove(srcInfos.bridgeToken, address(stargateRouter), bridgeAmount);
        }

        IStargateRouter.lzTxObj memory obj = _getLzTxObj(to, dstInfos);
        stargateRouter.swap{value: nativeAmount}(
            dstInfos.chainId, // dst chain id
            poolIds.src, // bridge token's pool id on src chain
            poolIds.dst, // bridge token's pool id on dst chain
            payable(_msgSender()), // rebate address
            bridgeAmount, // swap amount on src chain
            dstMinBridgedAmount, // min received amount on dst chain
            obj, // config: dstGasForCall, dstNativeAmount, dstNativeAddr
            abi.encodePacked(woofiDexCrossChainRouters[dstInfos.chainId]), // smart contract to call on dst chain
            payload // payload to piggyback
        );
    }

    function _depositTo(
        address to,
        address toToken,
        address woofiDexVault,
        DstVaultDeposit memory dstVaultDeposit,
        uint256 tokenAmount
    ) internal returns (IWOOFiDexVault.VaultDepositFE memory) {
        IWOOFiDexVault.VaultDepositFE memory vaultDepositFE = IWOOFiDexVault.VaultDepositFE(
            dstVaultDeposit.accountId,
            dstVaultDeposit.brokerHash,
            dstVaultDeposit.tokenHash,
            uint128(tokenAmount)
        );
        TransferHelper.safeApprove(toToken, woofiDexVault, tokenAmount);
        IWOOFiDexVault(woofiDexVault).depositTo(to, vaultDepositFE);

        return vaultDepositFE;
    }

    function _handleERC20Received(
        uint16 srcChainId,
        uint256 nonce,
        address sender,
        address to,
        address bridgedToken,
        uint256 bridgedAmount,
        address toToken,
        uint256 minToAmount,
        address woofiDexVault,
        DstVaultDeposit memory dstVaultDeposit
    ) internal {
        if (toToken == bridgedToken) {
            IWOOFiDexVault.VaultDepositFE memory vaultDepositFE = _depositTo(
                to,
                toToken,
                woofiDexVault,
                dstVaultDeposit,
                bridgedAmount
            );
            emit WOOFiDexCrossSwapOnDstChain(
                srcChainId,
                nonce,
                sender,
                to,
                bridgedToken,
                bridgedAmount,
                toToken,
                minToAmount,
                toToken,
                bridgedAmount,
                vaultDepositFE.accountId,
                vaultDepositFE.brokerHash,
                vaultDepositFE.tokenHash,
                vaultDepositFE.tokenAmount
            );
        } else {
            TransferHelper.safeApprove(bridgedToken, address(wooRouter), bridgedAmount);
            try wooRouter.swap(bridgedToken, toToken, bridgedAmount, minToAmount, payable(address(this)), to) returns (
                uint256 realToAmount
            ) {
                IWOOFiDexVault.VaultDepositFE memory vaultDepositFE = _depositTo(
                    to,
                    toToken,
                    woofiDexVault,
                    dstVaultDeposit,
                    realToAmount
                );
                emit WOOFiDexCrossSwapOnDstChain(
                    srcChainId,
                    nonce,
                    sender,
                    to,
                    bridgedToken,
                    bridgedAmount,
                    toToken,
                    minToAmount,
                    toToken,
                    realToAmount,
                    vaultDepositFE.accountId,
                    vaultDepositFE.brokerHash,
                    vaultDepositFE.tokenHash,
                    vaultDepositFE.tokenAmount
                );
            } catch {
                TransferHelper.safeTransfer(bridgedToken, to, bridgedAmount);
                emit WOOFiDexCrossSwapOnDstChain(
                    srcChainId,
                    nonce,
                    sender,
                    to,
                    bridgedToken,
                    bridgedAmount,
                    toToken,
                    minToAmount,
                    bridgedToken,
                    bridgedAmount,
                    bytes32(0),
                    bytes32(0),
                    bytes32(0),
                    0
                );
            }
        }
    }

    /* ----- Owner & Admin Functions ----- */

    function setWooRouter(address _wooRouter) external onlyOwner {
        require(_wooRouter != address(0), "WOOFiDexCrossChainRouter: _wooRouter cant be zero");
        wooRouter = IWooRouterV2(_wooRouter);
    }

    function setStargateRouter(address _stargateRouter) external onlyOwner {
        require(_stargateRouter != address(0), "WOOFiDexCrossChainRouter: _stargateRouter cant be zero");
        stargateRouter = IStargateRouter(_stargateRouter);
    }

    function setBridgeSlippage(uint256 _bridgeSlippage) external onlyOwner {
        require(_bridgeSlippage <= MAX_BRIDGE_SLIPPAGE, "WOOFiDexCrossChainRouter: _bridgeSlippage exceed max");
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

    function setWOOFiDexCrossChainRouter(uint16 chainId, address woofiDexCrossChainRouter) external onlyOwner {
        require(
            woofiDexCrossChainRouter != address(0),
            "WOOFiDexCrossChainRouter: woofiDexCrossChainRouter cant be zero"
        );
        woofiDexCrossChainRouters[chainId] = woofiDexCrossChainRouter;
    }

    function setWOOFiDexVault(
        uint16 chainId,
        address token,
        address woofiDexVault
    ) external onlyOwner {
        require(woofiDexVault != address(0), "WOOFiDexCrossChainRouter: woofiDexVault cant be zero");
        woofiDexVaults[chainId][token] = woofiDexVault;
    }

    function setSgETH(uint16 chainId, address token) external onlyOwner {
        require(token != address(0), "WOOFiDexCrossChainRouter: token cant be zero");
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
        require(success, "WOOFiDexCrossChainRouter: token exist");
    }

    function removeDirectBridgeToken(address token) external onlyOwner {
        bool success = directBridgeTokens.remove(token);
        require(success, "WOOFiDexCrossChainRouter: token not exist");
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        address sender = _msgSender();
        if (stuckToken == NATIVE_PLACEHOLDER) {
            TransferHelper.safeTransferETH(sender, address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, sender, amount);
        }
    }
}
