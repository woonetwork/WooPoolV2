// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let wscvContractName = "WooSuperChargerVault";
// eslint-disable-next-line prefer-const
let wlmContractName = "WooLendingManager";
// eslint-disable-next-line prefer-const
let wwmContractName = "WooWithdrawManager";

// Specify need before deploying contract
const weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
const usdc = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
const wethReserveVault = "0x478E7F3FE49931C601e2399DdaEE8EEf2eEF6F13";
const usdcReserveVault = "0xD3d86C94a8D468Bd1328e6491ED8aCa58D850AE7";

const masterChefWoo = "0xc0f8C29e3a9A7650a3F642e467d70087819926d6";
const weWETHPid = 2;
const weUSDCPid = 3;

const want = usdc;
const reserveVault = usdcReserveVault;

const wooAccessManager = "0xd14a997308F9e7514a8FEA835064D596CDCaa99E";
const wooPP = "0x1f79f8A65E02f8A137ce7F79C038Cc44332dF448";
const treasury = "0xD8Cbd7e0693AF1022D1c080aBEA53F0c4C62e6C5";

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
