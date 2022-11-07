// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

interface IVaultV2 {
    function want() external view returns (address);

    function weth() external view returns (address);

    function deposit(uint256 amount) external payable;

    function withdraw(uint256 shares) external;

    function earn() external;

    function available() external view returns (uint256);

    function balance() external view returns (uint256);

    function getPricePerFullShare() external view returns (uint256);
}
