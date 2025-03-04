// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;
import "../../contracts/wooracle/WooracleV2_2.sol";

contract MockOracle is WooracleV2_2 {
    // @audit modified from actual oracle contract to always return woFeasible = true
    // function state(address _base) external view override returns (State memory) {
    //     TokenInfo memory info = infos[_base];
    //     (uint256 basePrice, ) = price(_base);
    //     return State({price: uint128(basePrice), spread: info.spread, coeff: info.coeff, woFeasible: true});
    // }
}
