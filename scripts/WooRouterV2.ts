// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooRouterV2";

// Specify need before deploying contract
const weth = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const pool = "0x7081A38158BD050Ae4a86e38E0225Bc281887d7E";
const owner = "0x7C8A5d20b22Ce9b369C043A3E0091b5575B732d9";

async function main() {
  const args = [weth, pool];
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.deployed();
  console.log(`${contractName} deployed to: ${contract.address}`);

  // await contract.setWhitelisted(target, true); // Set whitelisted to support externalSwap manually

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
