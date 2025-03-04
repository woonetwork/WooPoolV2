// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {vm} from "@chimera/Hevm.sol";
import "forge-std/console.sol";

// @audit should add try catch to see where these revert
abstract contract OracleTargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {
    // function oracle_price(uint8 baseIndex) public {
    //     address baseToken = _boundTokenInSystem(baseIndex);
    //     uint256 woPrice_ = uint256(infos[_base].price);
    //     uint256 woPriceTimestamp = timestamp;

    //     (uint256 priceOut, bool feasible) = oracle.price(baseToken);
    // }

    // @audit when used in the above functions bounds input token values to those included in setup
    // NOTE: could be useful to include any tokens deposited in pool in this array to manipulate donated tokens
    function _boundTokenInSystem(uint8 fuzzedIndex) internal returns (address token) {
        uint8 boundedIndex = fuzzedIndex % uint8(tokensInSystem.length - 1);
        token = tokensInSystem[boundedIndex];
    }

    function _boundTokenAmount(
        address token,
        address addressBalanceToBound,
        uint256 amount
    ) internal returns (uint256 boundedAmount) {
        uint256 tokenBalance = IERC20(token).balanceOf(addressBalanceToBound);
        boundedAmount = amount % (tokenBalance + 1);
    }
}
