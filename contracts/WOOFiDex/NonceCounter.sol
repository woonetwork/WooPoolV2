// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {INonceCounter} from "../interfaces/WOOFiDex/INonceCounter.sol";

contract NonceCounter is INonceCounter, Ownable {
    /* ----- State Variables ----- */

    mapping(address => bool) public isCrossChainRouter;
    mapping(uint16 => uint256) public outboundNonce;

    /* ----- Modifiers ----- */

    modifier onlyCrossChainRouter() {
        require(isCrossChainRouter[_msgSender()], "NonceCounter: not crossChainRouter");
        _;
    }

    /* ----- Functions ----- */

    function setCrossChainRouter(address crossChainRouter, bool flag) external onlyOwner {
        isCrossChainRouter[crossChainRouter] = flag;
        emit CrossChainRouterUpdated(crossChainRouter, flag);
    }

    function increment(uint16 dstChainId) external override onlyCrossChainRouter returns (uint256) {
        return ++outboundNonce[dstChainId];
    }
}
