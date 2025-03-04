// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import {Setup} from "./Setup.sol";

abstract contract Properties is Setup, Asserts {
    // WP-14: Adding/removing liquidity doesn’t change the price of tokens in the pool
    // @audit this needs to be run on pool without swap function since they break the invariant
    function invariant_liquidityDoesntChangePrice() public returns (bool) {
        (uint128 baseToken1CurrentPrice, , ) = oracle.infos(address(baseToken1));
        (uint128 baseToken2CurrentPrice, , ) = oracle.infos(address(baseToken2));
        (uint128 baseToken3CurrentPrice, , ) = oracle.infos(address(baseToken3));

        return
            baseToken1CurrentPrice == baseToken1StartPrice &&
            baseToken2CurrentPrice == baseToken2StartPrice &&
            baseToken3CurrentPrice == baseToken3StartPrice;
    }
}
