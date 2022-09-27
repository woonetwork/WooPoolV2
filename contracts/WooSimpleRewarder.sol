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

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IRewarder.sol";
import "./interfaces/IMasterChefWoo.sol";
import "./libraries/TransferHelper.sol";

contract WooSimpleRewarder is IRewarder, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    address public constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    IERC20 public immutable weToken;
    IERC20 public immutable rewardToken;
    IMasterChefWoo public immutable MCW; // MasterChefWoo

    uint256 public tokenPerBlock;
    PoolInfo public poolInfo;
    mapping(address => UserInfo) public userInfo;

    modifier onlyMCW() {
        require(_msgSender() == address(MCW), "onlyMCW: only MasterChefWoo");
        _;
    }

    constructor(
        IERC20 _rewardToken,
        IERC20 _weToken,
        IMasterChefWoo _MCW,
        uint256 _tokenPerBlock
    ) {
        rewardToken = _rewardToken;
        weToken = _weToken;
        MCW = _MCW;
        tokenPerBlock = _tokenPerBlock;
    }

    /// @notice Function called by MasterChefWoo whenever staker claims weToken harvest.
    /// @notice Allows staker to also receive a 2nd reward token
    /// @param _user Address of user
    /// @param _weAmount Number of we tokens the user has
    function onRewarded(address _user, uint256 _weAmount) external override onlyMCW nonReentrant {
        PoolInfo memory pool = updatePool();
        UserInfo storage user = userInfo[_user];
        uint256 pending;
        if (user.amount > 0) {
            pending = (user.amount * pool.accTokenPerShare) / 1e12 - user.rewardDebt + user.unpaidRewards;
            uint256 curBalance = rewardToken.balanceOf(address(this));
            if (pending > curBalance) {
                if (curBalance > 0) {
                    rewardToken.safeTransfer(_user, curBalance);
                }
                user.unpaidRewards = pending - curBalance;
            } else {
                rewardToken.safeTransfer(_user, pending);
                user.unpaidRewards = 0;
            }
        }

        user.amount = _weAmount;
        user.rewardDebt = (user.amount * pool.accTokenPerShare) / 1e12;

        emit OnRewarded(_user, pending - user.unpaidRewards);
    }

    /// @notice View function to see pending tokens
    /// @param _user Address of user.
    /// @return pending reward for a given user.
    function pendingTokens(address _user) external view override returns (uint256 pending) {
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];

        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 weSupply = weToken.balanceOf(address(MCW));

        if (block.number > pool.lastRewardBlock && weSupply != 0) {
            uint256 blocks = block.number - pool.lastRewardBlock;
            uint256 tokenReward = blocks * tokenPerBlock;
            accTokenPerShare += (tokenReward * 1e12) / weSupply;
        }

        pending = (user.amount * accTokenPerShare) / 1e12 - user.rewardDebt + user.unpaidRewards;
    }

    /// @notice View function to see balance of reward token.
    function balance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    /// @notice Sets the distribution reward rate. This will also update the poolInfo.
    /// @param _tokenPerBlock The number of tokens to distribute per second
    function setRewardRate(uint256 _tokenPerBlock) external onlyOwner {
        require(_tokenPerBlock > 0, "WSR: invalid value");
        updatePool();
        uint256 oldRate = tokenPerBlock;
        tokenPerBlock = _tokenPerBlock;

        emit RewardRateUpdated(oldRate, _tokenPerBlock);
    }

    /// @notice Update reward variables of the given poolInfo.
    /// @return pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory pool) {
        pool = poolInfo;

        if (block.number > pool.lastRewardBlock) {
            uint256 weSupply = weToken.balanceOf(address(MCW));

            if (weSupply > 0) {
                uint256 blocks = block.number - pool.lastRewardBlock;
                uint256 tokenReward = blocks * tokenPerBlock;
                pool.accTokenPerShare += (tokenReward * 1e12) / weSupply;
            }

            pool.lastRewardBlock = block.number;
            poolInfo = pool;
        }
    }

    /// @notice In case rewarder is stopped before emissions finished,
    /// @notice this function allows withdrawal of remaining tokens.
    function emergencyWithdraw() public onlyOwner {
        uint256 amount = rewardToken.balanceOf(address(this));
        rewardToken.safeTransfer(owner(), amount);
    }

    /// @dev Rescue the specified funds when stuck happens
    /// @param stuckToken the stuck token address
    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        require(stuckToken != address(0), "WSR: invalid address");
        if (stuckToken == ETH_PLACEHOLDER_ADDR) {
            TransferHelper.safeTransferETH(_msgSender(), address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, _msgSender(), amount);
        }
    }
}
