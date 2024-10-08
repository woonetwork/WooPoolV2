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

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IPauser, IPauseContract} from "./interfaces/IPauser.sol";

contract Pauser is IPauser, Ownable {
    mapping(address => bool) public isPauseRole;
    mapping(address => bool) public isUnpauseRole;

    modifier onlyPauseRole() {
        require(msg.sender == owner() || isPauseRole[msg.sender], "Pauser: not pause role");
        _;
    }

    modifier onlyUnpauseRole() {
        require(msg.sender == owner() || isUnpauseRole[msg.sender], "Pauser: not unpause role");
        _;
    }

    function pause(address pauseContract) external onlyPauseRole {
        IPauseContract(pauseContract).pause();
    }

    function unpause(address unpauseContract) external onlyUnpauseRole {
        IPauseContract(unpauseContract).unpause();
    }

    function setPauseRole(address addr, bool flag) external onlyOwner {
        isPauseRole[addr] = flag;
        emit PauseRoleUpdated(addr, flag);
    }

    function setUnpauseRole(address addr, bool flag) external onlyOwner {
        isUnpauseRole[addr] = flag;
        emit UnpauseRoleUpdated(addr, flag);
    }
}
