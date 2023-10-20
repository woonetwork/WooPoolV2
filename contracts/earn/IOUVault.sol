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

import "./WooLendingManager.sol";

import "../libraries/TransferHelper.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract IOUVault is ERC20, Ownable, Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    event Deposit(address indexed depositor, address indexed receiver, uint256 assets, uint256 shares);
    event Withdraw(address indexed owner, uint256 assets, uint256 shares, uint256 fees);

    event LendingManagerUpdated(address formerLendingManager, address newLendingManager);
    event withdrawFeeRateUpdated(uint256 formerFeeRate, uint256 newFeeRate);

    /* ----- State Variables ----- */

    address constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    WooLendingManager public lendingManager;

    address public immutable want;
    address public immutable weth;
    IWooAccessManager public immutable accessManager;

    mapping(address => uint256) public costSharePrice;

    address public treasury = 0x815D4517427Fc940A90A5653cdCEA1544c6283c9;
    uint256 public withdrawFeeRate = 30; // 1 in 10000th. default: 30 -> 0.3%

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
        require(_weth != address(0), "WooIOUVault: !weth");
        require(_want != address(0), "WooIOUVault: !want");
        require(_accessManager != address(0), "WooIOUVault: !accessManager");

        weth = _weth;
        want = _want;
        accessManager = IWooAccessManager(_accessManager);
    }

    function init(address _lendingManager) external onlyOwner {
        require(_lendingManager != address(0), "WooIOUVault: !_lendingManager");
        lendingManager = WooLendingManager(_lendingManager);
    }

    modifier onlyAdmin() {
        require(owner() == msg.sender || accessManager.isVaultAdmin(msg.sender), "WooIOUVault: !ADMIN");
        _;
    }

    modifier onlyLendingManager() {
        require(msg.sender == address(lendingManager), "WooIOUVault: !lendingManager");
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
            require(amount == msg.value, "WooIOUVault: msg.value_INSUFFICIENT");
            IWETH(weth).deposit{value: msg.value}();
        } else {
            TransferHelper.safeTransferFrom(want, msg.sender, address(this), amount);
        }

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, amount, shares);
    }

    function withdraw(uint256 amount) external whenNotPaused nonReentrant {
        _withdrawShares(_sharesUpLatest(amount), msg.sender);
    }

    function withdrawAll() external whenNotPaused nonReentrant {
        _withdrawShares(balanceOf(msg.sender), msg.sender);
    }

    function _withdrawShares(uint256 shares, address owner) private {
        require(shares > 0, "WooIOUVault: !amount");

        lendingManager.accureInterest();
        uint256 amount = _assets(shares);
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);

        uint256 fee = accessManager.isZeroFeeVault(msg.sender) ? 0 : (amount * withdrawFeeRate) / 10000;
        if (want == weth) {
            IWETH(weth).withdraw(amount);
            TransferHelper.safeTransferETH(treasury, fee);
            TransferHelper.safeTransferETH(owner, amount - fee);
        } else {
            TransferHelper.safeTransfer(want, treasury, fee);
            TransferHelper.safeTransfer(want, owner, amount - fee);
        }
        emit Withdraw(owner, amount, shares, fee);
    }

    function available() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function lendingBalance() public view returns (uint256) {
        return lendingManager.debtAfterPerfFee();
    }

    // Returns the total balance (assets), which is avaiable + reserve + lending.
    function balance() public view returns (uint256) {
        return available() + lendingBalance();
    }

    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : (balance() * 1e18) / totalSupply();
    }

    // --- For WooLendingManager --- //

    function maxBorrowableAmount() public view returns (uint256) {
        return available();
    }

    function borrowFromLendingManager(uint256 amount, address fundAddr) external onlyLendingManager {
        require(amount <= maxBorrowableAmount(), "INSUFF_AMOUNT_FOR_BORROW");
        TransferHelper.safeTransfer(want, fundAddr, amount);
    }

    function repayFromLendingManager(uint256 amount) external onlyLendingManager {
        TransferHelper.safeTransferFrom(want, msg.sender, address(this), amount);
    }

    // --- Admin operations --- //

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

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setwithdrawFeeRate(uint256 _feeRate) external onlyOwner {
        uint256 formerFeeRate = withdrawFeeRate;
        withdrawFeeRate = _feeRate;
        emit withdrawFeeRateUpdated(formerFeeRate, _feeRate);
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
