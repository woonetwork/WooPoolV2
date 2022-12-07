// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let wscvContractName = "WooSuperChargerVault";
// eslint-disable-next-line prefer-const
let wlmContractName = "WooLendingManager";
// eslint-disable-next-line prefer-const
let wwmContractName = "WooWithdrawManager";

// Specify need before deploying contract
const weth = "0x4200000000000000000000000000000000000006";
const usdc = "0x7F5c764cBc14f9669B88837ca1490cCa17c31607";
const op = "0x4200000000000000000000000000000000000042";
const wethReserveVault = "0x7e1996945eA8866DE873179DC1677E93A4380107";
const usdcReserveVault = "0x64EDb6450F5a1C6158D76C1E30900fD7D8493636";
const opReserveVault = "0xCEC7E58CF02749b2592Bb3C0c392737Eec3f9636";

const masterChefWoo = "0xc0f8C29e3a9A7650a3F642e467d70087819926d6";
const weWETHPid = 0;
const weUSDCPid = 1;

const want = weth;
const reserveVault = wethReserveVault;

const wooAccessManager = "0x8A68849c8a61225964d2caE170fDD19eC46bf246";
const wooPP = "0xd1778F9DF3eee5473A9640f13682e3846f61fEbC";
const treasury = "0xf0a9E1e6c85E99bc29A68eB9D750Dd7389feb886";

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
