## Fuzz Testing Suite

The tests defined in this suite use the Recon scaffolding (you can learn more about it [here](https://allthingsfuzzy.substack.com/p/introducing-recon-invariant-testing?r=34r2zr)). These tests are made to work with the Echidna and Medusa fuzzers.

The general structure of the suite is as follows: 

- `Properties` -  Defines boolean invariant properties that get evaluated after each function call in call sequence created by fuzzer.

- `PoolTargetFunctions`, `OracleTargetFunctions`, `RouterTargetFunctions` - Defines the functions to be called by the fuzzer in the target contract, assertion tests in these functions are evaluated by the fuzzer each time the function with the assertion is called in a sequence.

- `Setup` - Used for deployments and setup needed before running the fuzzer

- `BeforeAfter` - Defines ghost variables for easily tracking changes to state variables before and after function calls.

- `CryticToFoundry` - Used for creating unit tests of broken properties from call sequences for easier debugging.

- `CryticTester` - The main entrypoint for the fuzzers

**Note**: this test suite uses an external testing setup so calls from any of the `TargetFunctions` contracts to the underlying contract will not preserve `msg.sender`.

The primary contract of focus due to limited time constraint was `WooPPV2` , although properties were also defined for the `WooracleV2_2` and `WooRouterV2` contracts. During the engagement Medusa executed 71,000,00+ calls on the invariant/fuzzing suite with no violations of any of the 10 properties tested and achieved 18% coverage on the `WooPPV2` contract (this figure doesn’t take into account non-public functions). 

Recommendation: in order to provide a greater guarantee that all properties defined on the system do in fact hold, more extensive fuzz/invariant tests are recommended to expand coverage on the `WooPPV2` ,`WooracleV2_2` and `WooRouterV2` contracts and including longer duration runs of the fuzzer would ensure greater depth coverage within these contract as the maximum run executed was 3-4 hours in this suite.

## Properties
The following properties were defined during the competition. 

- ✅ - tested 
- 🚧 - started testing (incomplete)
- ❌ - not tested

### WooPPV2
| Property | Description | Tested |
| --- | --- | --- |
| WP-01 | User always receives a minimum to amount after swapping | ✅ |
| WP-02 | Making deposit of token always leads to an increase in tokenInfos[token].reserve | ✅ |
| WP-03 | Withdrawing never leads to an increase in tokenInfos[token].reserve | ✅ |
| WP-04 | If calling swap doesn’t change the price, liquidity doesn’t change | ✅ |
| WP-05 | If swap for a given token A doesn’t lead to the payment of token A to the pool, it doesn’t lead to the receipt of token B | ✅ |
| WP-06 | After deposit, calling withdraw with same values always succeeds | ✅ |
| WP-07 | Calling withdraw with amount 0 doesn’t change liquidity of the pool | ✅ |
| WP-08 | Brokers always receive 20% rebate  | ❌ |
| WP-09 | If an asset has low liquidity in the pool, quotes with it should be more favorable to trader  | ❌ |
| WP-10 | Base tokens can only be added by the strategist | ❌ |
| WP-11 | Reserve accounting should always match the actual balance of tokens in the contract | ❌ |
| WP-12 | Swaps can’t be made to the 0 address (burning tokens isn’t allowed) | ✅ |
| WP-14 | Adding/removing liquidity doesn’t change the price of tokens in the pool | 🚧 |
| WP-15 | The transferred amount in a call to deposit is accounted for | ❌ |

### WooracleV2_2
| Property | Description | Tested |
| --- | --- | --- |
| WO-01 | Price updates from oracles never deviate more than ~0.1% | ❌ |
| WO-02 | Price feed falls back to chainlink if woPrice is infeasible and cloPreferred == true  | ❌ |

### WooRouterV2
Note: swap functionalities from WooPPV2 should also be tested here
| Property | Description | Tested |
| --- | --- | --- |
| WR-01 | external swaps to 3rd party DEX can’t be made to contracts that aren’t whitelisted | ❌ |
| WR-02 | user always receives a minimum to amount after swapping | ❌ |

### General
| Property | Description | Tested  |
| --- | --- | --- |
| GN-01 | When the quote token is changed in the oracle, pool must update the oracle it uses  | ❌ |