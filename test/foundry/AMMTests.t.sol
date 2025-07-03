// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import {Greeter} from "../../contracts/Greeter.sol";
import {TestHelpers} from "./TestHelpers.sol";

import {WooPPV2} from "../../contracts/WooPPV2.sol";
import {WooRouterV2} from "../../contracts/WooRouterV2.sol";
import {WooracleV2_2} from "../../contracts/wooracle/WooracleV2_2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "forge-std/console.sol";

contract AMMTests is TestHelpers {

    WooPPV2 public pool = WooPPV2(0x5520385bFcf07Ec87C4c53A7d8d65595Dff69FA4);
    WooracleV2_2 public oracle = WooracleV2_2(0xCf4EA1688bc23DD93D933edA535F8B72FC8934Ec);

    address private constant USDC_TOKEN = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // quote
    address private constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address private constant OWNER = 0xDe95557D3c243e116E40dD8e933c4c7A3939d515;
    address private constant TAPIR = address(69);

    uint loopAm = 1000;
    uint amountToSell = 200_000 * 1e6;

    function setUp() public {
        deal(USDC_TOKEN, TAPIR, amountToSell * 10); // 1M USDC
        deal(WBTC, OWNER, 100 * 1e8); // 100 btc

        vm.prank(OWNER);
        IERC20(WBTC).approve(address(pool), type(uint256).max);

        vm.prank(OWNER);
        pool.deposit(WBTC, 100 * 1e8);
    }

    // run this command to run the test:
    // forge test --fork-url https://arb1.arbitrum.io/rpc --match-contract AMMTests -vv
    function test_Sell_Partial() public {
        // sell 100k-100k-100k....100k 10 times, up to 1M USDC
        vm.startPrank(TAPIR);

        uint received;
        for (uint i; i < loopAm; ++i) {
            IERC20(USDC_TOKEN).transfer(address(pool), amountToSell / loopAm);
            received += pool.swap(USDC_TOKEN, WBTC, amountToSell / loopAm, 0, payable(TAPIR), TAPIR);
        }
        vm.stopPrank();
        console.log("Received", received);
    }

    function test_Sell_One_Go() public {
        // sell 1M USDC directly
        vm.startPrank(TAPIR);

        IERC20(USDC_TOKEN).transfer(address(pool), amountToSell);
        uint received = pool.swap(USDC_TOKEN, WBTC, amountToSell, 0, payable(TAPIR), TAPIR);
        
        vm.stopPrank();
        console.log("Received", received);
    }
}