// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IRewarder.sol";

interface IMasterChefWoo {
    event PoolAdded(uint256 poolId, uint256 allocPoint, IERC20 weToken, IRewarder rewarder);
    event PoolSet(uint256 poolId, uint256 allocPoint, IRewarder rewarder);
    event PoolUpdated(uint256 poolId, uint256 lastRewardBlock, uint256 supply, uint256 accTokenPerShare);
    event XWooPerBlockUpdated(uint256 xWooPerBlock);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
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
    function setXWooPerBlock(uint256 _xWooPerBlock) external;

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
    function pendingXWoo(uint256 pid, address user) external view returns (uint256, uint256);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function emergencyWithdraw(uint256 pid) external;
}
