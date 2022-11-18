// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooracleV2";

const owner = "0x7C8A5d20b22Ce9b369C043A3E0091b5575B732d9";

async function main() {
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy();
  await contract.deployed();
  console.log(`${contractName} deployed to: ${contract.address}`);

  await new Promise((resolve) => setTimeout(resolve, 10000));

  await contract.transferOwnership(owner);

  try {
    await run("verify:verify", {
      address: contract.address,
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
