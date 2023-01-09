// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooRebateManager";

// Specify need before deploying contract
const quoteToken = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const rewardToken = quoteToken;
const wooAccessManager = "0x925AFA2318825FCAC673Ef4eF551208b125dd965";
const testRebateBroker = "0xea02DCC6fe3eC1F2a433fF8718677556a3bb3618";
const testRebateRate = ethers.utils.parseEther("0.2");
const owner = "0x7C8A5d20b22Ce9b369C043A3E0091b5575B732d9";

async function main() {
  const args = [quoteToken, rewardToken, wooAccessManager]
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.deployed();
  console.log(`${contractName} deployed to: ${contract.address}`);

  await new Promise((resolve) => setTimeout(resolve, 10000));
  await contract.setRebateRate(testRebateBroker, testRebateRate);

  // await contract.setWooRouter(wooRouterV2); // Set WooRouterV2 manually

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
