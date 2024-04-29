// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import "../../contracts/interfaces/IWooracleV2_2.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Strings} from "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {vm} from "@chimera/Hevm.sol";
import "forge-std/console.sol";

abstract contract PoolTargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {
    // fuzz-utils generate ./test/recon/CryticTester.sol --corpus-dir echidna --contract CryticTester --fuzzer echidna
    // coverage-tested: ✅
    function testFuzz_pool_swap(
        uint8 fromIndex,
        uint8 toIndex,
        uint256 fromAmount
        // uint256 minToAmount
    ) public {
        address fromToken = _boundTokenInSystem(fromIndex);
        address toToken = _boundTokenInSystem(toIndex);
        if (fromToken == toToken) {
            toToken = _boundTokenInSystem(toIndex % 255 + 1);
        }
        require(fromToken != toToken, "baseToken == quoteToken");

        address fromAddress = testSender;
        address payable to = payable(testSender);
        address rebateTo = testSender;
        console.log("from address:", fromAddress);

        __before(fromToken, toToken);

        uint256 recipientBalanceBefore = IERC20(toToken).balanceOf(to);
        // fromAmount needs to be clamped to max of sender's balance
        uint256 boundedFromAmount = _boundTokenAmount(fromToken, fromAddress, fromAmount);

        console.log("fromToken boundedFromAmount:", fromToken, boundedFromAmount);

        // transfers fromToken to the pool, this step is normally done in router but could be worked around here
        vm.prank(fromAddress);
        TransferHelper.safeTransferFrom(fromToken, fromAddress, address(pool), boundedFromAmount);

        uint256 minToAmount = 0;
        vm.prank(fromAddress);
        try pool.swap(fromToken, toToken, boundedFromAmount, minToAmount, to, rebateTo) {
            uint256 recipientBalanceAfter = IERC20(toToken).balanceOf(to);

            __after(fromToken, toToken);

            console.log("fromToken, toToken, fromAmount", fromToken, toToken, boundedFromAmount);
            console.log("_before.fromPrice, _before.toPrice", _before.fromPrice, _before.toPrice);
            console.log("_after.fromPrice, _after.toPrice", _after.fromPrice, _after.toPrice);
            console.log("_before.fromTokenReserve, _before.toTokenReserve", _before.fromTokenReserve, _before.toTokenReserve);
            console.log("_after.fromTokenReserve, _after.toTokenReserve", _after.fromTokenReserve, _after.toTokenReserve);

            uint256 total = _getNotionalTotal(testSender);

            logToFFI("total fromPrice(before, after), toPrice(before, after): ",
                    total,
                    _before.fromPrice,
                    _after.fromPrice, 
                    _before.toPrice,
                    _after.toPrice);

            // WP-01: User always receives a minimum to amount after swapping
            t(
                recipientBalanceAfter - recipientBalanceBefore >= minToAmount,
                "user doesn't receive minimum swap amount"
            );

            // WP-04: If calling swap doesn’t change the price, liquidity doesn’t change
            // if ((_before.fromPrice - _after.fromPrice) == 0 && (_before.toPrice - _after.toPrice) == 0) {
            //     t(_before.fromTokenReserve == _after.fromTokenReserve, "fromToken liquidity changed in swap");
            //     t(_before.toTokenReserve == _after.toTokenReserve, "toToken liquidity changed in swap");
            // }

            // WP-12: Swaps can’t be made to the 0 address which would burn tokens
            t(to != address(0), "swap was made to 0 address");

            // WO-01: Price updates never deviate more than ~0.1%
            // since tokens use 18 decimals, 0.1% would be 15 decimals (e15)
            t(
                _before.fromPrice * (1e18 - 1e15) <= _after.fromPrice * 1e18 &&
                    _after.fromPrice * 1e18 <= _before.fromPrice * (1e18 + 1e15),
                "price deviates more than 0.1%"
            );
        } catch Error(string memory reason) {
            bool assertFalse = false;
            if (Strings.equal(reason, "WooPPV2: baseAmount_LT_minBaseAmount")) {
                assertFalse = true;
            }
            if (Strings.equal(reason, "WooPPV2: quoteAmount_LT_minQuoteAmount")) {
                assertFalse = true;
            }
            if (Strings.equal(reason, "WooPPV2: base2Amount_LT_minBase2Amount")) {
                assertFalse = true;
            }
            
            t(assertFalse, reason);
        } catch {
            t(false, "swap reverted");
        }
    }

    function _getNotionalTotal(address owner) internal view returns(uint256 total) {
        total = 0;
        for (uint8 i = 0; i < tokensInSystem.length; ++i) {
            address token = tokensInSystem[i];
            //uint256 tokenBalance = IERC20(token).balanceOf(owner);
            uint256 tokenBalance = pool.balance(token);
            // IWooracleV2_2.State memory state = IWooracleV2_2(oracle).state(token);
            (uint256 cloPrice, ) = IWooracleV2_2(oracle).cloPrice(token);

            // console.log("i: token ", i, token);
            // console.log("tokenBalance cloPrice", tokenBalance, cloPrice);

            // (baseAmount * state.price * decs.quoteDec) / decs.baseDec / decs.priceDec;
            if (i == 0) {
                uint256 amount = (tokenBalance * cloPrice * 1e6) / 1e6 / 1e8;
                total += amount;
                // console.log("amount: ", amount);
            } else {
                uint256 amount = (tokenBalance * cloPrice * 1e6) / 1e18 / 1e8;
                total += amount;
                // console.log("amount: ", amount);
            }
        }
    }

    // @audit when used in the above functions bounds input token values to those included in setup
    // NOTE: could be useful to include any tokens deposited in pool in this array to manipulate donated tokens
    function _boundTokenInSystem(uint8 fuzzedIndex) internal view returns (address token) {
        uint8 boundedIndex = fuzzedIndex % uint8(tokensInSystem.length - 1);
        token = tokensInSystem[boundedIndex];
    }

    function _boundTokenAmount(
        address token,
        address addressWithBalanceToBound,
        uint256 amount
    ) internal view returns (uint256 boundedAmount) {
        uint256 tokenBalance = IERC20(token).balanceOf(addressWithBalanceToBound);
        tokenBalance = tokenBalance * 3 / 5;
        if (tokenBalance > maxNotionalSwap) {
            tokenBalance = maxNotionalSwap;
        }
        boundedAmount = amount % (tokenBalance + 1);
    }

    function logToFFI(string memory text, uint total, uint p0, uint p1, uint p2, uint p3) private returns (uint256) {
        // compile a string input that represents the bash script to run the python script
        // increment the number in brackets when adding more input params
        // input 2 should be the location of the python script
        // each variable is made up of a pair of a tag "--tag" and a stringifed version of the variable
        string[] memory inputs = new string[](14);
        inputs[0] = "python3";
        inputs[1] = "test/logger.py";
        inputs[2] = "--text";
        inputs[3] = text;
        inputs[4] = "--total";
        inputs[5] = Strings.toString(total);
        inputs[6] = "--p0";
        inputs[7] = Strings.toString(p0);
        inputs[8] = "--p1";
        inputs[9] = Strings.toString(p1);
        inputs[10] = "--p2";
        inputs[11] = Strings.toString(p2);
        inputs[12] = "--p3";
        inputs[13] = Strings.toString(p3);
        // use foundry ffi to run the python script
        bytes memory res = vm.ffi(inputs);
        // decode the result
        //uint256 ans = abi.decode(res, (uint256));
        return 0;
    }

    function strConcat(string memory _a, string memory _b) internal view returns (string memory){
        bytes memory _ba = bytes(_a);
        bytes memory _bb = bytes(_b);
        string memory ret = new string(_ba.length + _bb.length);
        bytes memory bret = bytes(ret);
        uint k = 0;
        for (uint i = 0; i < _ba.length; i++)bret[k++] = _ba[i];
        for (uint i = 0; i < _bb.length; i++) bret[k++] = _bb[i];
        return string(ret);
   }
}
