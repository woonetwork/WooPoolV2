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

import "../../interfaces/IStrategy.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/IWooAccessManager.sol";
import "../../interfaces/IVaultV2.sol";

import "../../libraries/TransferHelper.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * Base strategy abstract contract for:
 *  - vault and access manager setup
 *  - fees management
 *  - pause / unpause
 */
abstract contract BaseStrategy is Ownable, Pausable, IStrategy, ReentrancyGuard {
    /* ----- State Variables ----- */

    address public override want;
    address public immutable override vault;

    // Default them to 'false' to save the gas cost
    bool public harvestOnDeposit = false;
    // Default them to 'true' to make the system more fair, but cost a bit more gas.
    bool public harvestOnWithdraw = true;

    /* ----- Constant Variables ----- */

    uint256 public constant FEE_MAX = 10000;
    uint256 public performanceFee = 300; // 1 in 10000th: 100: 1%, 300: 3%
    uint256 public withdrawalFee = 0; // 1 in 10000th: 1: 0.01%, 10: 0.1%
    address public performanceTreasury = address(0x4094D7A17a387795838c7aba4687387B0d32BCf3);
    address public withdrawalTreasury = address(0x4094D7A17a387795838c7aba4687387B0d32BCf3);

    IWooAccessManager public accessManager;

    event PerformanceFeeUpdated(uint256 newFee);
    event WithdrawalFeeUpdated(uint256 newFee);

    constructor(address _vault, address _accessManager) {
        require(_vault != address(0), "BaseStrategy: !_vault");
        require(_accessManager != address(0), "BaseStrategy: !_accessManager");
        vault = _vault;
        accessManager = IWooAccessManager(_accessManager);
        want = IVaultV2(_vault).want();
    }

    modifier onlyAdmin() {
        require(owner() == _msgSender() || accessManager.isVaultAdmin(msg.sender), "BaseStrategy: NOT_ADMIN");
        _;
    }

    /* ----- Public Functions ----- */

    function beforeDeposit() public virtual override {
        require(msg.sender == address(vault), "BaseStrategy: !vault");
        if (harvestOnDeposit) {
            harvest();
        }
    }

    function beforeWithdraw() public virtual override {
        require(msg.sender == address(vault), "BaseStrategy: !vault");
        if (harvestOnWithdraw) {
            harvest();
        }
    }

    function balanceOf() public view override returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    function balanceOfWant() public view override returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /* ----- Internal Functions ----- */

    function chargePerformanceFee(uint256 amount) internal returns (uint256) {
        uint256 fee = (amount * performanceFee) / FEE_MAX;
        if (fee > 0) {
            TransferHelper.safeTransfer(want, performanceTreasury, fee);
        }
        return fee;
    }

    function chargeWithdrawalFee(uint256 amount) internal returns (uint256) {
        uint256 fee = (amount * withdrawalFee) / FEE_MAX;
        if (fee > 0) {
            TransferHelper.safeTransfer(want, withdrawalTreasury, fee);
        }
        return fee;
    }

    /* ----- Abstract Method ----- */

    function balanceOfPool() public view virtual override returns (uint256);

    function deposit() public virtual override;

    function withdraw(uint256 amount) external virtual override;

    function harvest() public virtual override;

    function retireStrat() external virtual override;

    function emergencyExit() external virtual override;

    function _giveAllowances() internal virtual;

    function _removeAllowances() internal virtual;

    /* ----- Admin Functions ----- */

    function setPerformanceFee(uint256 fee) external onlyAdmin {
        require(fee <= FEE_MAX, "BaseStrategy: fee_EXCCEEDS_MAX");
        performanceFee = fee;
        emit PerformanceFeeUpdated(fee);
    }

    function setWithdrawalFee(uint256 fee) external onlyAdmin {
        require(fee <= FEE_MAX, "BaseStrategy: fee_EXCCEEDS_MAX");
        require(fee <= 500, "BaseStrategy: fee_EXCCEEDS_5%"); // less than 5%
        withdrawalFee = fee;
        emit WithdrawalFeeUpdated(fee);
    }

    function setPerformanceTreasury(address treasury) external onlyAdmin {
        require(treasury != address(0), "BaseStrategy: treasury_ZERO_ADDR");
        performanceTreasury = treasury;
    }

    function setWithdrawalTreasury(address treasury) external onlyAdmin {
        require(treasury != address(0), "BaseStrategy: treasury_ZERO_ADDR");
        withdrawalTreasury = treasury;
    }

    function setHarvestOnDeposit(bool newHarvestOnDeposit) external onlyAdmin {
        harvestOnDeposit = newHarvestOnDeposit;
    }

    function setHarvestOnWithdraw(bool newHarvestOnWithdraw) external onlyAdmin {
        harvestOnWithdraw = newHarvestOnWithdraw;
    }

    function pause() public onlyAdmin {
        _pause();
        _removeAllowances();
    }

    function unpause() external onlyAdmin {
        _unpause();
        _giveAllowances();
        deposit();
    }

    function paused() public view override(IStrategy, Pausable) returns (bool) {
        return Pausable.paused();
    }

    function inCaseTokensGetStuck(address stuckToken) external override onlyAdmin {
        require(stuckToken != want, "BaseStrategy: stuckToken_NOT_WANT");
        require(stuckToken != address(0), "BaseStrategy: stuckToken_ZERO_ADDR");

        uint256 amount = IERC20(stuckToken).balanceOf(address(this));
        if (amount > 0) {
            TransferHelper.safeTransfer(stuckToken, msg.sender, amount);
        }
    }

    function inCaseNativeTokensGetStuck() external onlyAdmin {
        // NOTE: vault never needs native tokens to do the yield farming;
        // This native token balance indicates a user's incorrect transfer.
        if (address(this).balance > 0) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        }
    }
}
