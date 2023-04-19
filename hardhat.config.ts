import type { HardhatUserConfig } from "hardhat/types";
import { task } from "hardhat/config";

import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-abi-exporter";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "dotenv/config";

import "@matterlabs/hardhat-zksync-deploy";
import "@matterlabs/hardhat-zksync-solc";
import "@matterlabs/hardhat-zksync-verify";

task("accounts", "Prints the list of accounts", async (_args, hre) => {
  const accounts = await hre.ethers.getSigners();
  accounts.forEach(async (account) => console.info(account.address));
});

const accounts = process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [];

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
      hardfork: "berlin", // Berlin is used (temporarily) to avoid issues with coverage
      mining: {
        auto: true,
        interval: 50000,
      },
      gasPrice: "auto",
    },
    bsc_mainnet: {
      url: "https://rpc.ankr.com/bsc/",
      chainId: 56,
      accounts: accounts,
    },
    bsc_testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      chainId: 97,
      accounts: accounts,
    },
    avalanche_mainnet: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      chainId: 43114,
      accounts: accounts,
    },
    avalanche_testnet: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      chainId: 43113,
      accounts: accounts,
    },
    fantom_mainnet: {
      url: "https://rpc.ftm.tools/",
      chainId: 250,
      accounts: accounts,
    },
    fantom_testnet: {
      url: "https://rpc.testnet.fantom.network/",
      chainId: 4002,
      accounts: accounts,
    },
    polygon_mainnet: {
      url: "https://polygon-rpc.com/",
      chainId: 137,
      accounts: accounts,
    },
    polygon_testnet: {
      url: "https://matic-mumbai.chainstacklabs.com/",
      chainId: 80001,
      accounts: accounts,
    },
    arbitrum_mainnet: {
      url: "https://arb1.arbitrum.io/rpc/",
      chainId: 42161,
      accounts: accounts,
    },
    arbitrum_testnet: {
      url: "https://rinkeby.arbitrum.io/rpc/",
      chainId: 421611,
      accounts: accounts,
    },
    optimism_mainnet: {
      url: "https://rpc.ankr.com/optimism/",
      chainId: 10,
      accounts: accounts,
    },
    optimism_testnet: {
      url: "https://goerli.optimism.io/",
      chainId: 420,
      accounts: accounts,
    },
    ethereum_mainnet: {
      url: "https://rpc.ankr.com/eth/",
      chainId: 1,
      accounts: accounts,
    },
    base_testnet: {
      url: "https://goerli.base.org/",
      chainId: 84531,
      accounts: accounts,
    },
    zksync_mainnet: {
      url: "https://mainnet.era.zksync.io",
      ethNetwork: "mainnet",
      zksync: true,
      verifyURL: "https://zksync2-mainnet-explorer.zksync.io/contract_verification",
    },
    zksync_testnet: {
      url: "https://zksync2-testnet.zksync.dev",
      ethNetwork: "goerli",
      zksync: true,
      verifyURL: "https://zksync2-testnet-explorer.zksync.dev/contract_verification",
    },
    polygon_zkevm_mainnet: {
      url: "https://zkevm-rpc.com/",
      chainId: 1101,
      accounts: accounts,
    },
    polygon_zkevm_testnet: {
      url: "https://rpc.public.zkevm-test.net/",
      chainId: 1442,
      accounts: accounts,
    },
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_KEY !== undefined ? process.env.ETHERSCAN_KEY : "",
      // binance smart chain
      bsc: process.env.BSCSCAN_KEY !== undefined ? process.env.BSCSCAN_KEY : "",
      bscTestnet: process.env.BSCSCAN_KEY !== undefined ? process.env.BSCSCAN_KEY : "",
      // avalanche
      avalanche: process.env.SNOWTRACE_KEY !== undefined ? process.env.SNOWTRACE_KEY : "",
      avalancheFujiTestnet: process.env.SNOWTRACE_KEY !== undefined ? process.env.SNOWTRACE_KEY : "",
      // fantom mainnet
      opera: process.env.FTMSCAN_KEY !== undefined ? process.env.FTMSCAN_KEY : "",
      ftmTestnet: process.env.FTMSCAN_KEY !== undefined ? process.env.FTMSCAN_KEY : "",
      // polygon
      polygon: process.env.POLYGONSCAN_KEY !== undefined ? process.env.POLYGONSCAN_KEY : "",
      polygonMumbai: process.env.POLYGONSCAN_KEY !== undefined ? process.env.POLYGONSCAN_KEY : "",
      // arbitrum
      arbitrumOne: process.env.ARBISCAN_KEY !== undefined ? process.env.ARBISCAN_KEY : "",
      arbitrumTestnet: process.env.ARBISCAN_KEY !== undefined ? process.env.ARBISCAN_KEY : "",
      // optimism
      optimisticEthereum: process.env.OPTIMISTIC_ETHERSCAN_KEY !== undefined ? process.env.OPTIMISTIC_ETHERSCAN_KEY : "",
      optimisticGoerli: process.env.OPTIMISTIC_ETHERSCAN_KEY !== undefined ? process.env.OPTIMISTIC_ETHERSCAN_KEY : "",
      base_testnet: "no-api-key-needed",
      polygon_zkevm_mainnet: process.env.ZKEVM_POLYGONSCAN_KEY !== undefined ? process.env.ZKEVM_POLYGONSCAN_KEY : "",
      polygon_zkevm_testnet: process.env.ZKEVM_POLYGONSCAN_KEY !== undefined ? process.env.ZKEVM_POLYGONSCAN_KEY : "",
    },
    customChains: [
      {
        network: "base_testnet",
        chainId: 84531,
        urls: {
          apiURL: "https://api-goerli.basescan.org/api",
          browserURL: "https://goerli.basescan.org",
        }
      },
      {
        network: "polygon_zkevm_mainnet",
        chainId: 1101,
        urls: {
          apiURL: "https://api-zkevm.polygonscan.com/api",
          browserURL: "https://zkevm.polygonscan.com",
        }
      },
      {
        network: "polygon_zkevm_testnet",
        chainId: 1442,
        urls: {
          apiURL: "https://api-testnet-zkevm.polygonscan.com/api",
          browserURL: "https://testnet-zkevm.polygonscan.com",
        }
      },
    ]
  },
  solidity: {
    compilers: [
      {
        version: "0.8.14",
        settings: { optimizer: { enabled: true, runs: 20000 } },
      },
      {
        version: "0.4.18",
        settings: { optimizer: { enabled: true, runs: 999 } },
      },
    ],
  },
  zksolc: {
    version: "1.3.5",
    compilerSource: "binary",
    settings: {},
  },
  paths: {
    sources: "./contracts/",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  abiExporter: {
    path: "./abis",
    runOnCompile: true,
    clear: true,
    flat: true,
    pretty: false,
    except: ["test*"],
  },
  gasReporter: {
    enabled: !!process.env.REPORT_GAS,
    excludeContracts: ["test*"],
  },
};

export default config;
