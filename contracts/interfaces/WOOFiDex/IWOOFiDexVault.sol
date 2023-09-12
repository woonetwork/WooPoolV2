// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

interface IWOOFiDexVault {
    struct VaultDepositFE {
        bytes32 accountId;
        bytes32 brokerHash;
        bytes32 tokenHash;
        uint128 tokenAmount;
    }

    function depositTo(address receiver, VaultDepositFE calldata data) external;
}
