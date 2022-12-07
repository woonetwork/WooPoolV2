// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IRewarder.sol";

interface IMasterChefReward {
    event PoolAdded(uint256 poolId, uint256 allocPoint, IERC20 weToken, IRewarder rewarder);
    event PoolSet(uint256 poolId, uint256 allocPoint, IRewarder rewarder);
    event PoolUpdated(uint256 poolId, uint256 lastRewardBlock, uint256 supply, uint256 accTokenPerShare);
    event RewardPerBlockUpdated(uint256 rewardPerBlock);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IERC20 weToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accTokenPerShare;
        IRewarder rewarder;
    }

    // System-level function
    function setRewardPerBlock(uint256 _rewardPerBlock) external;

    // Pool-related functions
    function poolLength() external view returns (uint256);

    function add(
        uint256 allocPoint,
        IERC20 weToken,
        IRewarder rewarder
    ) external;

    function set(
        uint256 pid,
        uint256 allocPoint,
        IRewarder rewarder
    ) external;

    function massUpdatePools() external;

    function updatePool(uint256 pid) external;

    // User-related functions
    function pendingReward(uint256 pid, address user)
        external
        view
        returns (uint256 pendingRewardAmount, uint256 pendingRewarderTokens);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function harvest(uint256 pid) external;

    function emergencyWithdraw(uint256 pid) external;

    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);

    function poolInfo(uint256 pid)
        external
        view
        returns (
            IERC20 weToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accTokenPerShare,
            IRewarder rewarder
        );
}
