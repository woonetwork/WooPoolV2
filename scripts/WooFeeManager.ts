// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooFeeManager";

// Specify need before deploying contract
const quoteToken = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const wooRebateManager = "0x913E116cD0E279763B0419798c0bA18F9311B390";
const wooVaultManager = "0x88748243DE01c4F3C103F2De2833f39F6807db17";
const wooAccessManager = "0x925AFA2318825FCAC673Ef4eF551208b125dd965";
const treasury = "0xBD9D33926Da514586201995cf20FEc9f21133166";
const vaultRewardRate = ethers.utils.parseEther("0.8");
const owner = "0x7C8A5d20b22Ce9b369C043A3E0091b5575B732d9";

async function main() {
  const args = [quoteToken, wooRebateManager, wooVaultManager, wooAccessManager, treasury]
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.deployed();
  console.log(`${contractName} deployed to: ${contract.address}`);

  await new Promise((resolve) => setTimeout(resolve, 10000));
  await contract.setVaultRewardRate(vaultRewardRate);

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
