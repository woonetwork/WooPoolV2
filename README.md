<p align="center"><img src="https://files.gitbook.com/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F-McghiWP3H5y-b9oQ6H6-887967055%2Fuploads%2FMaPxIQMWO8RcUv6vMK1n%2Flogo2.png?alt=media&token=e51ef4bd-664e-4356-9e38-fdfa12baf27d" width="320" /></p>
<div align="center">
  <a href="https://github.com/woonetwork/WooPoolV2/actions/workflows/checks.yaml" style="text-decoration:none;">
    <img src="https://github.com/woonetwork/WooPoolV2/actions/workflows/checks.yaml/badge.svg" alt='Build & Build' />
  </a>
  <a href='https://github.com/woonetwork/WooPoolV2/actions/workflows/tests.yaml' style="text-decoration:none;">
    <img src='https://github.com/woonetwork/WooPoolV2/actions/workflows/tests.yaml/badge.svg' alt='Unit Tests' />
  </a>
</div>

## WOOFi Swap V2.0

This repository contains the smart contracts and solidity library for the WOOFi swap. WOOFi Swap is a decentralized exchange using a brand new on-chain market making algorithm called Synthetic Proactive Market Making version 2 (sPMM v2), which is designed for professional market makers to generate an on-chain orderbook simulating the price, spread and depth from centralized liquidity sources. Read more here.

## Security

#### Bug Bounty

Bug bounty for the smart contracts: [Bug Bounty](https://learn.woo.org/woofi/woofi-swap/bug-bounty).

#### Security Audit

3rd party security audit: [Audit Report](https://learn.woo.org/woofi/woofi-swap/audits).

#### Run

```shell
yarn
npx hardhat compile
npx hardhat test
```
