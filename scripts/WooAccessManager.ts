// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooAccessManager";

// Specify need before deploying contract
const buybackAdmin = "0xb08Dc5670682658A77841Db446B226dd355527f2";
const settleAdmin = "0x3668ba88A32332269483a0EB2406A7f8149b486D";
const marketMaker = "0x4c298512e78C1FA8fc36c8f9c0a8B9522e5fB48c";
const owner = "0x7C8A5d20b22Ce9b369C043A3E0091b5575B732d9";

async function main() {
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy();
  await contract.deployed();
  console.log(`${contractName} deployed to: ${contract.address}`);

  await new Promise((resolve) => setTimeout(resolve, 10000));
  await contract.setFeeAdmin(buybackAdmin, true);

  await new Promise((resolve) => setTimeout(resolve, 10000));
  await contract.setVaultAdmin(buybackAdmin, true);

  await new Promise((resolve) => setTimeout(resolve, 10000));
  await contract.setVaultAdmin(settleAdmin, true);

  await new Promise((resolve) => setTimeout(resolve, 10000));
  await contract.setVaultAdmin(marketMaker, true);

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
