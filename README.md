<p align="center"><img src="https://files.gitbook.com/v0/b/gitbook-x-prod.appspot.com/o/spaces%2F-McghiWP3H5y-b9oQ6H6-887967055%2Fuploads%2FMaPxIQMWO8RcUv6vMK1n%2Flogo2.png?alt=media&token=e51ef4bd-664e-4356-9e38-fdfa12baf27d" width="320" /></p>
<div align="center">
  <a href="https://github.com/woonetwork/woofi_swap_smart_contracts/actions/workflows/build.yml" style="text-decoration:none;">
    <img src="https://github.com/woonetwork/woofi_swap_smart_contracts/actions/workflows/build.yml/badge.svg" alt='Build' />
  </a>
  <a href='https://github.com/woonetwork/woofi_swap_smart_contracts/actions/workflows/lint.yml' style="text-decoration:none;">
    <img src='https://github.com/woonetwork/woofi_swap_smart_contracts/actions/workflows/lint.yml/badge.svg' alt='Lint' />
  </a>
  <a href='https://github.com/woonetwork/woofi_swap_smart_contracts/actions/workflows/unit_tests.yml' style="text-decoration:none;">
    <img src='https://github.com/woonetwork/woofi_swap_smart_contracts/actions/workflows/unit_tests.yml/badge.svg' alt='Unit Tests' />
  </a>
</div>

## WOOFi Swap V2.0

This repository contains the smart contracts and solidity library for the WOOFi Swap v1. WOOFi Swap is a decentralized exchange using a brand new on-chain market making algorithm called Synthetic Proactive Market Making (sPMM), which is designed for professional market makers to generate an on-chain orderbook simulating the price, spread and depth from centralized liquidity sources. Read more here.

## Security

#### Bug Bounty

Bug bounty for the smart contracts: [Bug Bounty](https://learn.woo.org/woofi/woofi-swap/bug-bounty).

#### Security Audit

3rd party security audit: [Audit Report](https://learn.woo.org/woofi/woofi-swap/audits).

### Code Structure

It is a hybrid [Hardhat](https://hardhat.org/) repo that also requires [Foundry](https://book.getfoundry.sh/index.html) to run Solidity tests powered by the [ds-test library](https://github.com/dapphub/ds-test/).

> To install Foundry, please follow the instructions [here](https://book.getfoundry.sh/getting-started/installation.html).

### Run tests

- TypeScript tests are included in the `typescript` folder in the `test` folder at the root of the repo.
- Solidity tests are included in the `foundry` folder in the `test` folder at the root of the repo.

### Example of Foundry/Forge commands

```shell
forge build
forge test
forge test -vv
forge tree
```

### Example of Hardhat commands

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
npx hardhat help
REPORT_GAS=true npx hardhat test
npx hardhat coverage
npx hardhat run scripts/deploy.ts
TS_NODE_FILES=true npx ts-node scripts/deploy.ts
npx eslint '**/*.{js,ts}'
npx eslint '**/*.{js,ts}' --fix
npx prettier '**/*.{json,sol,md}' --check
npx prettier '**/*.{json,sol,md}' --write
npx solhint 'contracts/**/*.sol'
npx solhint 'contracts/**/*.sol' --fix
```