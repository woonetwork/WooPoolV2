// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let wscvContractName = "WooSuperChargerVaultV2";
// eslint-disable-next-line prefer-const
let wlmContractName = "WooLendingManager";
// eslint-disable-next-line prefer-const
let wwmContractName = "WooWithdrawManagerV2";

// Specify need before deploying contract
const weth = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const eth = "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619";
const usdc = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";

const wethReserveVault = "0xD5BEfE3Fecdf1C941c58119a4e395806Eea0C343";
const ethReserveVault = "0x99Ad6e3c00DFBcd80b7593B1Cd8Fb8a9F1a2d230";
const usdcReserveVault = "0xB54e1d90d845d888d39dcaCBd54a3EEc0d8853B2";

const want = weth;
const reserveVault = wethReserveVault;

const wooAccessManager = "0x925AFA2318825FCAC673Ef4eF551208b125dd965";
const wooPP = "0x7081A38158BD050Ae4a86e38E0225Bc281887d7E";
const treasury = "0xBD9D33926Da514586201995cf20FEc9f21133166";

const testBorrower = "0xea02DCC6fe3eC1F2a433fF8718677556a3bb3618";
const prodBorrower = "0x4c298512e78C1FA8fc36c8f9c0a8B9522e5fB48c";
const owner = testBorrower;

async function main() {
  // Deploy WooSuperChargerVault
  const wscvArgs = [weth, want, wooAccessManager];
  const wscvFactory = await ethers.getContractFactory(wscvContractName);
  const wscvContract = await wscvFactory.deploy(...wscvArgs);
  await wscvContract.deployed();
  console.log(`${wscvContractName} deployed to: ${wscvContract.address}`);

  // Deploy WooLendingManager
  await new Promise((resolve) => setTimeout(resolve, 10000));
  const wlmFactory = await ethers.getContractFactory(wlmContractName);
  const wlmContract = await wlmFactory.deploy();
  await wlmContract.deployed();
  console.log(`${wlmContractName} deployed to: ${wlmContract.address}`);

  // Deploy WooWithdrawManager
  await new Promise((resolve) => setTimeout(resolve, 10000));
  const wwmFactory = await ethers.getContractFactory(wwmContractName);
  const wwmContract = await wwmFactory.deploy();
  await wwmContract.deployed();
  console.log(`${wwmContractName} deployed to: ${wwmContract.address}`);

  // WooLendingManager init
  await new Promise((resolve) => setTimeout(resolve, 10000));
  await wlmContract.init(weth, want, wooAccessManager, wooPP, wscvContract.address);
  console.log(`${wlmContractName} inited`);

  // Set test borrower
  await new Promise((resolve) => setTimeout(resolve, 10000));
  await wlmContract.setBorrower(testBorrower, true);
  console.log(`${wlmContractName} set test borrower`);

  // Set prod borrower
  await new Promise((resolve) => setTimeout(resolve, 10000));
  await wlmContract.setBorrower(prodBorrower, true);
  console.log(`${wlmContractName} set prod borrower`);

  // WooWithdrawManager init
  await new Promise((resolve) => setTimeout(resolve, 10000));
  await wwmContract.init(weth, want, wooAccessManager, wscvContract.address);
  console.log(`${wwmContractName} inited`);

  // WooSuperChargerVault init
  await new Promise((resolve) => setTimeout(resolve, 10000));
  await wscvContract.init(reserveVault, wlmContract.address, wwmContract.address)
  console.log(`${wscvContractName} inited`);

  // WooSuperChargerVault set treasury
  await new Promise((resolve) => setTimeout(resolve, 10000));
  await wscvContract.setTreasury(treasury);
  console.log(`${wscvContractName} set treasury`);

  // WooLendingManager set treasury
  await new Promise((resolve) => setTimeout(resolve, 10000));
  await wlmContract.setTreasury(treasury);
  console.log(`${wlmContractName} set treasury`);

  // WooSuperChargerVault transferOwnership
  await new Promise((resolve) => setTimeout(resolve, 10000));
  await wscvContract.transferOwnership(owner);
  console.log(`${wscvContractName} transferOwnership`);

  // WooLendingManager transferOwnership
  await new Promise((resolve) => setTimeout(resolve, 10000));
  await wlmContract.transferOwnership(owner);
  console.log(`${wlmContractName} transferOwnership`);

  // await wscvContract.setMasterChef(masterChef, pid); // Set MasterChef and pid manually

  // Verify contracts
  await new Promise((resolve) => setTimeout(resolve, 10000));
  try {
    await run("verify:verify", {
      address: wscvContract.address,
      constructorArguments: wscvArgs,
    });
  } catch (e) {
    if (typeof e === "string") {
      console.log(e.toUpperCase()); // works, `e` narrowed to string
    } else if (e instanceof Error) {
      console.log(e.message); // works, `e` narrowed to Error
    }
  }

  await new Promise((resolve) => setTimeout(resolve, 10000));
  try {
    await run("verify:verify", {
      address: wlmContract.address,
      constructorArguments: [],
    });
  } catch (e) {
    if (typeof e === "string") {
      console.log(e.toUpperCase()); // works, `e` narrowed to string
    } else if (e instanceof Error) {
      console.log(e.message); // works, `e` narrowed to Error
    }
  }

  await new Promise((resolve) => setTimeout(resolve, 10000));
  try {
    await run("verify:verify", {
      address: wwmContract.address,
      constructorArguments: [],
    });
  } catch (e) {
    if (typeof e === "string") {
      console.log(e.toUpperCase()); // works, `e` narrowed to string
    } else if (e instanceof Error) {
      console.log(e.message); // works, `e` narrowed to Error
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
