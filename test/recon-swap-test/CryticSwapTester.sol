// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {PoolTargetFunctions} from "./PoolTargetFunctions.sol";
import {CryticAsserts} from "@chimera/CryticAsserts.sol";

// echidna . --contract CryticTester --config echidna.yaml
// medusa fuzz
contract CryticSwapTester is PoolTargetFunctions, CryticAsserts {
    constructor() payable {
        setup();
    }
}
