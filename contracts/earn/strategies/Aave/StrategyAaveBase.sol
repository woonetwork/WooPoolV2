// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "../BaseStrategy.sol";
import "../../../libraries/TransferHelper.sol";

import "../../../interfaces/Aave/IAavePool.sol";
import "../../../interfaces/Aave/IAaveV3Incentives.sol";
import "../../../interfaces/Aave/IAaveDataProvider.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StrategyAaveBase is BaseStrategy {
    using SafeERC20 for IERC20;

    /* ----- State Variables ----- */

    address[] public rewardAssets;
    address[] public aAssets = new address[](1);
    address public rewardTreasury;
    uint256 public lastHarvest;

    /* ----- Constant Variables ----- */

    address public constant aavePool = address(0xA238Dd80C259a72e81d7e4664a9801593F98d1c5); // Aave: Pool V3
    address public constant incentivesController = address(0xf9cc4F0D883F1a1eb2c253bdb46c254Ca51E1F44); // Aave: Incentives V3
    address public constant dataProvider = address(0x2d8A3C5677189723C4cB8873CfC9C8976FDF38Ac); // Aave: Pool Data Provider V3

    /* ----- Events ----- */

    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    constructor(
        address _vault,
        address _accessManager,
        address _rewardTreasury
    ) BaseStrategy(_vault, _accessManager) {
        rewardAssets = IAaveV3Incentives(incentivesController).getRewardsList();
        (address aToken, , ) = IAaveDataProvider(dataProvider).getReserveTokensAddresses(want);
        aAssets[0] = aToken;
        rewardTreasury = _rewardTreasury;

        _giveAllowances();
    }

    /* ----- External Functions ----- */

    /* ----- Public Functions ----- */

    function harvest() public override whenNotPaused {
        require(msg.sender == tx.origin || msg.sender == address(vault), "StrategyAaveBase: EOA_or_vault");

        // claim all rewards to the vault
        IAaveV3Incentives(incentivesController).claimAllRewards(aAssets, rewardTreasury);
    }

    function deposit() public override whenNotPaused nonReentrant {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IAavePool(aavePool).deposit(want, wantBal, address(this), 0);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 amount) public override nonReentrant {
        require(msg.sender == vault, "StrategyAaveBase: !vault");
        require(amount > 0, "StrategyAaveBase: !amount");

        uint256 wantBal = balanceOfWant();

        if (wantBal < amount) {
            IAavePool(aavePool).withdraw(want, amount - wantBal, address(this));
            uint256 newWantBal = IERC20(want).balanceOf(address(this));
            require(newWantBal > wantBal, "StrategyAaveBase: !newWantBal");
            wantBal = newWantBal;
        }

        uint256 withdrawAmt = amount < wantBal ? amount : wantBal;

        uint256 fee = chargeWithdrawalFee(withdrawAmt);
        if (withdrawAmt > fee) {
            TransferHelper.safeTransfer(want, vault, withdrawAmt - fee);
        }
        emit Withdraw(balanceOf());
    }

    function userReserves() public view returns (uint256, uint256) {
        (uint256 supplyBal, , uint256 borrowBal, , , , , , ) = IAaveDataProvider(dataProvider).getUserReserveData(
            want,
            address(this)
        );
        return (supplyBal, borrowBal);
    }

    function balanceOfPool() public view override returns (uint256) {
        (uint256 supplyBal, uint256 borrowBal) = userReserves();
        return supplyBal - borrowBal;
    }

    /* ----- Internal Functions ----- */

    function _giveAllowances() internal override {
        TransferHelper.safeApprove(want, aavePool, type(uint256).max);
    }

    function _removeAllowances() internal override {
        TransferHelper.safeApprove(want, aavePool, 0);
    }

    function _withdrawAll() internal {
        if (balanceOfPool() > 0) {
            IAavePool(aavePool).withdraw(want, type(uint256).max, address(this));
        }
    }

    /* ----- Admin Functions ----- */

    function retireStrat() external override {
        require(msg.sender == vault, "StrategyAaveBase: !vault");
        _withdrawAll();
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        if (wantBal > 0) {
            TransferHelper.safeTransfer(want, vault, wantBal);
        }
    }

    function emergencyExit() external override onlyAdminOrPauseRole {
        _withdrawAll();
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        if (wantBal > 0) {
            TransferHelper.safeTransfer(want, vault, wantBal);
        }
    }

    function updateRewardTreasury(address addr) external onlyAdmin {
        require(addr != address(0), "StrategyAaveBase: !rewardTreasury");
        rewardTreasury = addr;
    }
}
