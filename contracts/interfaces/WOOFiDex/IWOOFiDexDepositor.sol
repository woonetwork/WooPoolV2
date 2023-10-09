// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

interface IWOOFiDexDepositor {
    /* ----- Structs ----- */

    struct Infos {
        address fromToken;
        uint256 fromAmount;
        address toToken;
        uint256 minToAmount;
    }

    struct VaultDeposit {
        bytes32 accountId;
        bytes32 brokerHash;
        bytes32 tokenHash;
    }

    /* ----- Events ----- */

    event WOOFiDexSwap(
        address indexed sender,
        address indexed to,
        address fromToken,
        uint256 fromAmount,
        address toToken,
        uint256 minToAmount,
        uint256 toAmount,
        bytes32 accountId,
        bytes32 brokerHash,
        bytes32 tokenHash,
        uint128 tokenAmount
    );

    /* ----- State Variables ----- */

    function weth() external view returns (address);

    function woofiDexVaults(address token) external view returns (address woofiDexVault);

    /* ----- Functions ----- */

    function swap(
        address payable to,
        Infos calldata infos,
        VaultDeposit calldata vaultDeposit
    ) external payable;
}
