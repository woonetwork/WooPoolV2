// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "forge-std/console.sol";

contract MockWETHOracle is Ownable, ReentrancyGuard {

    function decimals() external view returns (uint8 _decimals) {
        _decimals = 8;
    }

    function description() external view returns (string memory _desc) {
        _desc = "WETH";
    }

    //function version() external view returns (uint256);

    /// getRoundData and latestRoundData should both raise "No data present"
    /// if they do not have data to report, instead of returning unset values
    /// which could be misinterpreted as actual reported values.
    // function getRoundData(uint80 _roundId)
    //     external
    //     view
    //     returns (
    //         uint80 roundId,
    //         int256 answer,
    //         uint256 startedAt,
    //         uint256 updatedAt,
    //         uint80 answeredInRound
    //     );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            roundId = 18446744073710118040;
            answer = 320976000000;
            startedAt = 1712978791;
            updatedAt = 1712978791;
            answeredInRound = 18446744073710118040;
        }
}