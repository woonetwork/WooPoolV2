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

import "./WooSuperChargerVaultV2.sol";
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
    WooSuperChargerVaultV2 public superChargerVault;

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
        superChargerVault = WooSuperChargerVaultV2(_superChargerVault);
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
        superChargerVault = WooSuperChargerVaultV2(_wooSuperCharger);
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
        return debt();
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

    // NOTE: this is the view function;
    // Remember to call the accureInterest to ensure the latest repayment state.
    function weeklyRepayment() public view returns (uint256 repayAmount) {
        (repayAmount, , , ) = weeklyRepaymentBreakdown();
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
            interest = neededAmount;
            principal = 0;
        } else {
            interest = borrowedInterest;
            principal = neededAmount - borrowedInterest;
        }
        perfFee = (interest * perfRate) / 10000;
        repayAmount = principal + interest + perfFee;
    }

    function repayWeekly() external onlyBorrower returns (uint256 repaidAmount) {
        accureInterest();
        uint256 _principal;
        uint256 _interest;
        (, _principal, _interest, ) = weeklyRepaymentBreakdown();
        return _repay(_principal, _interest);
    }

    function repayAll() external onlyBorrower returns (uint256 repaidAmount) {
        accureInterest();
        return _repay(borrowedPrincipal, borrowedInterest);
    }

    // NOTE: repay the specified principal amount with all the borrowed interest
    function repayPrincipal(uint256 _principal) external onlyBorrower returns (uint256 repaidAmount) {
        accureInterest();
        return _repay(_principal, borrowedInterest);
    }

    function _repay(uint256 _principal, uint256 _interest) private returns (uint256 repaidAmount) {
        if (_principal == 0 && _interest == 0) {
            emit Repay(msg.sender, 0, 0);
            return 0;
        }

        uint256 _perfFee = (_interest * perfRate) / 10000;
        uint256 _totalAmount = _principal + _interest + _perfFee;

        TransferHelper.safeTransferFrom(want, msg.sender, address(this), _totalAmount);

        borrowedInterest -= _interest;
        borrowedPrincipal -= _principal;

        TransferHelper.safeTransfer(want, treasury, _perfFee);

        TransferHelper.safeApprove(want, address(superChargerVault), _principal + _interest);
        superChargerVault.repayFromLendingManager(_principal + _interest);

        emit Repay(msg.sender, _totalAmount, _perfFee);

        return _totalAmount;
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
