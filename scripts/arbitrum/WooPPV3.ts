// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooPPV3";

const wooracle = "0x73504eaCB100c7576146618DC306c97454CB3620";
const feeAddr = "0x97471c0fDDdb5E5Cc34cb08CB17961Bd3a53F38f";
const usdOFT = "0x2500AD59b46fF4B96f8e1EaC3fE1f78eAF955777";

async function main() {
  const args = [wooracle, feeAddr, usdOFT];
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
