// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {vm} from "@chimera/Hevm.sol";

abstract contract RouterTargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {
    function router_swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount,
        address payable to,
        address rebateTo
    ) public {
        router.swap(fromToken, toToken, fromAmount, minToAmount, to, rebateTo);
    }

    // this needs a external DEX mock for it to work properly
    function router_externalSwap(
        address approveTarget,
        address swapTarget,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount,
        address payable to,
        bytes calldata data
    ) public {
        router.externalSwap(approveTarget, swapTarget, fromToken, toToken, fromAmount, minToAmount, to, data);
    }
}
