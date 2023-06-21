// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooUsdOFT";

const owner = "0xea02DCC6fe3eC1F2a433fF8718677556a3bb3618";

const name = "VUSD";
const symbol = "vusd";
const sharedDecimals = 6;
// Doc: https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids
const lzEndpoint = "0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7";

async function main() {
  const args = [name, symbol, sharedDecimals, lzEndpoint];
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.deployed();
  
  console.log(`${contractName} deployed to: ${contract.address}`);
  await new Promise((resolve) => setTimeout(resolve, 10000));

  // await contract.transferOwnership(owner);
  // await new Promise((resolve) => setTimeout(resolve, 10000));
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
