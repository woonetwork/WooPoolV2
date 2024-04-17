// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Setup} from "./Setup.sol";

abstract contract BeforeAfter is Setup {
    struct Vars {
        uint192 fromTokenReserve;
        uint192 toTokenReserve;
        uint256 fromPrice;
        uint256 toPrice;
    }

    Vars internal _before;
    Vars internal _after;

    function __before(address _fromToken, address _toToken) internal {
        (_before.fromTokenReserve, , , ) = pool.tokenInfos(_fromToken);
        (_before.toTokenReserve, , , ) = pool.tokenInfos(_toToken);

        (_before.fromPrice, ) = oracle.price(_fromToken);
        (_before.toPrice, ) = oracle.price(_toToken);
    }

    function __after(address _fromToken, address _toToken) internal {
        (_after.fromTokenReserve, , , ) = pool.tokenInfos(_fromToken);
        (_after.toTokenReserve, , , ) = pool.tokenInfos(_toToken);

        (_after.fromPrice, ) = oracle.price(_fromToken);
        (_after.toPrice, ) = oracle.price(_toToken);
    }
}
