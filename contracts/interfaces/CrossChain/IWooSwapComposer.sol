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

/// @title IWooSwapComposer
/// @notice functions to interface for WOOFi swap & cross-swap with composability support
interface IWooSwapComposer {
    /* ----- Structs ----- */

    struct LocalSwapInfos {
        address fromToken;
        address toToken;
        uint256 fromAmount;
        uint256 minToAmount;
        address rebateTo;
        bytes payload;
    }

    struct SrcInfos {
        address fromToken;
        address bridgeToken;
        uint256 fromAmount;
        uint256 minBridgeAmount;
    }

    struct Src1inch {
        address swapRouter;
        bytes data;
    }

    struct DstInfos {
        uint16 chainId;
        address toToken;
        address bridgeToken;
        uint256 minToAmount;
        uint256 airdropNativeAmount;
        uint256 dstGasForCall;
        bytes composePayload;
    }

    struct Dst1inch {
        address swapRouter;
        bytes data;
    }

    struct ComposeInfo {
        uint256 refId;
        address to;
        address srcAddr;
        address toToken;
        address bridgedToken;
        uint256 bridgedAmount;
        uint256 minToAmount;
        Dst1inch dst1inch;
        bytes composePayload;
    }

    /* ----- Events ----- */

    event WooCrossSwapOnSrcChain(
        uint256 indexed refId,
        address indexed sender,
        address indexed to,
        address fromToken,
        uint256 fromAmount,
        address bridgeToken,
        uint256 minBridgeAmount,
        uint256 realBridgeAmount,
        uint8 swapType,
        uint256 fee
    );

    event WooCrossSwapOnDstChain(
        uint256 indexed refId,
        address indexed sender,
        address indexed to,
        address bridgedToken,
        uint256 bridgedAmount,
        address toToken,
        address realToToken,
        uint256 minToAmount,
        uint256 realToAmount,
        uint8 swapType,
        uint256 fee
    );

    event WooSwapCrossComposeFailed(
        uint256 indexed refId,
        address indexed sender,
        address indexed to,
        address toToken,
        uint256 amount,
        bytes reason
    );

    event WooSwapLocalComposeFailed(
        address indexed sender,
        address indexed to,
        address toToken,
        uint256 amount,
        bytes reason
    );

    /* ----- State Variables ----- */

    function bridgeSlippage() external view returns (uint256);

    function wooCrossComposers(uint16 chainId) external view returns (address wooCrossComposer);

    /* ----- Functions ----- */

    function swap(
        address payable composeTo,
        LocalSwapInfos memory infoWOOFi,
        Src1inch calldata info1inch
    ) external payable returns (uint256 realToAmount);

    function crossSwap(
        address payable composeTo,
        SrcInfos memory srcInfos,
        DstInfos calldata dstInfos,
        Src1inch calldata src1inch,
        Dst1inch calldata dst1inch
    ) external payable;

    function quoteLayerZeroFee(
        address to,
        DstInfos calldata dstInfos,
        Dst1inch calldata dst1inch
    ) external view returns (uint256 nativeAmount, uint256 zroAmount);
}
