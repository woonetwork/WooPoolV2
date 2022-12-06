// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooFeeManager";

// Specify need before deploying contract
const quoteToken = "0x7F5c764cBc14f9669B88837ca1490cCa17c31607";
const wooRebateManager = "0x36b680fB76Dad86bcB2Cefc83fAE05e3Fe147706";
const wooVaultManager = "0x31d37b4Ec170D89376E614266b6E229342c1029e";
const wooAccessManager = "0x8A68849c8a61225964d2caE170fDD19eC46bf246";
const treasury = "0xf0a9E1e6c85E99bc29A68eB9D750Dd7389feb886";
const owner = "0x7C8A5d20b22Ce9b369C043A3E0091b5575B732d9";

async function main() {
  const args = [quoteToken, wooRebateManager, wooVaultManager, wooAccessManager, treasury]
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.deployed();
  console.log(`${contractName} deployed to: ${contract.address}`);

  await new Promise((resolve) => setTimeout(resolve, 10000));
  await contract.transferOwnership(owner);
  
  try {
    await run("verify:verify", {
      address: contract.address,
      constructorArguments: args,
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
