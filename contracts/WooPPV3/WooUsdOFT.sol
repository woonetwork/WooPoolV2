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
import {OFTV2} from "@layerzerolabs/solidity-examples/contracts/token/oft/v2/OFTV2.sol";

/// @title Woo Cross Chain Router
contract WooUsdOFT is OFTV2 {
    event WooPPUpdated(address indexed addr, bool flag);

    mapping(address => bool) public isWooPP;

    modifier onlyWooPPAllowed() {
        require(isWooPP[_msgSender()], "WooUsdOFT: !allowed");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint
    ) OFTV2(_name, _symbol, decimals(), _lzEndpoint) {
    }

    function decimals() public override pure returns (uint8) {
        return 6;
    }

    function mint(address _user, uint256 _amount) public onlyWooPPAllowed {
        _mint(_user, _amount);
    }

    function burn(address _user, uint256 _amount) public onlyWooPPAllowed {
        _burn(_user, _amount);
    }

    function setWooPP(address _wooPP, bool _flag) public onlyOwner {
        isWooPP[_wooPP] = _flag;
        emit WooPPUpdated(_wooPP, _flag);
    }
}