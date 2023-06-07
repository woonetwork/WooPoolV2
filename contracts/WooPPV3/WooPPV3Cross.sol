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

import "./WooPPV3.sol";

import {WooUsdOFT} from "./WooUsdOFT.sol";
import {NonblockingLzApp} from "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";

import {IWooPPV3Cross} from "../interfaces/IWooPPV3Cross.sol";

/// @title Woo Cross Chain Router
contract WooPPV3Cross is WooPPV3, IWooPPV3Cross {
    // int256 public usdReserve;    // USD (virtual quote) balance
    address public usdOFT;

    mapping(address => bool) public isCrossAllowed;

    modifier onlyCrossAllowed() {
        require(isCrossAllowed[_msgSender()], "WooPPV3Cross: !allowed");
        _;
    }

    constructor(address _usdOFT) {
        usdOFT = _usdOFT;
    }

    function swapBaseToUsd(
        address baseToken,
        uint256 baseAmount,
        uint256 minQuoteAmount,
        address to,
        address rebateTo
    ) public nonReentrant whenNotPaused returns (uint256 quoteAmount) {
        require(baseToken != address(0), "WooPPV3Cross: !baseToken");
        require(to != address(0), "WooPPV3Cross: !to");
        require(
            balance(baseToken) - tokenInfos[baseToken].reserve >= baseAmount,
            "WooPPV3Cross: BASE_BALANCE_NOT_ENOUGH"
        );

        {
            uint256 newPrice;
            IWooracleV2.State memory state = IWooracleV2(wooracle).state(baseToken);
            (quoteAmount, newPrice) = _calcUsdAmountSellBase(baseToken, baseAmount, state);
            IWooracleV2(wooracle).postPrice(baseToken, uint128(newPrice));
            // console.log('Post new price:', newPrice, newPrice/1e8);
        }

        uint256 swapFee = (quoteAmount * tokenInfos[baseToken].feeRate) / 1e5;
        quoteAmount -= swapFee;
        require(quoteAmount >= minQuoteAmount, "WooPPV3Cross: quoteAmount_LT_minQuoteAmount");

        unclaimedFee += swapFee;
        tokenInfos[baseToken].reserve = uint192(tokenInfos[baseToken].reserve + baseAmount);

        // ATTENTION: for cross chain, usdOFT will be minted in base->usd swap
        WooUsdOFT(usdOFT).mint(to, quoteAmount + swapFee);

        emit WooSwap(
            baseToken,
            address(0),
            baseAmount,
            quoteAmount,
            msg.sender,
            to,
            rebateTo,
            (quoteAmount + swapFee),
            swapFee
        );
    }

    function swapUsdToBase(
        address baseToken,
        uint256 quoteAmount,
        uint256 minBaseAmount,
        address to,
        address rebateTo
    ) public onlyCrossAllowed whenNotPaused returns (uint256 baseAmount) {
        require(baseToken != address(0), "WooPPV3Cross: !baseToken");
        require(to != address(0), "WooPPV3Cross: !to");

        // TODO: double check this logic
        require(balance(usdOFT) - unclaimedFee >= quoteAmount, "WooPPV3Cross: USD_BALANCE_NOT_ENOUGH");

        uint256 swapFee = (quoteAmount * tokenInfos[baseToken].feeRate) / 1e5;
        quoteAmount -= swapFee; // NOTE: quote deducted the swap fee
        unclaimedFee += swapFee;

        {
            uint256 newPrice;
            IWooracleV2.State memory state = IWooracleV2(wooracle).state(baseToken);
            (baseAmount, newPrice) = _calcBaseAmountSellUsd(baseToken, quoteAmount, state);
            IWooracleV2(wooracle).postPrice(baseToken, uint128(newPrice));
            // console.log('Post new price:', newPrice, newPrice/1e8);
            require(baseAmount >= minBaseAmount, "WooPPV3Cross: baseAmount_LT_minBaseAmount");
        }

        tokenInfos[baseToken].reserve = uint192(tokenInfos[baseToken].reserve - baseAmount);

        // ATTENTION: for cross swap, usdOFT will be burnt in usd->base swap
        WooUsdOFT(usdOFT).burn(address(this), quoteAmount);

        if (to != address(this)) {
            TransferHelper.safeTransfer(baseToken, to, baseAmount);
        }

        emit WooSwap(
            address(0),
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
}
