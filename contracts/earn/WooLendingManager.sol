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

import "./WooSuperChargerVault.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IWooAccessManager.sol";
import "../interfaces/IWooPPV2.sol";

import "../libraries/TransferHelper.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract WooLendingManager is Ownable, ReentrancyGuard {
    event Borrow(address indexed user, uint256 assets);
    event Repay(address indexed user, uint256 assets, uint256 perfFee);
    event InterestRateUpdated(address indexed user, uint256 oldInterest, uint256 newInterest);

    address public weth;
    address public want;
    address public accessManager;
    address public wooPP;
    WooSuperChargerVault public superChargerVault;

    uint256 public borrowedPrincipal;
    uint256 public borrowedInterest;

    uint256 public perfRate = 1000; // 1 in 10000th. 1000 = 10%
    address public treasury;

    uint256 public interestRate; // 1 in 10000th. 1 = 0.01% (1 bp), 10 = 0.1% (10 bps)
    uint256 public lastAccuredTs; // Timestamp of last accured interests

    mapping(address => bool) public isBorrower;

    address constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor() {}

    function init(
        address _weth,
        address _want,
        address _accessManager,
        address _wooPP,
        address payable _superChargerVault
    ) external onlyOwner {
        weth = _weth;
        want = _want;
        accessManager = _accessManager;
        wooPP = _wooPP;
        superChargerVault = WooSuperChargerVault(_superChargerVault);
        lastAccuredTs = block.timestamp;
        treasury = 0x4094D7A17a387795838c7aba4687387B0d32BCf3;
    }

    modifier onlyAdmin() {
        require(
            owner() == msg.sender || IWooAccessManager(accessManager).isVaultAdmin(msg.sender),
            "WooLendingManager: !ADMIN"
        );
        _;
    }

    modifier onlyBorrower() {
        require(isBorrower[msg.sender], "WooLendingManager: !borrower");
        _;
    }

    modifier onlySuperChargerVault() {
        require(msg.sender == address(superChargerVault), "WooLendingManager: !superChargerVault");
        _;
    }

    function setSuperChargerVault(address payable _wooSuperCharger) external onlyOwner {
        superChargerVault = WooSuperChargerVault(_wooSuperCharger);
    }

    function setWooPP(address _wooPP) external onlyOwner {
        wooPP = _wooPP;
    }

    function setBorrower(address _borrower, bool _isBorrower) external onlyOwner {
        isBorrower[_borrower] = _isBorrower;
    }

    function setPerfRate(uint256 _rate) external onlyAdmin {
        require(_rate < 10000);
        perfRate = _rate;
    }

    function debt() public view returns (uint256 assets) {
        return borrowedPrincipal + borrowedInterest;
    }

    function debtAfterPerfFee() public view returns (uint256 assets) {
        uint256 perfFee = (borrowedInterest * perfRate) / 10000;
        return borrowedPrincipal + borrowedInterest - perfFee;
    }

    function borrowState()
        external
        view
        returns (
            uint256 total,
            uint256 principal,
            uint256 interest,
            uint256 borrowable
        )
    {
        total = debt();
        principal = borrowedPrincipal;
        interest = borrowedInterest;
        borrowable = superChargerVault.maxBorrowableAmount();
    }

    function accureInterest() public {
        uint256 currentTs = block.timestamp;

        // CAUTION: block.timestamp may be out of order
        if (currentTs <= lastAccuredTs) {
            return;
        }

        uint256 duration = currentTs - lastAccuredTs;

        // interestRate is in 10000th.
        // 31536000 = 365 * 24 * 3600 (1 year of seconds)
        uint256 interest = (borrowedPrincipal * interestRate * duration) / 31536000 / 10000;

        borrowedInterest = borrowedInterest + interest;
        lastAccuredTs = currentTs;
    }

    function setInterestRate(uint256 _rate) external onlyAdmin {
        require(_rate <= 50000, "RATE_INVALID"); // NOTE: rate < 500%
        accureInterest();
        uint256 oldInterest = interestRate;
        interestRate = _rate;
        emit InterestRateUpdated(msg.sender, oldInterest, _rate);
    }

    function setTreasury(address _treasury) external onlyAdmin {
        require(_treasury != address(0), "WooLendingManager: !_treasury");
        treasury = _treasury;
    }

    function maxBorrowableAmount() external view returns (uint256) {
        return superChargerVault.maxBorrowableAmount();
    }

    /// @dev Borrow the fund from super charger and then deposit directly into WooPP.
    /// @param amount the borrowing amount
    function borrow(uint256 amount) external onlyBorrower {
        require(amount > 0, "!AMOUNT");

        accureInterest();
        borrowedPrincipal = borrowedPrincipal + amount;

        uint256 preBalance = IERC20(want).balanceOf(address(this));
        superChargerVault.borrowFromLendingManager(amount, address(this));
        uint256 afterBalance = IERC20(want).balanceOf(address(this));
        require(afterBalance - preBalance == amount, "WooLendingManager: BORROW_AMOUNT_ERROR");

        TransferHelper.safeApprove(want, wooPP, amount);
        IWooPPV2(wooPP).deposit(want, amount);

        emit Borrow(msg.sender, amount);
    }

    // NOTE: this is the view functiono;
    // Remember to call the accureInterest to ensure the latest repayment state.
    function weeklyRepayment() public view returns (uint256 repayAmount) {
        uint256 neededAmount = superChargerVault.weeklyNeededAmountForWithdraw();
        if (neededAmount == 0) {
            return 0;
        }
        if (neededAmount <= borrowedInterest) {
            repayAmount = (neededAmount * 10000) / (uint256(10000) - perfRate);
        } else {
            repayAmount = neededAmount - borrowedInterest + ((borrowedInterest * 10000) / (uint256(10000) - perfRate));
        }
        repayAmount = repayAmount + 1;
    }

    function weeklyRepaymentBreakdown()
        public
        view
        returns (
            uint256 repayAmount,
            uint256 principal,
            uint256 interest,
            uint256 perfFee
        )
    {
        uint256 neededAmount = superChargerVault.weeklyNeededAmountForWithdraw();
        if (neededAmount == 0) {
            return (0, 0, 0, 0);
        }
        if (neededAmount <= borrowedInterest) {
            repayAmount = (neededAmount * 10000) / (uint256(10000) - perfRate);
            principal = 0;
            interest = neededAmount;
        } else {
            repayAmount = neededAmount - borrowedInterest + ((borrowedInterest * 10000) / (uint256(10000) - perfRate));
            principal = neededAmount - borrowedInterest;
            interest = borrowedInterest;
        }
        repayAmount = repayAmount + 1;
        perfFee = repayAmount - neededAmount;
    }

    function repayWeekly() external onlyBorrower returns (uint256 repaidAmount) {
        accureInterest();
        repaidAmount = weeklyRepayment();
        if (repaidAmount != 0) {
            repay(repaidAmount);
        } else {
            emit Repay(msg.sender, 0, 0);
        }
    }

    function repayAll() external onlyBorrower returns (uint256 repaidAmount) {
        accureInterest();
        repaidAmount = debt();
        if (repaidAmount != 0) {
            repay(repaidAmount);
        } else {
            emit Repay(msg.sender, 0, 0);
        }
    }

    function repay(uint256 amount) public onlyBorrower {
        require(amount > 0);

        accureInterest();

        TransferHelper.safeTransferFrom(want, msg.sender, address(this), amount);

        require(IERC20(want).balanceOf(address(this)) >= amount);

        uint256 perfFee;
        if (borrowedInterest >= amount) {
            borrowedInterest = borrowedInterest - amount;
            perfFee = (amount * perfRate) / 10000;
        } else {
            perfFee = (borrowedInterest * perfRate) / 10000;
            borrowedPrincipal = borrowedPrincipal - (amount - borrowedInterest);
            borrowedInterest = 0;
        }
        TransferHelper.safeTransfer(want, treasury, perfFee);
        uint256 amountRepaid = amount - perfFee;

        TransferHelper.safeApprove(want, address(superChargerVault), amountRepaid);
        uint256 beforeBalance = IERC20(want).balanceOf(address(this));
        superChargerVault.repayFromLendingManager(amountRepaid);
        uint256 afterBalance = IERC20(want).balanceOf(address(this));
        require(beforeBalance - afterBalance == amountRepaid, "WooLendingManager: REPAY_AMOUNT_ERROR");

        emit Repay(msg.sender, amount, perfFee);
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        if (stuckToken == ETH_PLACEHOLDER_ADDR) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, msg.sender, amount);
        }
    }
}
