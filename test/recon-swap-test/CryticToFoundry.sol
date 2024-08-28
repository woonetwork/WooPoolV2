// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PoolTargetFunctions} from "./PoolTargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../contracts/interfaces/IWooracleV2.sol";
import "forge-std/console.sol";

contract CryticSwapToFoundry is Test, PoolTargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    // forge test --match-contract CryticSwapToFoundry -vvv
    function test_setUp() public {
        // check that contracts were properly deployed
        assertTrue(address(pool) != address(0), "pool not deployed");
        assertTrue(address(router) != address(0), "router not deployed");
        assertTrue(address(oracle) != address(0), "oracle not deployed");

        // check that CryticTester was properly minted tokens
        assertTrue(quoteToken.balanceOf(testSender) != 0, "quoteToken balance is 0");
        assertTrue(baseToken1.balanceOf(testSender) != 0, "baseToken1 balance is 0");
        assertTrue(baseToken2.balanceOf(testSender) != 0, "baseToken2 balance is 0");

        // check Router approvals
        assertTrue(
            quoteToken.allowance(address(this), address(router)) == type(uint256).max,
            "CryticTester: router quoteToken approval not set"
        );
        assertTrue(
            baseToken1.allowance(address(this), address(router)) == type(uint256).max,
            "CryticTester: router baseToken1 approval not set"
        );
        assertTrue(
            baseToken2.allowance(address(this), address(router)) == type(uint256).max,
            "CryticTester: router baseToken2 approval not set"
        );

        // check Pool approvals
        assertTrue(
            quoteToken.allowance(address(owner), address(pool)) == type(uint256).max,
            "owner: router quoteToken approval not set"
        );
        assertTrue(
            baseToken1.allowance(address(owner), address(pool)) == type(uint256).max,
            "owner: router baseToken1 approval not set"
        );
        assertTrue(
            baseToken2.allowance(address(owner), address(pool)) == type(uint256).max,
            "owner: router baseToken2 approval not set"
        );

        // check that pool owner is correct
        assertTrue(address(pool.owner()) == address(owner), "pool owner not properly set");

        // check that pool was properly initialized
        assertTrue(address(pool.wooracle()) == address(oracle), "oracle not properly set");
        assertTrue(address(pool.feeAddr()) == address(owner), "fee address not properly set");

        // check that quote token was properly set in oracle
        assertTrue(oracle.quoteToken() == address(quoteToken));

        // check that tokenInfo is properly set
        (uint192 reserveQuote, uint16 feeRateQuote, uint128 maxGammaQuote, uint128 maxNotionalSwapQuote) = pool.tokenInfos(
            address(quoteToken)
        );
        (uint192 reserve1, uint16 feeRate1, uint128 maxGamma1, uint128 maxNotionalSwap1) = pool.tokenInfos(
            address(baseToken1)
        );
        (uint192 reserve2, uint16 feeRate2, uint128 maxGamma2, uint128 maxNotionalSwap2) = pool.tokenInfos(
            address(baseToken2)
        );
        (uint192 reserve3, uint16 feeRate3, uint128 maxGamma3, uint128 maxNotionalSwap3) = pool.tokenInfos(
            address(baseToken3)
        );
        assertTrue(feeRate1 == feeRate && feeRate2 == feeRate && feeRate3 == feeRate, "fee rate not properly set");
        assertTrue(
            maxGamma1 == maxGamma && maxGamma2 == maxGamma && maxGamma3 == maxGamma,
            "max gamma not properly set"
        );
        assertTrue(
            maxNotionalSwap1 == maxNotionalSwap &&
                maxNotionalSwap2 == maxNotionalSwap &&
                maxNotionalSwap3 == maxNotionalSwap,
            "max notional swap not properly set"
        );

        // check that liquidity deposits by owner are properly accounted for
        assertTrue(reserve1 >= quoteMintAmount, "reserve balance of quoteToken isn't set");
        assertTrue(reserve1 >= baseMintAmount, "reserve balance of baseToken1 isn't set");
        assertTrue(reserve2 >= baseMintAmount, "reserve balance of baseToken2 isn't set");
        assertTrue(reserve3 >= baseMintAmount, "reserve balance of baseToken3 isn't set");
    }
}
