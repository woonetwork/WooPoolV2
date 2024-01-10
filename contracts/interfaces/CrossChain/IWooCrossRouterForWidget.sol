// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

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

import {IWooCrossChainRouterV3} from "./IWooCrossChainRouterV3.sol";

/// @title IWooCrossRouterForWidget
/// @notice functions to interface for WOOFi swap & cross-swap for 3rd party widget
interface IWooCrossRouterForWidget {
    /* ----- Structs ----- */

    struct FeeInfo {
        uint256 feeRate; // in 0.1 bps : 1/100000
        address feeAddr;
    }

    struct LocalSwapInfos {
        address fromToken;
        address toToken;
        uint256 fromAmount;
        uint256 minToAmount;
        address rebateTo;
        bytes payload;
    }

    /* ----- Functions ----- */

    function swap(
        address payable to,
        LocalSwapInfos memory infoWOOFi,
        IWooCrossChainRouterV3.Src1inch calldata info1inch,
        FeeInfo calldata feeInfo
    ) external payable returns (uint256 realToAmount);

    function crossSwap(
        address payable to,
        IWooCrossChainRouterV3.SrcInfos memory srcInfos,
        IWooCrossChainRouterV3.DstInfos calldata dstInfos,
        IWooCrossChainRouterV3.Src1inch calldata src1inch,
        IWooCrossChainRouterV3.Dst1inch calldata dst1inch,
        FeeInfo calldata feeInfo
    ) external payable;

    function quoteLayerZeroFee(
        address to,
        IWooCrossChainRouterV3.DstInfos calldata dstInfos,
        IWooCrossChainRouterV3.Dst1inch calldata dst1inch
    ) external view returns (uint256 nativeAmount, uint256 zroAmount);
}
