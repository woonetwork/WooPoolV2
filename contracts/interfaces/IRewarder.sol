// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewarder {
    event OnRewarded(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    struct PoolInfo {
        uint256 accTokenPerShare;
        uint256 lastRewardBlock;
    }

    function onRewarded(address user, uint256 amount) external;

    function pendingTokens(address user) external view returns (uint256);
}
