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
import {IStargateEthVault} from "../interfaces/Stargate/IStargateEthVault.sol";
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
        dstGasForSwapCall = 710000;
        dstGasForNoSwapCall = 430000;

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
        require(woofiDexVaults[dstInfos.chainId][dstInfos.toToken] != address(0), "WOOFiDexCrossChainRouter: dstInfos.chainId not allow");

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
            bytes memory payload = _getEncodePayload(nonce, to, dstInfos, dstVaultDeposit);
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
        uint256 amountLD,
        bytes memory payload
    ) external {
        address sender = _msgSender();
        require(sender == address(stargateRouter), "WOOFiDexCrossChainRouter: invalid sender");

        (
            uint256 nonce,
            address to,
            address toToken,
            uint256 minToAmount,
            DstVaultDeposit memory dstVaultDeposit
        ) = _getDecodePayload(payload);
        address woofiDexVault = woofiDexVaults[sgChainIdLocal][toToken];

        _handleERC20Received(
            srcChainId,
            nonce,
            sender,
            to,
            bridgedToken,
            amountLD,
            toToken,
            minToAmount,
            woofiDexVault,
            dstVaultDeposit
        );
    }

    function quoteLayerZeroFee(
        address to,
        SrcInfos calldata, // srcInfos
        DstInfos calldata dstInfos,
        DstVaultDeposit calldata dstVaultDeposit
    ) external view returns (uint256 nativeAmount, uint256 zroAmount) {
        uint256 nonce = nonceCounter.outboundNonce(dstInfos.chainId) + 1;
        bytes memory payload = _getEncodePayload(nonce, payable(to), dstInfos, dstVaultDeposit);


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

    function _initSgETHs() internal {}

    function _initSgPoolIds() internal {
        // poolId > 0 means able to be bridge token
        // Ethereum Goerli
        sgPoolIds[10121][0xDf0360Ad8C5ccf25095Aa97ee5F2785c8d848620] = 1; // USDC
        sgPoolIds[10121][0x5BCc22abEC37337630C0E0dd41D64fd86CaeE951] = 2; // USDT
        // BNB Chain Testnet
        sgPoolIds[10102][0xF49E250aEB5abDf660d643583AdFd0be41464EfD] = 2; // USDT
        sgPoolIds[10102][0x1010Bb1b9Dff29e6233E7947e045e0ba58f6E92e] = 5; // BUSD
        // Avalanche Fuji
        sgPoolIds[10106][0x4A0D1092E9df255cf95D72834Ea9255132782318] = 1; // USDC
        sgPoolIds[10106][0x134Dc38AE8C853D1aa2103d5047591acDAA16682] = 2; // USDT
        // Polygon Mumbai
        sgPoolIds[10109][0x742DfA5Aa70a8212857966D491D67B09Ce7D6ec7] = 1; // USDC
        sgPoolIds[10109][0x6Fc340be8e378c2fF56476409eF48dA9a3B781a0] = 2; // USDT
        // Arbitrum Goerli
        sgPoolIds[10143][0x6aAd876244E7A1Ad44Ec4824Ce813729E5B6C291] = 1; // USDC
        sgPoolIds[10143][0x533046F316590C19d99c74eE661c6d541b64471C] = 2; // USDT
        // Optimism Goerli
        sgPoolIds[10132][0x0CEDBAF2D0bFF895C861c5422544090EEdC653Bf] = 1; // USDC
        // Fantom Testnet
        sgPoolIds[10112][0x076488D244A73DA4Fa843f5A8Cd91F655CA81a1e] = 1; // USDC
        // Linea Goerli
        sgPoolIds[10157][0x78136C68561996d36a3B053C99c7ADC62B673644] = 1; // USDC
        // Base Goerli
        sgPoolIds[10160][0x5C8ef0FA2b094276520D25dEf4725F93467227bC] = 1; // USDC
    }

    function _getDstGasForCall(DstInfos memory dstInfos) internal view returns (uint256) {
        return (dstInfos.toToken == dstInfos.bridgedToken) ? dstGasForNoSwapCall : dstGasForSwapCall;
    }

    function _getLzTxObj(address to, DstInfos memory dstInfos) internal view returns (IStargateRouter.lzTxObj memory) {
        uint256 dstGasForCall = _getDstGasForCall(dstInfos);

        return IStargateRouter.lzTxObj(dstGasForCall, dstInfos.airdropNativeAmount, abi.encodePacked(to));
    }

    function _getEncodePayload(
        uint256 nonce,
        address payable to,
        DstInfos calldata dstInfos,
        DstVaultDeposit calldata dstVaultDeposit
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                nonce,
                to,
                dstInfos.toToken,
                dstInfos.minToAmount,
                dstVaultDeposit.accountId,
                dstVaultDeposit.brokerHash,
                dstVaultDeposit.tokenHash
            );
    }

    function _getDecodePayload(
        bytes memory payload
    ) internal pure returns (uint256, address, address, uint256, DstVaultDeposit memory) {
        (
            uint256 nonce,
            address to,
            address toToken,
            uint256 minToAmount,
            bytes32 accountId,
            bytes32 brokerHash,
            bytes32 tokenHash
        ) = abi.decode(payload, (uint256, address, address, uint256, bytes32, bytes32, bytes32));

        return (nonce, to, toToken, minToAmount, DstVaultDeposit(accountId, brokerHash, tokenHash));
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
            address sgETH = sgETHs[sgChainIdLocal];
            IStargateEthVault(sgETH).deposit{value: bridgeAmount}(); // logic from Stargate RouterETH.sol
            TransferHelper.safeApprove(sgETH, address(stargateRouter), bridgeAmount);
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
            IWOOFiDexVault.VaultDepositFE memory vaultDepositFE = IWOOFiDexVault.VaultDepositFE(
                dstVaultDeposit.accountId,
                dstVaultDeposit.brokerHash,
                dstVaultDeposit.tokenHash,
                uint128(bridgedAmount)
            );
            TransferHelper.safeApprove(toToken, woofiDexVault, bridgedAmount);
            IWOOFiDexVault(woofiDexVault).depositTo(to, vaultDepositFE);
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
                IWOOFiDexVault.VaultDepositFE memory vaultDepositFE = IWOOFiDexVault.VaultDepositFE(
                    dstVaultDeposit.accountId,
                    dstVaultDeposit.brokerHash,
                    dstVaultDeposit.tokenHash,
                    uint128(realToAmount)
                );
                TransferHelper.safeApprove(toToken, woofiDexVault, realToAmount);
                IWOOFiDexVault(woofiDexVault).depositTo(to, vaultDepositFE);
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
        require(woofiDexCrossChainRouter != address(0), "WOOFiDexCrossChainRouter: woofiDexCrossChainRouter cant be zero");
        woofiDexCrossChainRouters[chainId] = woofiDexCrossChainRouter;
    }

    function setWOOFiDexVault(uint16 chainId, address token, address woofiDexVault) external onlyOwner {
        require(woofiDexVault != address(0), "WOOFiDexCrossChainRouter: woofiDexVault cant be zero");
        woofiDexVaults[chainId][token] = woofiDexVault;
    }

    function setSgETH(uint16 chainId, address token) external onlyOwner {
        require(token != address(0), "WOOFiDexCrossChainRouter: token cant be zero");
        sgETHs[chainId] = token;
    }

    function setSgPoolId(uint16 chainId, address token, uint256 poolId) external onlyOwner {
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
