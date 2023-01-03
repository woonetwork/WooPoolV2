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
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

import "../interfaces/IWETH.sol";
import "../interfaces/IWooAccessManager.sol";

import "../libraries/TransferHelper.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract WooWithdrawManagerV2 is Ownable, ReentrancyGuard {
    // addedAmount: added withdrawal amount for this user
    // totalAmount: total withdrawal amount for this user
    event WithdrawAdded(address indexed user, uint256 addedAmount, uint256 totalAmount);

    event Withdraw(address indexed user, uint256 amount);

    address public want;
    address public weth;
    address public accessManager;
    address public superChargerVault;

    mapping(address => uint256) public withdrawAmount;

    address constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor() {}

    function init(
        address _weth,
        address _want,
        address _accessManager,
        address _superChargerVault
    ) external onlyOwner {
        weth = _weth;
        want = _want;
        accessManager = _accessManager;
        superChargerVault = _superChargerVault;
    }

    modifier onlyAdmin() {
        require(
            owner() == msg.sender || IWooAccessManager(accessManager).isVaultAdmin(msg.sender),
            "WooWithdrawManager: !owner"
        );
        _;
    }

    modifier onlySuperChargerVault() {
        require(superChargerVault == msg.sender, "WooWithdrawManager: !superChargerVault");
        _;
    }

    function setSuperChargerVault(address _superChargerVault) external onlyAdmin {
        superChargerVault = _superChargerVault;
    }

    function addWithdrawAmount(address user, uint256 amount) external onlySuperChargerVault {
        // NOTE: in V2, granular token transfer is avoided to save the save consumption;
        // Do remember batch transfer the total amount of `want` tokens after calling this method.

        // TransferHelper.safeTransferFrom(want, msg.sender, address(this), amount);
        withdrawAmount[user] = withdrawAmount[user] + amount;
        emit WithdrawAdded(user, amount, withdrawAmount[user]);
    }

    function withdraw() external nonReentrant {
        uint256 amount = withdrawAmount[msg.sender];
        if (amount == 0) {
            return;
        }
        withdrawAmount[msg.sender] = 0;
        if (want == weth) {
            IWETH(weth).withdraw(amount);
            TransferHelper.safeTransferETH(msg.sender, amount);
        } else {
            TransferHelper.safeTransfer(want, msg.sender, amount);
        }
        emit Withdraw(msg.sender, amount);
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        require(stuckToken != want);
        if (stuckToken == ETH_PLACEHOLDER_ADDR) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, msg.sender, amount);
        }
    }

    receive() external payable {}
}
