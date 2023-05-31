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

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWooracleV2} from "./interfaces/IWooracleV2.sol";

import "./libraries/TransferHelper.sol";

/// @title Wooracle V2 contract for L2 chains for calldata zip.
contract WooracleV2Zip {
    mapping(uint8 => address) public bases;

    IWooracleV2 public wooracle;

    modifier onlyAdmin() {
        require(wooracle.isAdmin(msg.sender), "WooracleV2Zip: !Admin");
        _;
    }

    constructor(address _wooracle) {
        wooracle = IWooracleV2(_wooracle);
    }

    function setWooracle(address _wooracle) external onlyAdmin {
        wooracle = IWooracleV2(_wooracle);
    }

    function setBase(uint8 _id, address _base) external onlyAdmin {
        require(getBase(_id) == address(0), "WooracleV2Zip: !id_SET_ALREADY");
        bases[_id] = _base;
    }

    function getBase(uint8 _id) public view returns (address) {
        address[5] memory CONST_BASES = [
            // mload
            // NOTE: Update token address for different chains
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, // WETH
            0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, // WBTC
            0xcAFcD85D8ca7Ad1e1C6F82F651fA15E33AEfD07b, // WOO
            0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, // USDT
            0x912CE59144191C1204E64559FE8253a0e49E6548 // ARB
        ];

        return _id < 5 ? CONST_BASES[_id] : bases[_id];
    }

    /* ----- External Functions ----- */

    // https://docs.soliditylang.org/en/v0.8.12/contracts.html#fallback-function
    // prettier-ignore
    fallback (bytes calldata _input) external onlyAdmin returns (bytes memory _output) {
        /*
            2 bit: 0: post prices, 1: post states, 2,3: for future operations
            6 bits: length

            post prices:
               [price] -->
                  base token: 8 bites (1 byte)
                  price data: 32 bits = (27, 5)

            post states:
               [states] -->
                  base token: 8 bites (1 byte)
                  price:      32 bits (4 bytes) = (27, 5)
                  k coeff:    16 bits (2 bytes) = (11, 5)
                  s spread:   16 bits (2 bytes) = (11, 5)
        */
        uint256 x = _input.length;
        require(x > 0, "WooracleV2Zip: !calldata");

        uint8 firstByte = uint8(bytes1(_input[0]));
        uint8 op = firstByte >> 6; // 11000000
        uint8 len = firstByte & 0x3F; // 00111111
        if (op == 0) {
            // post prices list
            address base;
            uint128 p;
            for (uint256 i = 0; i < len; ++i) {
                base = getBase(uint8(bytes1(_input[1 + i * 5:1 + i * 5 + 1])));
                p = _price(uint32(bytes4(_input[1 + i * 5 + 1:1 + i * 5 + 5])));
                wooracle.postPrice(base, p);
            }
        } else if (op == 1) {
            // post states list
            address base;
            uint128 p;
            uint64 s;
            uint64 k;
            for (uint256 i = 0; i < len; ++i) {
                base = getBase(uint8(bytes1(_input[1 + i * 9:1 + i * 9 + 1])));
                p = _price(uint32(bytes4(_input[1 + i * 9 + 1:1 + i * 9 + 5])));
                s = _ks(uint16(bytes2(_input[1 + i * 9 + 5:1 + i * 9 + 7])));
                k = _ks(uint16(bytes2(_input[1 + i * 9 + 7:1 + i * 9 + 9])));
                wooracle.postState(base, p, s, k);
            }
        } else {
            // not supported
        }
    }

    function _price(uint32 b) internal pure returns (uint128) {
        return uint128((b >> 5) * (10**(b & 0x1F))); // 0x1F = 00011111
    }

    function _ks(uint16 b) internal pure returns (uint64) {
        return uint64((b >> 5) * (10**(b & 0x1F)));
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyAdmin {
        if (stuckToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, msg.sender, amount);
        }
    }
}
