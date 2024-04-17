// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {Properties} from "./Properties.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {vm} from "@chimera/Hevm.sol";
import "forge-std/console.sol";

abstract contract PoolTargetFunctions is BaseTargetFunctions, Properties, BeforeAfter {
    // coverage-tested: ✅
    function pool_swap(
        uint8 fromIndex,
        uint8 toIndex,
        uint256 fromAmount,
        uint256 minToAmount,
        address payable to,
        address rebateTo
    ) public {
        address fromToken = _boundTokenInSystem(fromIndex);
        address toToken = _boundTokenInSystem(toIndex);
        require(fromToken != toToken, "baseToken == quoteToken");

        __before(fromToken, toToken);

        uint256 recipientBalanceBefore = IERC20(toToken).balanceOf(to);
        // fromAmount needs to be clamped to max of sender's balance
        uint256 boundedFromAmount = _boundTokenAmount(fromToken, address(this), fromAmount);

        // transfers fromToken to the pool, this step is normally done in router but could be worked around here
        TransferHelper.safeTransferFrom(fromToken, address(this), address(pool), boundedFromAmount);

        try pool.swap(fromToken, toToken, boundedFromAmount, minToAmount, to, rebateTo) {
            uint256 recipientBalanceAfter = IERC20(toToken).balanceOf(to);

            __after(fromToken, toToken);

            // WP-01: User always receives a minimum to amount after swapping
            t(
                recipientBalanceAfter - recipientBalanceBefore >= minToAmount,
                "user doesn't receive minimum swap amount"
            );

            // WP-04: If calling swap doesn’t change the price, liquidity doesn’t change
            if ((_before.fromPrice - _after.fromPrice) == 0 && (_before.toPrice - _after.toPrice) == 0) {
                t(_before.fromTokenReserve == _after.fromTokenReserve, "fromToken liquidity changed in swap");
                t(_before.toTokenReserve == _after.toTokenReserve, "toToken liquidity changed in swap");
            }

            // WP-12: Swaps can’t be made to the 0 address which would burn tokens
            t(to != address(0), "swap was made to 0 address");

            // WO-01: Price updates never deviate more than ~0.1%
            // since tokens use 18 decimals, 0.1% would be 15 decimals (e15)
            t(
                _before.fromPrice * (1e18 - 1e15) <= _after.fromPrice &&
                    _after.fromPrice <= _before.fromPrice * (1e18 + 1e15),
                "price deviates more than 0.1%"
            );
        } catch {
            // t(false, "swap reverted");
        }
    }

    // coverage-tested: ✅
    function pool_swapWithoutTransfer(
        uint8 fromIndex,
        uint8 toIndex,
        uint256 fromAmount,
        uint256 minToAmount,
        address payable to,
        address rebateTo
    ) public {
        address fromToken = _boundTokenInSystem(fromIndex);
        address toToken = _boundTokenInSystem(toIndex);
        require(fromToken != toToken, "baseToken == quoteToken");

        __before(fromToken, toToken);

        uint256 recipientBalanceBefore = IERC20(toToken).balanceOf(to);
        // fromAmount needs to be clamped to max of sender's balance
        uint256 boundedFromAmount = _boundTokenAmount(fromToken, address(this), fromAmount);

        try pool.swap(fromToken, toToken, boundedFromAmount, minToAmount, to, rebateTo) {
            uint256 recipientBalanceAfter = IERC20(toToken).balanceOf(to);

            __after(fromToken, toToken);

            // WP-05: If swap for a given token A doesn’t lead to the payment of token A to the pool, it doesn’t lead to the receipt of token B
            t(recipientBalanceAfter == recipientBalanceBefore, "user receives toToken without paying");
        } catch {
            // t(false, "swap reverted");
        }
    }

    // coverage-tested: ✅
    function pool_deposit(uint8 tokenIndex, uint256 amount) public {
        address token = _boundTokenInSystem(tokenIndex);

        uint256 tokenBalanceTestSender = IERC20(token).balanceOf(address(this));
        uint256 boundedAmount = amount % (tokenBalanceTestSender + 1);

        (uint192 reserveBefore, , , ) = pool.tokenInfos(token);

        try pool.deposit(token, boundedAmount) {
            (uint192 reserveAfter, , , ) = pool.tokenInfos(token);

            if (boundedAmount == 0) {
                // depositing 0 tokens shouldn't increase the reserve accounting
                t(reserveAfter == reserveBefore, "reserve value increases with 0 deposit");
            } else {
                // WP-02: Making deposit of token always leads to an increase in tokenInfos[token].reserve
                t(reserveAfter > reserveBefore, "reserve value decreases after deposit");

                // WP-15: The transferred amount in a call to deposit is accounted for
                t(reserveAfter - reserveBefore == boundedAmount, "transferred amount isn't fully accounted for");
            }
        } catch {
            // t(false, "call to deposit reverted");
        }
    }

    // coverage-tested: ✅
    function pool_depositAll(uint8 tokenIndex) public {
        address token = _boundTokenInSystem(tokenIndex);

        uint256 tokenBalanceTestSender = IERC20(token).balanceOf(address(this));

        (uint192 reserveBefore, , , ) = pool.tokenInfos(token);

        try pool.depositAll(token) {
            (uint192 reserveAfter, , , ) = pool.tokenInfos(token);
            // WP-02: Making deposit of token always leads to an increase in tokenInfos[token].reserve
            t(reserveAfter == reserveBefore + tokenBalanceTestSender, "reserve value decreases after deposit");
        } catch {
            // t(false, "call to deposit reverted");
        }
    }

    // coverage-tested: ✅
    function pool_withdraw(uint8 tokenIndex, uint256 amount) public {
        address token = _boundTokenInSystem(tokenIndex);
        (uint192 reserveBefore, , , ) = pool.tokenInfos(token);

        // bounds amount to be no more than reserve amount to not cause unnecessary revert
        uint256 boundedAmount = amount % (reserveBefore + 1);

        try pool.withdraw(token, boundedAmount) {
            (uint192 reserveAfter, , , ) = pool.tokenInfos(token);

            if (boundedAmount == 0) {
                // WP-07: withdrawing 0 tokens shouldn't decrease the reserve accounting
                t(reserveAfter == reserveBefore, "reserve value changes with 0 withdraw");
            } else {
                // WP-03: Withdrawing never leads to an increase in tokenInfos[token].reserve
                t(reserveAfter < reserveBefore, "reserve value increases after withdraw");

                // WP-06: After deposit, calling withdraw with same values always succeeds
                t(reserveBefore - reserveAfter == boundedAmount, "the amount withdrawn is less than was deposited");
            }
        } catch {
            // t(false, "call to deposit reverted");
        }
    }

    // coverage-tested: ✅
    function pool_withdrawAll(uint8 tokenIndex) public {
        address token = _boundTokenInSystem(tokenIndex);
        (uint192 reserveBefore, , , ) = pool.tokenInfos(token);

        // bounds amount to be no more than poolSize
        uint256 poolSize = pool.poolSize(token);

        try pool.withdrawAll(token) {
            (uint192 reserveAfter, , , ) = pool.tokenInfos(token);

            if (poolSize == 0) {
                // withdrawing 0 tokens shouldn't decrease the reserve accounting
                t(reserveAfter == reserveBefore, "reserve value changes with 0 withdraw");
            } else {
                // WP-03: Withdrawing never leads to an increase in tokenInfos[token].reserve
                t(reserveAfter == reserveBefore - poolSize, "reserve value increases after withdraw");
            }
        } catch {
            // t(false, "call to deposit reverted");
        }
    }

    function pool_claimFee() public {
        pool.claimFee();
    }

    function pool_repayWeeklyLending(address wantToken) public {
        pool.repayWeeklyLending(wantToken);
    }

    function pool_repayPrincipal(address wantToken, uint256 principalAmount) public {
        pool.repayPrincipal(wantToken, principalAmount);
    }

    function pool_sync(address token) public {
        pool.sync(token);
    }

    // transfers any value tokens already in the pool directly to the pool
    function erc20_transfer(uint8 tokenIndex, uint256 amount) public {
        address token = _boundTokenInSystem(tokenIndex);
        uint256 boundedAmount = _boundTokenAmount(token, address(this), amount);

        IERC20(token).transfer(address(pool), boundedAmount);
    }

    // @audit when used in the above functions bounds input token values to those included in setup
    // NOTE: could be useful to include any tokens deposited in pool in this array to manipulate donated tokens
    function _boundTokenInSystem(uint8 fuzzedIndex) internal returns (address token) {
        uint8 boundedIndex = fuzzedIndex % uint8(tokensInSystem.length - 1);
        token = tokensInSystem[boundedIndex];
    }

    function _boundTokenAmount(
        address token,
        address addressWithBalanceToBound,
        uint256 amount
    ) internal returns (uint256 boundedAmount) {
        uint256 tokenBalance = IERC20(token).balanceOf(addressWithBalanceToBound);
        boundedAmount = amount % (tokenBalance + 1);
    }
}
