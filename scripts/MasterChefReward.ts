// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "MasterChefReward";

// Specify need before deploying contract
const reward = "0x1B815d120B3eF02039Ee11dC2d33DE7aA4a8C603"; // Any ERC20 token
const rewardPerBlock = 10000000000000;

const ownerAddress = "0x7C8A5d20b22Ce9b369C043A3E0091b5575B732d9";

async function main() {
  const args = [reward, rewardPerBlock];
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.deployed();
  console.log(`${contractName} deployed to: ${contract.address}`);

  // await contract.add(1000, weToken, '0x0000000000000000000000000000000000000000'); // Add pool for each weToken manually

  await new Promise((resolve) => setTimeout(resolve, 10000));
  await contract.transferOwnership(ownerAddress);
  await new Promise((resolve) => setTimeout(resolve, 10000));
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
