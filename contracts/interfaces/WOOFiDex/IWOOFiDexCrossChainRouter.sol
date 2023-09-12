// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

interface IWOOFiDexCrossChainRouter {
    /* ----- Structs ----- */

    struct SrcInfos {
        address fromToken;
        uint256 fromAmount;
        address bridgeToken;
        uint256 minBridgeAmount;
    }

    struct DstInfos {
        uint16 chainId;
        address bridgedToken;
        address toToken;
        uint256 minToAmount;
        uint256 airdropNativeAmount;
    }

    struct DstVaultDeposit {
        bytes32 accountId;
        bytes32 brokerHash;
        bytes32 tokenHash;
    }

    struct PoolIds {
        uint256 src;
        uint256 dst;
    }

    /* ----- Events ----- */

    event WOOFiDexCrossSwapOnSrcChain(
        uint16 dstChainId,
        uint256 indexed nonce,
        address indexed sender,
        address indexed to,
        address fromToken,
        uint256 fromAmount,
        address bridgeToken,
        uint256 minBridgeAmount,
        uint256 bridgeAmount
    );

    event WOOFiDexCrossSwapOnDstChain(
        uint16 srcChainId,
        uint256 indexed nonce,
        address indexed sender,
        address indexed to,
        address bridgedToken,
        uint256 bridgedAmount,
        address toToken,
        uint256 minToAmount,
        address realToToken,
        uint256 realToAmount,
        bytes32 accountId,
        bytes32 brokerHash,
        bytes32 tokenHash,
        uint128 tokenAmount
    );

    /* ----- State Variables ----- */

    function weth() external view returns (address);

    function bridgeSlippage() external view returns (uint256);

    function dstGasForSwapCall() external view returns (uint256);

    function dstGasForNoSwapCall() external view returns (uint256);

    function sgChainIdLocal() external view returns (uint16);

    function woofiDexCrossChainRouters(uint16 chainId) external view returns (address wooCrossChainRouter);

    function woofiDexVaults(uint16 chainId, address token) external view returns (address woofiDexVault);

    function sgETHs(uint16 chainId) external view returns (address sgETH);

    function sgPoolIds(uint16 chainId, address token) external view returns (uint256 poolId);

    /* ----- Functions ----- */

    function crossSwap(
        address payable to,
        SrcInfos calldata srcInfos,
        DstInfos calldata dstInfos,
        DstVaultDeposit calldata dstVaultDeposit
    ) external payable;

    function sgReceive(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint256 nonce,
        address bridgedToken,
        uint256 amountLD,
        bytes memory payload
    ) external;

    function quoteLayerZeroFee(
        address to,
        DstInfos memory dstInfos,
        DstVaultDeposit calldata dstVaultDeposit
    ) external view returns (uint256 nativeAmount, uint256 zroAmount);

    function allDirectBridgeTokens() external view returns (address[] memory tokens);

    function allDirectBridgeTokensLength() external view returns (uint256 length);
}
