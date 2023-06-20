// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooRouterV3";

const weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
const wooPP = "0x26F33EA1e476Ad8a016834107f9889B6c31c14f5";

async function main() {
  const args = [weth, wooPP];
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.deployed();
  
  console.log(`${contractName} deployed to: ${contract.address}`);
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
