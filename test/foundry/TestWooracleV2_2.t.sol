// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import {Greeter} from "../../contracts/Greeter.sol";
import {TestHelpers} from "./TestHelpers.sol";

import {WooPPV2} from "../../contracts/WooPPV2.sol";
import {WooRouterV2} from "../../contracts/WooRouterV2.sol";
import {WooracleV2_2} from "../../contracts/wooracle/WooracleV2_2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "forge-std/console.sol";

contract TestWooracleV2_2 is TestHelpers {

    WooPPV2 public pool;
    WooRouterV2 public router;
    WooracleV2_2 public oracle;

    address private constant ADMIN = address(1);
    address private constant ATTACKER = address(2);
    address private constant FEE_ADDR = address(4);

    // mainnet
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // QUOTE TOKEN
    address private constant WOO = 0x4691937a7508860F876c9c0a2a617E7d9E945D4B;
    address private constant USDC_USD_ORACLE = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private constant ETH_USD_ORACLE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    uint128 private constant MAX_NOTIONAL_USDC = 5000_000 * 1e18;
    uint128 private constant MAX_GAMMA = type(uint128).max;

    // deployed addresses

    function setUp() public {
        vm.startPrank(ADMIN);
        pool = new WooPPV2(USDC);
        router = new WooRouterV2(WETH, address(pool));
        oracle = new WooracleV2_2();

        oracle.setQuoteToken(USDC, USDC_USD_ORACLE);
        oracle.setCLOracle(WETH, ETH_USD_ORACLE, true);
        oracle.setWooPP(address(pool));

        oracle.postState(WETH, 346288977288, 363000000000000, 1000000000);
        oracle.setGuardian(ADMIN, true);
        oracle.setRange(WOO, 9000, 110000000);
        oracle.setAdmin(address(pool), true);

        pool.setWooracle(address(oracle));
        pool.setTokenInfo(WETH, 0, MAX_GAMMA, MAX_NOTIONAL_USDC);
        pool.setTokenInfo(WOO, 0, MAX_GAMMA, MAX_NOTIONAL_USDC);
        pool.setFeeAddr(FEE_ADDR);
        vm.stopPrank();
    }

    // forge test --fork-url https://rpc.ankr.com/eth --match-contract TestWooracleV2_2 -vvvv
    function test_Wooracle() public {
        vm.startPrank(ADMIN);

        oracle.woState(WETH);
        // (346288977288, 363000000000000, 1000000000, true)

        oracle.postState(WETH, 349833999632, 655000000000000, 1000000000);
        oracle.woState(WETH);

    //post (349833999632, 655000000000000, 1000000000)
        // (349833999632, 9773989383877141, 1000000000, true)

        oracle.postState(WETH, 348921000000, 566000000000000, 1000000000);
        oracle.woState(WETH);

        oracle.postState(WETH, 350021000000, 111000000000000, 1000000000);
        oracle.woState(WETH);

        oracle.postState(WETH, 351121000000, 111000000000000, 1000000000);
        oracle.woState(WETH);

        oracle.postState(WETH, 345420000000, 861000000000000, 1000000000);
        oracle.postState(WBTC, 6846630000000, 650000000000000, 1000000000);
        oracle.woState(WETH);
        oracle.woState(WBTC);

        oracle.postState(WETH, 345400000000, 0, 1000000000);
        oracle.woState(WETH);

        oracle.postState(WETH, 345820000000, 861000000000000, 1000000000);
        oracle.postState(WBTC, 6859100000000, 848000000000000, 1000000000);
        oracle.woState(WETH);
        oracle.woState(WBTC);

        oracle.postState(WETH, 345820000000, 111000000000000, 1000000000);
        oracle.woState(WETH);

        oracle.postState(WETH, 345820000000, 0, 0);
        oracle.woState(WETH);

        oracle.postState(WETH, 345830000000, 0, 0);
        oracle.woState(WETH);

        oracle.postState(WETH, 345820000000, 111000000000000, 1000000000);
        oracle.woState(WETH);

        vm.stopPrank();
    }

}