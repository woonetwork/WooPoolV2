// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooPPV3";

// Specify need before deploying contract
const wooracle = "0x31aE608cBadD1214D6A3d5dcf49E45Fb18E2a48E";
const feeAddr = "0x938021351425dbfa606Ed2B81Fc66952283e0Dd5";
const usdOFT = "0x3784A47D47593542903E3A319332e4719B8F95Da";
const wooPPV2 = "0x7081A38158BD050Ae4a86e38E0225Bc281887d7E";

// const admin = "0xDe95557D3c243e116E40dD8e933c4c7A3939d515";
const owner = "0x97471c0fDDdb5E5Cc34cb08CB17961Bd3a53F38f";
const baseFeeRate = 25;
const baseTokens = [
  "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270", // WMATIC
  "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619", // WETH
  "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6", // WBTC
  "0x1B815d120B3eF02039Ee11dC2d33DE7aA4a8C603", // WOO
];

async function main() {


  const args = [
    wooracle,
    feeAddr,
    usdOFT,
    wooPPV2
  ];
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.deployed();
  console.log(`${contractName} deployed to: ${contract.address}`);

  // await new Promise((resolve) => setTimeout(resolve, 10000));
  // await contract.init(wooracle, feeAddr); // Set wooracle and feeAddr


  // await new Promise((resolve) => setTimeout(resolve, 10000));
  // await contract.setAdmin(admin, true);

  // eslint-disable-next-line prefer-const
  for (let i in baseTokens) {
    await contract.setFeeRate(baseTokens[i], baseFeeRate);
    await new Promise((resolve) => setTimeout(resolve, 10000));
  }

  // await contract.transferOwnership(owner);
  
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
