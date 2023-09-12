// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

interface INonceCounter {
    /* ----- Events ----- */

    event CrossChainRouterUpdated(address crossChainRouter, bool flag);

    /* ----- Functions ----- */

    function outboundNonce(uint16 dstChainId) external view returns (uint256 nonce);

    function increment(uint16 dstChainId) external returns (uint256 nonce);
}
