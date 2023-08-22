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
import "../interfaces/AggregatorV3Interface.sol";
import "../interfaces/IWooLendingManager.sol";

import "../libraries/TransferHelper.sol";

import "./WooPPBase.sol";

import {WooUsdOFT} from "./WooUsdOFT.sol";

// OpenZeppelin contracts
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// REMOVE IT IN PROD
// import "hardhat/console.sol";

/// @title Woo pool for token swap, version 3.
/// Change in version 3:
///     - virtual quote: USD. All swaps are base to base.
///     - Stable swap support
///     - Legacy supercharger lending manager support
contract WooPPV3 is WooPPBase, IWooPPV3 {
    uint256 public unclaimedFee; // NOTE: in USD

    mapping(address => IWooLendingManager) public lendManagers;

    // int256 public usdReserve;    // USD (virtual quote) balance
    address public usdOFT;

    // token address --> fee rate
    mapping(address => TokenInfo) public tokenInfos;

    constructor(
        address _wooracle,
        address _feeAddr,
        address _usdOFT
    ) WooPPBase(_wooracle, _feeAddr) {
        usdOFT = _usdOFT;
    }

    /* ----- External Functions ----- */

    /// @inheritdoc IWooPPV3
    function tryQuery(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) external view override returns (uint256 toAmount) {
        if (fromToken == usdOFT) {
            toAmount = _tryQuerySellUsd(toToken, fromAmount);
        } else if (toToken == usdOFT) {
            toAmount = _tryQuerySellBase(fromToken, fromAmount);
        } else {
            (toAmount, ) = _tryQueryBaseToBase(fromToken, toToken, fromAmount);
        }
    }

    /// @inheritdoc IWooPPV3
    function query(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) external view override returns (uint256 toAmount) {
        if (fromToken == usdOFT) {
            toAmount = _tryQuerySellUsd(toToken, fromAmount);
            require(toAmount <= tokenInfos[toToken].reserve, "WooPPV3: INSUFF_BALANCE");
        } else if (toToken == usdOFT) {
            toAmount = _tryQuerySellBase(fromToken, fromAmount);
        } else {
            (toAmount, ) = _tryQueryBaseToBase(fromToken, toToken, fromAmount);
            // TODO: double check it
            // require(swapFee <= tokenInfos[quoteToken].reserve, "WooPPV3: INSUFF_QUOTE_FOR_SWAPFEE");
            require(toAmount <= tokenInfos[toToken].reserve, "WooPPV3: INSUFF_BALANCE");
        }
    }

    /// @inheritdoc IWooPPV3
    function swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount,
        address to,
        address rebateTo
    ) external override returns (uint256 realToAmount) {
        // realToAmount = _swapBaseToBase(fromToken, toToken, fromAmount, minToAmount, to, rebateTo);
        if (fromToken == usdOFT) {
            // case 1: usdOFT --> baseToken
            realToAmount = _swapUsdToBase(toToken, fromAmount, minToAmount, to, rebateTo);
        } else if (toToken == usdOFT) {
            // case 2: fromToken --> usdOFT
            realToAmount = _swapBaseToUsd(fromToken, fromAmount, minToAmount, to, rebateTo);
        } else {
            // case 3: fromToken --> toToken (base to base)
            realToAmount = _swapBaseToBase(fromToken, toToken, fromAmount, minToAmount, to, rebateTo);
        }
    }

    function claimFee() external onlyAdmin {
        require(feeAddr != address(0), "WooPPV3: !feeAddr");
        uint256 _fee = unclaimedFee;
        unclaimedFee = 0;
        WooUsdOFT(usdOFT).mint(feeAddr, _fee);
    }

    function claimFee(address _withdrawToken) external onlyAdmin {
        require(feeAddr != address(0), "WooPPV3: !feeAddr");
        require(_withdrawToken != address(0), "WooPPV3: !_withdrawToken");
        uint256 _fee = unclaimedFee;
        unclaimedFee = 0;
        WooUsdOFT(usdOFT).mint(address(this), _fee);
        _swapUsdToBase(_withdrawToken, _fee, 0, feeAddr, feeAddr);
    }

    /// @inheritdoc IWooPPV3
    /// @dev pool size = tokenInfo.reserve
    function poolSize(address token) public view override returns (uint256) {
        return tokenInfos[token].reserve;
    }

    function decimalInfo(address baseToken) public view returns (DecimalInfo memory) {
        return
            DecimalInfo({
                priceDec: uint64(10)**(IWooracleV2(wooracle).decimals(baseToken)), // 8
                quoteDec: uint64(10)**(IERC20Metadata(usdOFT).decimals()), // 6, same as native USDC
                baseDec: uint64(10)**(IERC20Metadata(baseToken).decimals()) // 18 or 8
            });
    }

    function setFeeRate(address token, uint16 rate) external onlyAdmin {
        require(rate <= 1e5, "!rate");
        tokenInfos[token].feeRate = rate;
    }

    function setFeeRates(address[] calldata tokens, uint16[] calldata feeRates) external onlyAdmin {
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokenInfos[tokens[i]].feeRate = feeRates[i];
        }
    }

    function setCapBals(address[] calldata tokens, uint192[] calldata capBals) external onlyAdmin {
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokenInfos[tokens[i]].capBal = capBals[i];
        }
    }

    function setTargetBals(address[] calldata tokens, uint192[] calldata tgtBals) external onlyAdmin {
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokenInfos[tokens[i]].tgtBal = tgtBals[i];
        }
    }

    /* ----- Admin Functions ----- */

    function deposit(address token, uint256 amount) public override nonReentrant onlyAdmin {
        uint256 balanceBefore = balance(token);
        TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);
        uint256 amountReceived = balance(token) - balanceBefore;
        require(amountReceived >= amount, "AMOUNT_INSUFF");

        tokenInfos[token].reserve = uint192(tokenInfos[token].reserve + amount);

        emit Deposit(token, msg.sender, amount);
    }

    function depositAll(address token) external onlyAdmin {
        deposit(token, IERC20(token).balanceOf(msg.sender));
    }

    function repayWeeklyLending(address wantToken) external nonReentrant onlyAdmin {
        IWooLendingManager lendManager = lendManagers[wantToken];
        lendManager.accureInterest();
        uint256 amount = lendManager.weeklyRepayment();
        address repaidToken = lendManager.want();
        if (amount > 0) {
            tokenInfos[repaidToken].reserve = uint192(tokenInfos[repaidToken].reserve - amount);
            TransferHelper.safeApprove(repaidToken, address(lendManager), amount);
            lendManager.repayWeekly();
        }
        emit Withdraw(repaidToken, address(lendManager), amount);
    }

    function withdraw(address token, uint256 amount) public nonReentrant onlyAdmin {
        require(tokenInfos[token].reserve >= amount, "WooPPV3: !amount");
        tokenInfos[token].reserve = uint192(tokenInfos[token].reserve - amount);
        TransferHelper.safeTransfer(token, owner(), amount);
        emit Withdraw(token, owner(), amount);
    }

    function withdrawAll(address token) external onlyAdmin {
        withdraw(token, poolSize(token));
    }

    function skim(address token) public nonReentrant onlyAdmin {
        TransferHelper.safeTransfer(token, owner(), balance(token) - tokenInfos[token].reserve);
    }

    function skimMulTokens(address[] memory tokens) external nonReentrant onlyAdmin {
        unchecked {
            uint256 len = tokens.length;
            for (uint256 i = 0; i < len; i++) {
                skim(tokens[i]);
            }
        }
    }

    function sync(address token) external nonReentrant onlyAdmin {
        tokenInfos[token].reserve = uint192(balance(token));
    }

    /* ----- Owner Functions ----- */

    function setUsdOFT(address _usdOFT) external onlyOwner {
        usdOFT = _usdOFT;
    }

    function setLendManager(IWooLendingManager _lendManager) external onlyOwner {
        lendManagers[_lendManager.want()] = _lendManager;
        isAdmin[address(_lendManager)] = true;
        emit AdminUpdated(address(_lendManager), true);
    }

    function migrateToNewPool(address token, address newPool) external onlyOwner {
        require(token != address(0), "WooPPV3: !token");
        require(newPool != address(0), "WooPPV3: !newPool");

        tokenInfos[token].reserve = 0;

        uint256 bal = balance(token);
        TransferHelper.safeApprove(token, newPool, bal);
        WooPPV3(newPool).depositAll(token);

        emit Migrate(token, newPool, bal);
    }

    /* ----- Internal Functions ----- */

    function _tryQuerySellBase(address baseToken, uint256 baseAmount) internal view returns (uint256 usdAmount) {
        IWooracleV2.State memory state = IWooracleV2(wooracle).state(baseToken);
        (usdAmount, ) = _calcUsdAmountSellBase(baseToken, baseAmount, state);
        uint256 fee = (usdAmount * tokenInfos[baseToken].feeRate) / 1e5;
        usdAmount = usdAmount - fee;
    }

    function _tryQuerySellUsd(address baseToken, uint256 usdAmount) internal view returns (uint256 baseAmount) {
        uint256 swapFee = (usdAmount * tokenInfos[baseToken].feeRate) / 1e5;
        usdAmount = usdAmount - swapFee;
        IWooracleV2.State memory state = IWooracleV2(wooracle).state(baseToken);
        (baseAmount, ) = _calcBaseAmountSellUsd(baseToken, usdAmount, state);
    }

    function _tryQueryBaseToBase(
        address baseToken1,
        address baseToken2,
        uint256 base1Amount
    ) private view whenNotPaused returns (uint256 base2Amount, uint256 swapFee) {
        if (baseToken1 == address(0) || baseToken2 == address(0) || baseToken1 == usdOFT || baseToken2 == usdOFT) {
            return (0, 0);
        }

        IWooracleV2.State memory state1 = IWooracleV2(wooracle).state(baseToken1);
        IWooracleV2.State memory state2 = IWooracleV2(wooracle).state(baseToken2);

        uint64 spread = _maxUInt64(state1.spread, state2.spread) / 2;
        uint16 feeRate = _maxUInt16(tokenInfos[baseToken1].feeRate, tokenInfos[baseToken2].feeRate);

        state1.spread = spread;
        state2.spread = spread;

        (uint256 usdAmount, ) = _calcUsdAmountSellBase(baseToken1, base1Amount, state1);

        swapFee = (usdAmount * feeRate) / 1e5;
        usdAmount = usdAmount - swapFee;

        (base2Amount, ) = _calcBaseAmountSellUsd(baseToken2, usdAmount, state2);
    }

    function _swapBaseToBase(
        address baseToken1,
        address baseToken2,
        uint256 base1Amount,
        uint256 minBase2Amount,
        address to,
        address rebateTo
    ) private nonReentrant whenNotPaused returns (uint256 base2Amount) {
        require(baseToken1 != address(0) && baseToken1 != usdOFT, "WooPPV3: !baseToken1");
        require(baseToken2 != address(0) && baseToken2 != usdOFT, "WooPPV3: !baseToken2");
        require(to != address(0), "WooPPV3: !to");

        require(balance(baseToken1) <= tokenInfos[baseToken1].capBal, "WooPPV3: CAP_EXCEEDS");
        require(balance(baseToken1) - tokenInfos[baseToken1].reserve >= base1Amount, "WooPPV3: !BASE1_BALANCE");

        IWooracleV2.State memory state1 = IWooracleV2(wooracle).state(baseToken1);
        IWooracleV2.State memory state2 = IWooracleV2(wooracle).state(baseToken2);

        uint256 swapFee;
        uint256 usdAmount;
        {
            uint64 spread = _maxUInt64(state1.spread, state2.spread) / 2;
            uint16 feeRate = _maxUInt16(tokenInfos[baseToken1].feeRate, tokenInfos[baseToken2].feeRate);

            state1.spread = spread;
            state2.spread = spread;

            uint256 newBase1Price;
            (usdAmount, newBase1Price) = _calcUsdAmountSellBase(baseToken1, base1Amount, state1);
            // TODO: uncomment it in prod version
            // IWooracleV2(wooracle).postPrice(baseToken1, uint128(newBase1Price));
            // console.log('Post new base1 price:', newBase1Price, newBase1Price/1e8);

            swapFee = (usdAmount * feeRate) / 1e5;
        }

        usdAmount -= swapFee;
        unclaimedFee += swapFee;

        tokenInfos[baseToken1].reserve = uint192(tokenInfos[baseToken1].reserve + base1Amount);

        {
            uint256 newBase2Price;
            (base2Amount, newBase2Price) = _calcBaseAmountSellUsd(baseToken2, usdAmount, state2);
            // TODO: uncomment it in prod version
            // IWooracleV2(wooracle).postPrice(baseToken2, uint128(newBase2Price));
            // console.log('Post new base2 price:', newBase2Price, newBase2Price/1e8);
            require(base2Amount >= minBase2Amount, "WooPPV3: base2Amount_LT_minBase2Amount");
        }

        tokenInfos[baseToken2].reserve = uint192(tokenInfos[baseToken2].reserve - base2Amount);

        if (to != address(this)) {
            TransferHelper.safeTransfer(baseToken2, to, base2Amount);
        }

        emit WooSwap(
            baseToken1,
            baseToken2,
            base1Amount,
            base2Amount,
            msg.sender,
            to,
            rebateTo,
            usdAmount + swapFee,
            swapFee
        );
    }

    function _swapBaseToUsd(
        address baseToken,
        uint256 baseAmount,
        uint256 minQuoteAmount,
        address to,
        address rebateTo
    ) internal returns (uint256 quoteAmount) {
        require(baseToken != address(0) && baseToken != usdOFT, "WooPPV3: !baseToken");
        require(to != address(0), "WooPPV3: !to");

        require(balance(baseToken) <= tokenInfos[baseToken].capBal, "WooPPV3: CAP_EXCEEDS");
        require(balance(baseToken) - tokenInfos[baseToken].reserve >= baseAmount, "WooPPV3: BASE_BALANCE_NOT_ENOUGH");

        {
            uint256 newPrice;
            IWooracleV2.State memory state = IWooracleV2(wooracle).state(baseToken);
            (quoteAmount, newPrice) = _calcUsdAmountSellBase(baseToken, baseAmount, state);
            // TODO: uncomment it in prod version
            // IWooracleV2(wooracle).postPrice(baseToken, uint128(newPrice));
            // console.log('Post new price:', newPrice, newPrice/1e8);
        }

        uint256 swapFee = (quoteAmount * tokenInfos[baseToken].feeRate) / 1e5;
        quoteAmount -= swapFee;
        require(quoteAmount >= minQuoteAmount, "WooPPV3: quoteAmount_LT_minQuoteAmount");

        unclaimedFee += swapFee;
        tokenInfos[baseToken].reserve = uint192(tokenInfos[baseToken].reserve + baseAmount);

        // ATTENTION: for cross chain, usdOFT will be minted in base->usd swap
        WooUsdOFT(usdOFT).mint(to, quoteAmount);

        emit WooSwap(
            baseToken,
            usdOFT,
            baseAmount,
            quoteAmount,
            msg.sender,
            to,
            rebateTo,
            (quoteAmount + swapFee),
            swapFee
        );
    }

    function _swapUsdToBase(
        address baseToken,
        uint256 quoteAmount,
        uint256 minBaseAmount,
        address to,
        address rebateTo
    ) internal returns (uint256 baseAmount) {
        require(baseToken != address(0) && baseToken != usdOFT, "WooPPV3: !baseToken");
        require(to != address(0), "WooPPV3: !to");

        require(balance(usdOFT) <= tokenInfos[usdOFT].capBal, "WooPPV3: CAP_EXCEEDS");

        // TODO: double check this logic
        // or: require(balance(usdOFT) - tokenInfos[usdOFT].reserve >= quoteAmount, "WooPPV3: USD_BALANCE_NOT_ENOUGH");
        // require(balance(usdOFT) >= quoteAmount, "WooPPV3: USD_BALANCE_NOT_ENOUGH");
        require(balance(usdOFT) - tokenInfos[usdOFT].reserve >= quoteAmount, "WooPPV3: USD_BALANCE_NOT_ENOUGH");

        // ATTENTION: for cross swap, usdOFT will be burnt in usd->base swap
        WooUsdOFT(usdOFT).burn(address(this), quoteAmount);

        uint256 swapFee = (quoteAmount * tokenInfos[baseToken].feeRate) / 1e5;
        quoteAmount -= swapFee; // NOTE: quote deducted the swap fee
        unclaimedFee += swapFee;

        {
            uint256 newPrice;
            IWooracleV2.State memory state = IWooracleV2(wooracle).state(baseToken);
            (baseAmount, newPrice) = _calcBaseAmountSellUsd(baseToken, quoteAmount, state);

            // TODO: uncomment it in prod version
            // IWooracleV2(wooracle).postPrice(baseToken, uint128(newPrice));
            // console.log('Post new price:', newPrice, newPrice/1e8);
            require(baseAmount >= minBaseAmount, "WooPPV3: baseAmount_LT_minBaseAmount");
        }

        tokenInfos[baseToken].reserve = uint192(tokenInfos[baseToken].reserve - baseAmount);

        if (to != address(this)) {
            TransferHelper.safeTransfer(baseToken, to, baseAmount);
        }

        emit WooSwap(
            usdOFT,
            baseToken,
            quoteAmount + swapFee,
            baseAmount,
            msg.sender,
            to,
            rebateTo,
            quoteAmount + swapFee,
            swapFee
        );
    }

    function _calcUsdAmountSellBase(
        address baseToken,
        uint256 baseAmount,
        IWooracleV2.State memory state
    ) internal view returns (uint256 usdAmount, uint256 newPrice) {
        require(state.woFeasible, "WooPPV3: !ORACLE_FEASIBLE");

        DecimalInfo memory decs = decimalInfo(baseToken);

        // usdAmount = baseAmount * oracle.price * (1 - oracle.k * baseAmount * oracle.price - oracle.spread)
        {
            uint256 coef = uint256(1e18) -
                ((uint256(state.coeff) * baseAmount * state.price) / decs.baseDec / decs.priceDec) -
                state.spread;
            usdAmount = (((baseAmount * decs.quoteDec * state.price) / decs.priceDec) * coef) / 1e18 / decs.baseDec;
        }

        // newPrice = oracle.price * (1 - 2 * k * oracle.price * baseAmount)
        newPrice =
            ((uint256(1e18) - (uint256(2) * state.coeff * state.price * baseAmount) / decs.priceDec / decs.baseDec) *
                state.price) /
            1e18;
    }

    function _calcBaseAmountSellUsd(
        address baseToken,
        uint256 usdAmount,
        IWooracleV2.State memory state
    ) internal view returns (uint256 baseAmount, uint256 newPrice) {
        require(state.woFeasible, "WooPPV3: !ORACLE_FEASIBLE");

        DecimalInfo memory decs = decimalInfo(baseToken);

        // baseAmount = usdAmount / oracle.price * (1 - oracle.k * usdAmount - oracle.spread)
        {
            uint256 coef = uint256(1e18) - (usdAmount * state.coeff) / decs.quoteDec - state.spread;
            baseAmount = (((usdAmount * decs.baseDec * decs.priceDec) / state.price) * coef) / 1e18 / decs.quoteDec;
        }

        // new_price = oracle.price * (1 + 2 * k * usdAmount)
        newPrice =
            ((uint256(1e18) * decs.quoteDec + uint256(2) * state.coeff * usdAmount) * state.price) /
            decs.quoteDec /
            1e18;
    }

    function _maxUInt16(uint16 a, uint16 b) private pure returns (uint16) {
        return a > b ? a : b;
    }

    function _maxUInt64(uint64 a, uint64 b) private pure returns (uint64) {
        return a > b ? a : b;
    }
}
