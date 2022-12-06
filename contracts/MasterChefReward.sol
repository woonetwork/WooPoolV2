// SPDX-License-Identifier: MIT

pragma solidity =0.8.14;

/*

░██╗░░░░░░░██╗░█████╗░░█████╗░░░░░░░███████╗██╗
░██║░░██╗░░██║██╔══██╗██╔══██╗░░░░░░██╔════╝██║
░╚██╗████╗██╔╝██║░░██║██║░░██║█████╗█████╗░░██║
░░████╔═████║░██║░░██║██║░░██║╚════╝██╔══╝░░██║
░░╚██╔╝░╚██╔╝░╚█████╔╝╚█████╔╝░░░░░░██║░░░░░██║
░░░╚═╝░░░╚═╝░░░╚════╝░░╚════╝░░░░░░░╚═╝░░░░░╚═╝

*
* MIT License
* ===========
*
* Copyright (c) 2020 WooTrade
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IMasterChefReward.sol";
import "./libraries/TransferHelper.sol";

contract MasterChefReward is IMasterChefReward, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IERC20 public immutable reward;
    uint256 public rewardPerBlock;
    uint256 public totalAllocPoint;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    EnumerableSet.AddressSet private weTokenSet;

    constructor(IERC20 _reward, uint256 _rewardPerBlock) {
        reward = _reward;
        rewardPerBlock = _rewardPerBlock;
    }

    function poolLength() public view override returns (uint256) {
        return poolInfo.length;
    }

    function add(
        uint256 _allocPoint,
        IERC20 _weToken,
        IRewarder _rewarder
    ) external override onlyOwner {
        require(!weTokenSet.contains(address(_weToken)), "MCW: already added");
        // Sanity check to ensure _lpToken is an ERC20 token
        _weToken.balanceOf(address(this));
        // Sanity check if we add a rewarder
        if (address(_rewarder) != address(0)) {
            _rewarder.onRewarded(address(0), 0);
        }

        totalAllocPoint += _allocPoint;
        poolInfo.push(
            PoolInfo({
                weToken: _weToken,
                allocPoint: _allocPoint,
                lastRewardBlock: block.number,
                accTokenPerShare: 0,
                rewarder: _rewarder
            })
        );
        weTokenSet.add(address(_weToken));

        emit PoolAdded(poolLength() - 1, _allocPoint, _weToken, _rewarder);
    }

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        IRewarder _rewarder
    ) external override onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.allocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint + _allocPoint - pool.allocPoint;
            pool.allocPoint = _allocPoint;
        }

        if (address(_rewarder) != address(pool.rewarder)) {
            if (address(_rewarder) != address(0)) {
                _rewarder.onRewarded(address(0), 0);
            }
            pool.rewarder = _rewarder;
        }

        emit PoolSet(_pid, _allocPoint, pool.rewarder);
    }

    function pendingReward(uint256 _pid, address _user)
        external
        view
        override
        returns (uint256 pendingRewardAmount, uint256 pendingRewarderTokens)
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 weTokenSupply = pool.weToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && weTokenSupply != 0) {
            uint256 blocks = block.number - pool.lastRewardBlock;
            uint256 totalRewardAmount = (blocks * rewardPerBlock * pool.allocPoint) / totalAllocPoint;
            accTokenPerShare += (totalRewardAmount * 1e12) / weTokenSupply;
        }
        pendingRewardAmount = (user.amount * accTokenPerShare) / 1e12 - user.rewardDebt;

        IRewarder rewarder = pool.rewarder;
        pendingRewarderTokens = address(rewarder) != address(0) ? rewarder.pendingTokens(_user) : 0;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public override {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public override {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number > pool.lastRewardBlock) {
            uint256 weSupply = pool.weToken.balanceOf(address(this));
            if (weSupply > 0) {
                uint256 blocks = block.number - pool.lastRewardBlock;
                uint256 totalRewardAmount = (blocks * rewardPerBlock * pool.allocPoint) / totalAllocPoint;
                pool.accTokenPerShare += (totalRewardAmount * 1e12) / weSupply;
            }
            pool.lastRewardBlock = block.number;
            emit PoolUpdated(_pid, pool.lastRewardBlock, weSupply, pool.accTokenPerShare);
        }
    }

    function setRewardPerBlock(uint256 _rewardPerBlock) external override onlyOwner {
        require(_rewardPerBlock > 0, "Invalid value");
        massUpdatePools();
        rewardPerBlock = _rewardPerBlock;

        emit RewardPerBlockUpdated(_rewardPerBlock);
    }

    function deposit(uint256 _pid, uint256 _amount) external override nonReentrant {
        updatePool(_pid);
        address caller = _msgSender();
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][caller];

        if (user.amount > 0) {
            // Harvest reward
            uint256 pending = (user.amount * pool.accTokenPerShare) / 1e12 - user.rewardDebt;
            reward.safeTransfer(caller, pending);
            emit Harvest(caller, _pid, pending);
        }

        user.amount += _amount;
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onRewarded(caller, user.amount);
        }

        pool.weToken.safeTransferFrom(caller, address(this), _amount);

        emit Deposit(caller, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) external override nonReentrant {
        require(_amount > 0, "MCW: invalid value");
        updatePool(_pid);
        address caller = _msgSender();
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][caller];
        require(user.amount >= _amount, "MCW: !amount");

        if (user.amount > 0) {
            uint256 pending = (user.amount * pool.accTokenPerShare) / 1e12 - user.rewardDebt;
            reward.safeTransfer(caller, pending);
        }
        user.amount -= _amount;
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onRewarded(caller, user.amount);
        }

        pool.weToken.safeTransfer(caller, _amount);

        emit Withdraw(caller, _pid, _amount);
    }

    function harvest(uint256 _pid) external override nonReentrant {
        updatePool(_pid);
        address caller = _msgSender();
        UserInfo storage user = userInfo[_pid][caller];
        PoolInfo memory pool = poolInfo[_pid];

        uint256 totalReward = (user.amount * pool.accTokenPerShare) / 1e12;
        uint256 pending = totalReward - user.rewardDebt;

        // Effects
        user.rewardDebt = totalReward;

        // Interactions
        reward.safeTransfer(caller, pending);

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onRewarded(caller, user.amount);
        }

        emit Harvest(caller, _pid, pending);
    }

    function emergencyWithdraw(uint256 _pid) external override nonReentrant {
        address caller = _msgSender();
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][caller];
        emit EmergencyWithdraw(caller, _pid, user.amount);
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onRewarded(caller, 0);
        }
        pool.weToken.safeTransfer(caller, amount);
    }

    /// @dev Rescue the specified funds when stuck happens
    /// @param stuckToken the stuck token address
    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        require(stuckToken != address(0), "MCW: !address");
        require(!weTokenSet.contains(stuckToken), "MCW: !staked_token");
        if (stuckToken == ETH_PLACEHOLDER_ADDR) {
            TransferHelper.safeTransferETH(_msgSender(), address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, _msgSender(), amount);
        }
    }
}
