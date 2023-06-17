// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

/*

░██╗░░░░░░░██╗░█████╗░░█████╗░░░░░░░███████╗██╗
░██║░░██╗░░██║██╔══██╗██╔══██╗░░░░░░██╔════╝██║
░╚██╗████╗██╔╝██║░░██║██║░░██║█████╗█████╗░░██║
░░████╔═████║░██║░░██║██║░░██║╚════╝██╔══╝░░██║
░░╚██╔╝░╚██╔╝░╚█████╔╝╚█████╔╝░░░░░░██║░░░░░██║
░░░╚═╝░░░╚═╝░░░╚════╝░░╚════╝░░░░░░░╚═╝░░░░░╚═╝

*
* MIT License
* ===========
*
* Copyright (c) 2020 WooTrade
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

import "../interfaces/IWooPPV3.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IWooRouterV3.sol";

import "../libraries/TransferHelper.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Woo Swap Router V3
/// @notice Router for stateless execution of swaps based on WooPPV3
contract WooRouterV3 is IWooRouterV3, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ----- Constant variables ----- */

    // Erc20 placeholder address for native tokens (e.g. eth, bnb, matic, etc)
    address constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ----- State variables ----- */

    // Wrapper for native tokens (e.g. eth, bnb, matic, etc)
    // BSC WBNB: 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c
    address public immutable WETH;

    IWooPPV3 public wooPP;

    mapping(address => bool) public isWhitelisted;

    /* ----- Callback Function ----- */

    receive() external payable {
        // only accept ETH from WETH or whitelisted external swaps.
        assert(msg.sender == WETH || isWhitelisted[msg.sender]);
    }

    /* ----- Query & swap APIs ----- */

    constructor(address _weth, address _wooPP) {
        require(_weth != address(0), "WooRouterV3: !weth");
        WETH = _weth;
        wooPP = IWooPPV3(_wooPP);
    }

    function usdOFT() external view returns (address) {
        return wooPP.usdOFT();
    }

    /// @inheritdoc IWooRouterV3
    function querySwap(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) external view override returns (uint256 toAmount) {
        require(fromToken != address(0), "WooRouterV3: !fromToken");
        require(toToken != address(0), "WooRouterV3: !toToken");
        fromToken = (fromToken == ETH_PLACEHOLDER_ADDR) ? WETH : fromToken;
        toToken = (toToken == ETH_PLACEHOLDER_ADDR) ? WETH : toToken;
        toAmount = wooPP.query(fromToken, toToken, fromAmount);
    }

    function tryQuerySwap(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) external view override returns (uint256 toAmount) {
        if (fromToken == address(0) || toToken == address(0)) {
            return 0;
        }
        fromToken = (fromToken == ETH_PLACEHOLDER_ADDR) ? WETH : fromToken;
        toToken = (toToken == ETH_PLACEHOLDER_ADDR) ? WETH : toToken;
        toAmount = wooPP.tryQuery(fromToken, toToken, fromAmount);
    }

    /// @inheritdoc IWooRouterV3
    function swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount,
        address payable to,
        address rebateTo
    ) external payable override nonReentrant returns (uint256 realToAmount) {
        require(fromToken != address(0), "WooRouterV3: !fromToken");
        require(toToken != address(0), "WooRouterV3: !toToken");
        require(to != address(0), "WooRouterV3: !to");

        bool isFromETH = fromToken == ETH_PLACEHOLDER_ADDR;
        bool isToETH = toToken == ETH_PLACEHOLDER_ADDR;
        fromToken = isFromETH ? WETH : fromToken;
        toToken = isToETH ? WETH : toToken;

        // Step 1: transfer the source tokens to WooRouterV3
        if (isFromETH) {
            require(fromAmount <= msg.value, "WooRouterV3: fromAmount_INVALID");
            IWETH(WETH).deposit{value: msg.value}();
            TransferHelper.safeTransfer(WETH, address(wooPP), fromAmount);
        } else {
            TransferHelper.safeTransferFrom(fromToken, msg.sender, address(wooPP), fromAmount);
        }

        // Step 2: swap and transfer
        if (isToETH) {
            realToAmount = wooPP.swap(fromToken, toToken, fromAmount, minToAmount, address(this), rebateTo);
            IWETH(WETH).withdraw(realToAmount);
            TransferHelper.safeTransferETH(to, realToAmount);
        } else {
            realToAmount = wooPP.swap(fromToken, toToken, fromAmount, minToAmount, to, rebateTo);
        }

        // Step 3: firing event
        emit WooRouterSwap(
            SwapType.WooSwap,
            isFromETH ? ETH_PLACEHOLDER_ADDR : fromToken,
            isToETH ? ETH_PLACEHOLDER_ADDR : toToken,
            fromAmount,
            realToAmount,
            msg.sender,
            to,
            rebateTo
        );
    }

    /// @inheritdoc IWooRouterV3
    function externalSwap(
        address approveTarget,
        address swapTarget,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount,
        address payable to,
        bytes calldata data
    ) external payable override nonReentrant returns (uint256 realToAmount) {
        require(approveTarget != address(0), "WooRouterV3: approveTarget_ADDR_ZERO");
        require(swapTarget != address(0), "WooRouterV3: swapTarget_ADDR_ZERO");
        require(fromToken != address(0), "WooRouterV3: fromToken_ADDR_ZERO");
        require(toToken != address(0), "WooRouterV3: toToken_ADDR_ZERO");
        require(to != address(0), "WooRouterV3: to_ADDR_ZERO");
        require(isWhitelisted[approveTarget], "WooRouterV3: APPROVE_TARGET_NOT_ALLOWED");
        require(isWhitelisted[swapTarget], "WooRouterV3: SWAP_TARGET_NOT_ALLOWED");

        uint256 preBalance = _generalBalanceOf(toToken, address(this));
        _internalFallbackSwap(approveTarget, swapTarget, fromToken, fromAmount, data);
        uint256 postBalance = _generalBalanceOf(toToken, address(this));

        require(preBalance <= postBalance, "WooRouterV3: balance_ERROR");
        realToAmount = postBalance - preBalance;
        require(realToAmount >= minToAmount && realToAmount > 0, "WooRouterV3: realToAmount_NOT_ENOUGH");
        _generalTransfer(toToken, to, realToAmount);

        emit WooRouterSwap(SwapType.DodoSwap, fromToken, toToken, fromAmount, realToAmount, msg.sender, to, address(0));
    }

    /* ----- Admin functions ----- */

    /// @dev Rescue the specified funds when stuck happen
    /// @param stuckToken the stuck token address
    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        if (stuckToken == ETH_PLACEHOLDER_ADDR) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, msg.sender, amount);
        }
    }

    /// @dev Set wooPP
    /// @param _wooPP new wooPP address
    function setWooPP(address _wooPP) public onlyOwner {
        wooPP = IWooPPV3(_wooPP);
        emit wooPPChanged(_wooPP);
    }

    /// @dev Add target address into whitelist
    /// @param target address that approved by WooRouterV3
    /// @param whitelisted approve to using WooRouterV3 or not
    function setWhitelisted(address target, bool whitelisted) external onlyOwner {
        require(target != address(0), "WooRouterV3: target_ADDR_ZERO");
        isWhitelisted[target] = whitelisted;
    }

    /* ----- Private Function ----- */

    function _internalFallbackSwap(
        address approveTarget,
        address swapTarget,
        address fromToken,
        uint256 fromAmount,
        bytes calldata data
    ) private {
        require(isWhitelisted[approveTarget], "WooRouterV3: APPROVE_TARGET_NOT_ALLOWED");
        require(isWhitelisted[swapTarget], "WooRouterV3: SWAP_TARGET_NOT_ALLOWED");

        if (fromToken != ETH_PLACEHOLDER_ADDR) {
            TransferHelper.safeTransferFrom(fromToken, msg.sender, address(this), fromAmount);
            TransferHelper.safeApprove(fromToken, approveTarget, fromAmount);
        } else {
            require(fromAmount <= msg.value, "WooRouterV3: fromAmount_INVALID");
        }

        (bool success, ) = swapTarget.call{value: fromToken == ETH_PLACEHOLDER_ADDR ? fromAmount : 0}(data);
        require(success, "WooRouterV3: FALLBACK_SWAP_FAILED");
    }

    function _generalTransfer(
        address token,
        address payable to,
        uint256 amount
    ) private {
        if (amount > 0) {
            if (token == ETH_PLACEHOLDER_ADDR) {
                TransferHelper.safeTransferETH(to, amount);
            } else {
                TransferHelper.safeTransfer(token, to, amount);
            }
        }
    }

    function _generalBalanceOf(address token, address who) private view returns (uint256) {
        return token == ETH_PLACEHOLDER_ADDR ? who.balance : IERC20(token).balanceOf(who);
    }
}
