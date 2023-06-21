// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooPPV3";

// fantom wooracle address
const wooracle = "0x8840e26e0ebf7D100A0644DD8576DC62B03cbf04";

// owner address
const feeAddr = "0xA113d3B08df49D442fA1c0b47A82Ad95aD19c0Fb";

// fantom WooUsdOFT address
const usdOFT = "0xb2D005d449B98f977F2707dE355cc0F236456C4B";

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
