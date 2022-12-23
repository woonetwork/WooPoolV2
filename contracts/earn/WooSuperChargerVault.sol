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

import "../interfaces/IStrategy.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IWooAccessManager.sol";
import "../interfaces/IVaultV2.sol";
import "../interfaces/IMasterChefWoo.sol";

import "./WooWithdrawManager.sol";
import "./WooLendingManager.sol";

import "../libraries/TransferHelper.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract WooSuperChargerVault is ERC20, Ownable, Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    event Deposit(address indexed depositor, address indexed receiver, uint256 assets, uint256 shares);
    event RequestWithdraw(address indexed owner, uint256 assets, uint256 shares);
    event InstantWithdraw(address indexed owner, uint256 assets, uint256 shares, uint256 fees);
    event WeeklySettleStarted(address indexed caller, uint256 totalRequestedShares, uint256 weeklyRepayAmount);
    event WeeklySettleEnded(
        address indexed caller,
        uint256 totalBalance,
        uint256 lendingBalance,
        uint256 reserveBalance
    );
    event ReserveVaultMigrated(address indexed user, address indexed oldVault, address indexed newVault);
    event SuperChargerVaultMigrated(
        address indexed user,
        address indexed oldVault,
        address indexed newVault,
        uint256 amount
    );

    event LendingManagerUpdated(address formerLendingManager, address newLendingManager);
    event WithdrawManagerUpdated(address formerWithdrawManager, address newWithdrawManager);
    event InstantWithdrawFeeRateUpdated(uint256 formerFeeRate, uint256 newFeeRate);

    /* ----- State Variables ----- */

    address constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IVaultV2 public reserveVault;
    address public migrationVault;
    WooLendingManager public lendingManager;
    WooWithdrawManager public withdrawManager;

    address public immutable want;
    address public immutable weth;
    IWooAccessManager public immutable accessManager;

    mapping(address => uint256) public costSharePrice;
    mapping(address => uint256) public requestedWithdrawShares; // Requested withdrawn amount (in assets, NOT shares)
    uint256 public requestedTotalShares;
    EnumerableSet.AddressSet private requestUsers;

    uint256 public instantWithdrawCap; // Max instant withdraw amount (in assets, per week)
    uint256 public instantWithdrawnAmount; // Withdrawn amout already consumed (in assets, per week)

    bool public isSettling;

    address public treasury = 0x815D4517427Fc940A90A5653cdCEA1544c6283c9;
    uint256 public instantWithdrawFeeRate = 30; // 1 in 10000th. default: 30 -> 0.3%

    address public masterChef;
    uint256 public pid;

    constructor(
        address _weth,
        address _want,
        address _accessManager
    )
        ERC20(
            string(abi.encodePacked("WOOFi Super Charger ", ERC20(_want).name())),
            string(abi.encodePacked("we", ERC20(_want).symbol()))
        )
    {
        require(_weth != address(0), "WooSuperChargerVault: !weth");
        require(_want != address(0), "WooSuperChargerVault: !want");
        require(_accessManager != address(0), "WooSuperChargerVault: !accessManager");

        weth = _weth;
        want = _want;
        accessManager = IWooAccessManager(_accessManager);
    }

    function init(
        address _reserveVault,
        address _lendingManager,
        address payable _withdrawManager
    ) external onlyOwner {
        require(_reserveVault != address(0), "WooSuperChargerVault: !_reserveVault");
        require(_lendingManager != address(0), "WooSuperChargerVault: !_lendingManager");
        require(_withdrawManager != address(0), "WooSuperChargerVault: !_withdrawManager");

        reserveVault = IVaultV2(_reserveVault);
        require(reserveVault.want() == want);
        lendingManager = WooLendingManager(_lendingManager);
        withdrawManager = WooWithdrawManager(_withdrawManager);
    }

    modifier onlyAdmin() {
        require(owner() == msg.sender || accessManager.isVaultAdmin(msg.sender), "WooSuperChargerVault: !ADMIN");
        _;
    }

    modifier onlyLendingManager() {
        require(msg.sender == address(lendingManager), "WooSuperChargerVault: !lendingManager");
        _;
    }

    /* ----- External Functions ----- */

    function setMasterChef(address _masterChef, uint256 _pid) external onlyOwner {
        require(_masterChef != address(0), "!_masterChef");
        masterChef = _masterChef;
        pid = _pid;
        (IERC20 weToken, , , , ) = IMasterChefWoo(masterChef).poolInfo(pid);
        require(address(weToken) == address(this), "!pid");
    }

    function stakedShares(address _user) public view returns (uint256 shares) {
        if (masterChef == address(0)) {
            shares = 0;
        } else {
            (shares, ) = IMasterChefWoo(masterChef).userInfo(pid, _user);
        }
    }

    function deposit(uint256 amount) external payable whenNotPaused nonReentrant {
        _deposit(amount, msg.sender);
    }

    function deposit(uint256 amount, address receiver) external payable whenNotPaused nonReentrant {
        _deposit(amount, receiver);
    }

    function _deposit(uint256 amount, address receiver) private {
        if (amount == 0) {
            return;
        }

        lendingManager.accureInterest();
        uint256 shares = _shares(amount, getPricePerFullShare());
        require(shares > 0, "!shares");

        uint256 sharesBefore = balanceOf(receiver) + stakedShares(receiver);
        uint256 costBefore = costSharePrice[receiver];
        uint256 costAfter = (sharesBefore * costBefore + amount * 1e18) / (sharesBefore + shares);

        costSharePrice[receiver] = costAfter;

        if (want == weth) {
            require(amount == msg.value, "WooSuperChargerVault: msg.value_INSUFFICIENT");
            reserveVault.deposit{value: msg.value}(amount);
        } else {
            TransferHelper.safeTransferFrom(want, msg.sender, address(this), amount);
            TransferHelper.safeApprove(want, address(reserveVault), amount);
            reserveVault.deposit(amount);
        }
        _mint(receiver, shares);

        instantWithdrawCap = instantWithdrawCap + amount / 10;

        emit Deposit(msg.sender, receiver, amount, shares);
    }

    function instantWithdraw(uint256 amount) external whenNotPaused nonReentrant {
        _instantWithdrawShares(_sharesUpLatest(amount), msg.sender);
    }

    function instantWithdraw(uint256 amount, address owner) external whenNotPaused nonReentrant {
        _instantWithdrawShares(_sharesUpLatest(amount), owner);
    }

    function instantWithdrawAll() external whenNotPaused nonReentrant {
        _instantWithdrawShares(balanceOf(msg.sender), msg.sender);
    }

    function instantWithdrawAll(address owner) external whenNotPaused nonReentrant {
        _instantWithdrawShares(balanceOf(owner), owner);
    }

    function _instantWithdrawShares(uint256 shares, address owner) private {
        require(shares > 0, "WooSuperChargerVault: !amount");
        require(!isSettling, "WooSuperChargerVault: NOT_ALLOWED_IN_SETTLING");

        if (instantWithdrawnAmount >= instantWithdrawCap) {
            // NOTE: no more instant withdraw quota.
            return;
        }

        lendingManager.accureInterest();
        uint256 amount = _assets(shares);
        require(amount <= instantWithdrawCap - instantWithdrawnAmount, "WooSuperChargerVault: OUT_OF_CAP");

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);

        uint256 reserveShares = _sharesUp(amount, reserveVault.getPricePerFullShare());
        reserveVault.withdraw(reserveShares);

        uint256 fee = accessManager.isZeroFeeVault(msg.sender) ? 0 : (amount * instantWithdrawFeeRate) / 10000;
        if (want == weth) {
            TransferHelper.safeTransferETH(treasury, fee);
            TransferHelper.safeTransferETH(owner, amount - fee);
        } else {
            TransferHelper.safeTransfer(want, treasury, fee);
            TransferHelper.safeTransfer(want, owner, amount - fee);
        }

        instantWithdrawnAmount = instantWithdrawnAmount + amount;

        emit InstantWithdraw(owner, amount, reserveShares, fee);
    }

    function migrateToNewVault() external whenNotPaused nonReentrant {
        _migrateToNewVault(msg.sender);
    }

    function migrateToNewVault(address owner) external whenNotPaused nonReentrant {
        _migrateToNewVault(owner);
    }

    function _migrateToNewVault(address owner) private {
        require(owner != address(0), "WooSuperChargerVault: !owner");
        require(migrationVault != address(0), "WooSuperChargerVault: !migrationVault");

        WooSuperChargerVault newVault = WooSuperChargerVault(payable(migrationVault));
        require(newVault.want() == want, "WooSuperChargerVault: !WANT_newVault");

        uint256 shares = balanceOf(owner);
        if (shares == 0) {
            return;
        }

        lendingManager.accureInterest();
        uint256 amount = _assets(shares);

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);

        uint256 reserveShares = _sharesUp(amount, reserveVault.getPricePerFullShare());
        reserveVault.withdraw(reserveShares);

        if (want == weth) {
            newVault.deposit{value: amount}(amount, owner);
        } else {
            TransferHelper.safeApprove(want, address(newVault), amount);
            newVault.deposit(amount, owner);
        }

        emit SuperChargerVaultMigrated(owner, address(this), address(newVault), amount);
    }

    function requestWithdraw(uint256 amount) external whenNotPaused nonReentrant {
        _requestWithdrawShares(_sharesUpLatest(amount));
    }

    function requestWithdrawAll() external whenNotPaused nonReentrant {
        _requestWithdrawShares(balanceOf(msg.sender));
    }

    function _requestWithdrawShares(uint256 shares) private {
        require(shares > 0, "WooSuperChargerVault: !amount");
        require(!isSettling, "WooSuperChargerVault: CANNOT_WITHDRAW_IN_SETTLING");

        address owner = msg.sender;

        lendingManager.accureInterest();
        uint256 amount = _assets(shares);
        TransferHelper.safeTransferFrom(address(this), owner, address(this), shares);

        requestedWithdrawShares[owner] = requestedWithdrawShares[owner] + shares;
        requestedTotalShares = requestedTotalShares + shares;
        requestUsers.add(owner);

        emit RequestWithdraw(owner, amount, shares);
    }

    function requestedTotalAmount() public view returns (uint256) {
        return _assets(requestedTotalShares);
    }

    function requestedWithdrawAmount(address user) public view returns (uint256) {
        return _assets(requestedWithdrawShares[user]);
    }

    function available() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function reserveBalance() public view returns (uint256) {
        return _assets(IERC20(address(reserveVault)).balanceOf(address(this)), reserveVault.getPricePerFullShare());
    }

    function lendingBalance() public view returns (uint256) {
        return lendingManager.debtAfterPerfFee();
    }

    // Returns the total balance (assets), which is avaiable + reserve + lending.
    function balance() public view returns (uint256) {
        return available() + reserveBalance() + lendingBalance();
    }

    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : (balance() * 1e18) / totalSupply();
    }

    // --- For WooLendingManager --- //

    function maxBorrowableAmount() public view returns (uint256) {
        uint256 resBal = reserveBalance();
        uint256 instWithdrawBal = instantWithdrawCap - instantWithdrawnAmount;
        return resBal > instWithdrawBal ? resBal - instWithdrawBal : 0;
    }

    function borrowFromLendingManager(uint256 amount, address fundAddr) external onlyLendingManager {
        require(!isSettling, "IN SETTLING");
        require(amount <= maxBorrowableAmount(), "INSUFF_AMOUNT_FOR_BORROW");
        uint256 sharesToWithdraw = _sharesUp(amount, reserveVault.getPricePerFullShare());
        reserveVault.withdraw(sharesToWithdraw);
        if (want == weth) {
            IWETH(weth).deposit{value: amount}();
        }
        TransferHelper.safeTransfer(want, fundAddr, amount);
    }

    function repayFromLendingManager(uint256 amount) external onlyLendingManager {
        TransferHelper.safeTransferFrom(want, msg.sender, address(this), amount);
        if (want == weth) {
            IWETH(weth).withdraw(amount);
            reserveVault.deposit{value: amount}(amount);
        } else {
            TransferHelper.safeApprove(want, address(reserveVault), amount);
            reserveVault.deposit(amount);
        }
    }

    // --- Admin operations --- //

    function weeklyNeededAmountForWithdraw() public view returns (uint256) {
        uint256 reserveBal = reserveBalance();
        uint256 requestedAmount = requestedTotalAmount();
        uint256 afterBal = balance() - requestedAmount;

        return reserveBal >= requestedAmount + afterBal / 10 ? 0 : requestedAmount + afterBal / 10 - reserveBal;
    }

    function startWeeklySettle() external onlyAdmin {
        require(!isSettling, "IN_SETTLING");
        isSettling = true;
        lendingManager.accureInterest();
        emit WeeklySettleStarted(msg.sender, requestedTotalShares, weeklyNeededAmountForWithdraw());
    }

    function endWeeklySettle() public onlyAdmin {
        require(isSettling, "!SETTLING");
        require(weeklyNeededAmountForWithdraw() == 0, "WEEKLY_REPAY_NOT_CLEARED");

        uint256 sharePrice = getPricePerFullShare();

        isSettling = false;
        uint256 amount = requestedTotalAmount();

        if (amount != 0) {
            uint256 shares = _sharesUp(amount, reserveVault.getPricePerFullShare());
            reserveVault.withdraw(shares);

            if (want == weth) {
                IWETH(weth).deposit{value: amount}();
            }
            require(available() >= amount);

            TransferHelper.safeApprove(want, address(withdrawManager), amount);
            uint256 length = requestUsers.length();
            for (uint256 i = 0; i < length; i++) {
                address user = requestUsers.at(0);

                withdrawManager.addWithdrawAmount(user, (requestedWithdrawShares[user] * sharePrice) / 1e18);

                requestedWithdrawShares[user] = 0;
                requestUsers.remove(user);
            }

            _burn(address(this), requestedTotalShares);
            requestedTotalShares = 0;
        }

        instantWithdrawnAmount = 0;

        lendingManager.accureInterest();
        uint256 totalBalance = balance();
        instantWithdrawCap = totalBalance / 10;

        emit WeeklySettleEnded(msg.sender, totalBalance, lendingBalance(), reserveBalance());
    }

    function migrateReserveVault(address _vault) external onlyOwner {
        require(_vault != address(0), "!_vault");

        uint256 preBal = (want == weth) ? address(this).balance : available();
        reserveVault.withdraw(IERC20(address(reserveVault)).balanceOf(address(this)));
        uint256 afterBal = (want == weth) ? address(this).balance : available();
        uint256 reserveAmount = afterBal - preBal;

        address oldVault = address(reserveVault);
        reserveVault = IVaultV2(_vault);
        require(reserveVault.want() == want, "INVALID_WANT");
        if (want == weth) {
            reserveVault.deposit{value: reserveAmount}(reserveAmount);
        } else {
            TransferHelper.safeApprove(want, address(reserveVault), reserveAmount);
            reserveVault.deposit(reserveAmount);
        }

        emit ReserveVaultMigrated(msg.sender, oldVault, _vault);
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        if (stuckToken == ETH_PLACEHOLDER_ADDR) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, msg.sender, amount);
        }
    }

    function setLendingManager(address _lendingManager) external onlyOwner {
        address formerManager = address(lendingManager);
        lendingManager = WooLendingManager(_lendingManager);
        emit LendingManagerUpdated(formerManager, _lendingManager);
    }

    function setWithdrawManager(address payable _withdrawManager) external onlyOwner {
        address formerManager = address(withdrawManager);
        withdrawManager = WooWithdrawManager(_withdrawManager);
        emit WithdrawManagerUpdated(formerManager, _withdrawManager);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setInstantWithdrawFeeRate(uint256 _feeRate) external onlyOwner {
        uint256 formerFeeRate = instantWithdrawFeeRate;
        instantWithdrawFeeRate = _feeRate;
        emit InstantWithdrawFeeRateUpdated(formerFeeRate, _feeRate);
    }

    function setInstantWithdrawCap(uint256 _instantWithdrawCap) external onlyOwner {
        instantWithdrawCap = _instantWithdrawCap;
    }

    function setMigrationVault(address _vault) external onlyOwner {
        migrationVault = _vault;
        WooSuperChargerVault newVault = WooSuperChargerVault(payable(_vault));
        require(newVault.want() == want, "WooSuperChargerVault: !WANT_vault");
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    receive() external payable {}

    function _assets(uint256 shares) private view returns (uint256) {
        return _assets(shares, getPricePerFullShare());
    }

    function _assets(uint256 shares, uint256 sharePrice) private pure returns (uint256) {
        return (shares * sharePrice) / 1e18;
    }

    function _shares(uint256 assets, uint256 sharePrice) private pure returns (uint256) {
        return (assets * 1e18) / sharePrice;
    }

    function _sharesUpLatest(uint256 assets) private returns (uint256) {
        lendingManager.accureInterest();
        return _sharesUp(assets, getPricePerFullShare());
    }

    function _sharesUp(uint256 assets, uint256 sharePrice) private pure returns (uint256) {
        uint256 shares = (assets * 1e18) / sharePrice;
        return _assets(shares, sharePrice) == assets ? shares : shares + 1;
    }
}
