// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IMasterChefWoo.sol";
import "./interfaces/IXWoo.sol";

contract MasterChefWoo is IMasterChefWoo, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    IERC20 public xWoo;
    uint256 public xWooPerBlock;
    uint256 public totalAllocPoint;
    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    EnumerableSet.AddressSet private weTokenSet;

    constructor(IERC20 _xWoo, uint256 _xWooPerBlock) {
        require(address(_xWoo) != address(0), "MCW: invalid address");
        require(_xWooPerBlock > 0, "MCW: invalid value");

        xWoo = _xWoo;
        xWooPerBlock = _xWooPerBlock;

        // staking pool
        poolInfo.push(
            PoolInfo({
                weToken: IERC20(address(0)),
                allocPoint: 0,
                lastRewardBlock: block.number,
                accTokenPerShare: 0,
                rewarder: IRewarder(address(0))
            })
        );

        totalAllocPoint = 0;
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

    function pendingXWoo(uint256 _pid, address _user) 
        external 
        override 
        view 
        returns (uint256 pendingXWooAmount, uint256 pendingWooAmount) 
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 weTokenSupply = pool.weToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && weTokenSupply != 0) {
            uint256 blocks = block.number - pool.lastRewardBlock;
            uint256 xWooReward = (blocks * xWooPerBlock * pool.allocPoint) / totalAllocPoint;
            accTokenPerShare += (xWooReward * 1e12) / weTokenSupply;
        }
        pendingXWooAmount = user.amount * accTokenPerShare / 1e12 - user.rewardDebt;
        uint256 rate = IXWoo(xWoo).getPricePerFullShare();
        pendingWooAmount =  pendingXWooAmount * rate / 1e18;
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
                uint256 xWooReward = (blocks * xWooPerBlock * pool.allocPoint) / totalAllocPoint;
                pool.accTokenPerShare += (xWooReward * 1e12) / weSupply;
            }
            pool.lastRewardBlock = block.number;
            emit PoolUpdated(_pid, pool.lastRewardBlock, weSupply, pool.accTokenPerShare);
        }
    }

    function setXWooPerBlock(uint256 _xWooPerBlock) external override onlyOwner {
        require(_xWooPerBlock > 0, "Invalid value");
        xWooPerBlock = _xWooPerBlock;

        emit XWooPerBlockUpdated(xWooPerBlock);
    }

    function deposit(uint256 _pid, uint256 _amount) external override nonReentrant {
        require(_pid != 0, "deposit woo by staking");
        require(_amount > 0, "Invalid deposit amount");

        updatePool(_pid);
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];

        if (user.amount > 0) {
            uint256 pending = (user.amount * pool.accTokenPerShare) / 1e12 - user.rewardDebt;
            if (pending > 0) {
                xWoo.safeTransfer(_msgSender(), pending);
            }
        }
        uint256 balanceBefore = pool.weToken.balanceOf(address(this));
        pool.weToken.safeTransferFrom(_msgSender(), address(this), _amount);
        uint256 receivedAmount = pool.weToken.balanceOf(address(this)) - balanceBefore;

        user.amount += receivedAmount;
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onRewarded(_msgSender(), user.amount);
        }

        emit Deposit(_msgSender(), _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) external override nonReentrant {
        require(_pid != 0, "withdraw WETOKEN by unstaking");
        updatePool(_pid);
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        require(user.amount >= _amount, "withdraw: not good");

        if (user.amount > 0) {
            uint256 pending = (user.amount * pool.accTokenPerShare) / 1e12 - user.rewardDebt;
            xWoo.safeTransfer(_msgSender(), pending);
        }
        user.amount -= _amount;
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onRewarded(_msgSender(), user.amount);
        }

        pool.weToken.safeTransfer(_msgSender(), _amount);

        emit Withdraw(_msgSender(), _pid, _amount);
    }

    function emergencyWithdraw(uint256 _pid) external override nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        emit EmergencyWithdraw(_msgSender(), _pid, user.amount);
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onRewarded(_msgSender(), 0);
        }
        pool.weToken.safeTransfer(_msgSender(), amount);
    }
}
