// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooPPV2";

// Specify need before deploying contract
const quoteToken = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
const wooracle = "0x37a9dE70b6734dFCA54395D8061d9411D9910739";
const feeAddr = "0x36dbF060dDDEDB1AaeBd9553Cf27dF03A5746603";
const owner = "0x7C8A5d20b22Ce9b369C043A3E0091b5575B732d9";
const baseFeeRate = 25;
const baseTokens = [
  "0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f", // WBTC
  "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1", // WETH
  "0xcAFcD85D8ca7Ad1e1C6F82F651fA15E33AEfD07b", // WOO
];

async function main() {
  const args = [quoteToken];
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.deployed();
  console.log(`${contractName} deployed to: ${contract.address}`);

  await new Promise((resolve) => setTimeout(resolve, 10000));

  await contract.init(wooracle, feeAddr); // Set wooracle and feeAddr
  await new Promise((resolve) => setTimeout(resolve, 10000));

  // eslint-disable-next-line prefer-const
  for (let i in baseTokens) {
    await contract.setFeeRate(baseTokens[i], baseFeeRate);
    await new Promise((resolve) => setTimeout(resolve, 10000));
  }

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
