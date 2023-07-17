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

import "../interfaces/IWooracleV2.sol";
import "../interfaces/IWooPPV3.sol";
import "../interfaces/IWooCrossFee.sol";

import "../libraries/TransferHelper.sol";
import "../IntegrationHelper.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract WooCrossFee is Ownable, IWooCrossFee {
    struct FeeInfo {
        // all params are in 10000th
        uint16 k1; // bps [0, 10000]
        uint16 k2; // bps [0, 10000]
        uint16 maxPercent; // e.g. 80% of target balance
        uint16 minPercent; // e.g. 5% of target balance
    }

    uint256 public constant FEE_BASE = 1e4; // bps

    FeeInfo public feeInfo;

    uint256 public targetBalance; // 850000 , BTC, ETH

    IWooracleV2 wooracle;

    IWooPPV3 wooPP;

    IntegrationHelper helper;

    mapping(address => bool) public isAdmin;

    /* ----- Modifiers ----- */

    modifier onlyAdmin() {
        require(_msgSender() == owner() || isAdmin[_msgSender()], "WooCrossFee: !admin");
        _;
    }

    constructor(
        address _wooracle,
        address _wooPP,
        address _helper
    ) {
        wooracle = IWooracleV2(_wooracle);
        wooPP = IWooPPV3(_wooPP);
        helper = IntegrationHelper(_helper);
    }

    /* ----- Business Functions ----- */

    function feeBase() external pure returns (uint256) {
        return FEE_BASE;
    }

    function ingressFee(uint256 amount) external view returns (uint256 fee) {
        uint256 curBal = currentBalance();
        fee = _fee(curBal + amount);
    }

    function outgressFee(uint256 amount) external view returns (uint256 fee) {
        uint256 curBal = currentBalance();
        fee = _fee(curBal - amount);
    }

    function _fee(uint256 newBal) internal view returns (uint256) {
        uint256 tgtBal = targetBalance;
        if (newBal >= (feeInfo.maxPercent * tgtBal) / FEE_BASE) {
            return 0;
        } else if (newBal < (feeInfo.minPercent * tgtBal) / FEE_BASE) {
            // k1 + k2 * (minP * targetBal - newBal) / (minP * targetBal)
            return
                feeInfo.k1 +
                (feeInfo.k2 * ((feeInfo.minPercent * tgtBal) / FEE_BASE - newBal)) /
                ((feeInfo.minPercent * tgtBal) / FEE_BASE);
        } else {
            // k1 * (maxP * targetBal - newBal) / ((maxP - minP) * targetBal)
            return
                (feeInfo.k1 * ((feeInfo.maxPercent * tgtBal) / FEE_BASE - newBal)) /
                (((feeInfo.maxPercent - feeInfo.minPercent) * tgtBal) / FEE_BASE);
        }
    }

    function currentBalance() public view returns (uint256 balance) {
        uint256 len = helper.allBaseTokensLength();
        address[] memory bases = helper.allBaseTokens();
        balance = 0;
        for (uint256 i = 0; i < len; ++i) {
            address base = bases[i];
            (uint256 price, ) = wooracle.price(base);
            IWooPPV3.DecimalInfo memory info = wooPP.decimalInfo(base);
            balance += (wooPP.poolSize(base) * info.quoteDec * price) / info.priceDec / info.baseDec;
        }
    }

    /* ----- Admin Functions ----- */

    function setTargetBalance(uint256 _targetBalance) external onlyAdmin {
        uint256 prevTargetBalance = targetBalance;
        targetBalance = _targetBalance;
        emit TargetBalanceUpdated(prevTargetBalance, _targetBalance);
    }

    function setFeeInfo(
        uint16 k1,
        uint16 k2,
        uint16 maxPercent,
        uint16 minPercent
    ) external onlyAdmin {
        feeInfo.k1 = k1;
        feeInfo.k2 = k2;
        feeInfo.maxPercent = maxPercent;
        feeInfo.minPercent = minPercent;
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        if (stuckToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, msg.sender, amount);
        }
    }
}
