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
    bsc: {
      url: "https://rpc.ankr.com/bsc",
      accounts: accounts,
    },
    bscTestnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      accounts: accounts,
    },
    avalanche: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      accounts: accounts,
    },
    avalancheFuji: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: accounts,
    },
    fantom: {
      url: "https://rpc.ftm.tools",
      accounts: accounts,
    },
    fantomTestnet: {
      url: "https://rpc.testnet.fantom.network",
      accounts: accounts,
    },
    polygon: {
      url: "https://polygon-rpc.com",
      accounts: accounts,
    },
    polygonMumbai: {
      url: "https://matic-mumbai.chainstacklabs.com",
      accounts: accounts,
    },
    arbitrum: {
      url: "https://arb1.arbitrum.io/rpc",
      accounts: accounts,
    },
    arbitrumGoerli: {
      url: "https://goerli-rollup.arbitrum.io/rpc",
      accounts: accounts,
    },
    optimism: {
      url: "https://rpc.ankr.com/optimism",
      accounts: accounts,
    },
    optimismGoerli: {
      url: "https://goerli.optimism.io",
      accounts: accounts,
    },
    mainnet: {
      url: "https://rpc.ankr.com/eth",
      accounts: accounts,
    },
    goerli: { 
      url: "https://rpc.ankr.com/eth_goerli",
      accounts: accounts,
    },
    zkSync: {
      url: "https://mainnet.era.zksync.io",
      ethNetwork: "mainnet",
      zksync: true,
      verifyURL: "https://zksync2-mainnet-explorer.zksync.io/contract_verification",
    },
    zkSyncGoerli: {
      url: "https://zksync2-testnet.zksync.dev",
      ethNetwork: "goerli",
      zksync: true,
      verifyURL: "https://zksync2-testnet-explorer.zksync.dev/contract_verification",
    },
    polygonZkEVM: {
      url: "https://zkevm-rpc.com/",
      accounts: accounts,
    },
    polygonZkEVMTestnet: {
      url: "https://rpc.public.zkevm-test.net",
      accounts: accounts,
    },
    linea: {
      url: "https://rpc.linea.build",
      accounts: accounts,
    },
    base: {
      url: "https://mainnet.base.org",
      accounts: accounts,
    },
    baseGoerli: {
      url: "https://goerli.base.org",
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
      arbitrumGoerli: process.env.ARBISCAN_KEY !== undefined ? process.env.ARBISCAN_KEY : "",
      // optimism
      optimisticEthereum: process.env.OPTIMISTIC_ETHERSCAN_KEY !== undefined ? process.env.OPTIMISTIC_ETHERSCAN_KEY : "",
      optimisticGoerli: process.env.OPTIMISTIC_ETHERSCAN_KEY !== undefined ? process.env.OPTIMISTIC_ETHERSCAN_KEY : "",
      polygon_zkevm_mainnet: process.env.ZKEVM_POLYGONSCAN_KEY !== undefined ? process.env.ZKEVM_POLYGONSCAN_KEY : "",
      polygon_zkevm_testnet: process.env.ZKEVM_POLYGONSCAN_KEY !== undefined ? process.env.ZKEVM_POLYGONSCAN_KEY : "",
      linea: process.env.LINEA_KEY !== undefined ? process.env.LINEA_KEY : "",
      base: process.env.BASESCAN_KEY !== undefined ? process.env.BASESCAN_KEY : "",
      baseGoerli: process.env.BASESCAN_KEY !== undefined ? process.env.BASESCAN_KEY : "",
      goerli: process.env.ETHERSCAN_KEY !== undefined ? process.env.ETHERSCAN_KEY : "",
    },
    customChains: [
      {
        network: "arbitrumGoerli",
        chainId: 421613,
        urls: {
          apiURL: "https://api-goerli.arbiscan.io/api",
          browserURL: "https://goerli.arbiscan.io",
        }
      },
      {
        network: "polygonZkEVM",
        chainId: 1101,
        urls: {
          apiURL: "https://api-zkevm.polygonscan.com/api",
          browserURL: "https://zkevm.polygonscan.com",
        }
      },
      {
        network: "polygonZkEVMTestnet",
        chainId: 1442,
        urls: {
          apiURL: "https://api-testnet-zkevm.polygonscan.com/api",
          browserURL: "https://testnet-zkevm.polygonscan.com",
        }
      },
      {
        network: "linea",
        chainId: 59144,
        urls: {
          apiURL: "https://api.lineascan.build/api",
          browserURL: "https://lineascan.build",
        }
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org",
        },
      },
      {
        network: "baseGoerli",
        chainId: 84531,
        urls: {
          apiURL: "https://api-goerli.basescan.org/api",
          browserURL: "https://goerli.basescan.org",
        },
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
