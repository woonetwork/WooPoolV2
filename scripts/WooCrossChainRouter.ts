// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooCrossChainRouter";

// Specify need before deploying contract
const weth = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
const wooRouter = "0x817Eb46D60762442Da3D931Ff51a30334CA39B74";
const stargateRouter = "0x45A01E4e04F14f7A4a6702c74187c5F6222033cd";
const owner = "0x7C8A5d20b22Ce9b369C043A3E0091b5575B732d9";

const sgChainIdMapping: {[key: number]: string} = {
  102: "0x53E255e8Bbf4EDF16797f9885291B3Ca0C70B59f",
  106: "0xdF37F7A85D4563f39A78494568824b4dF8669B7a",
  // 109: "0x376d567C5794cfc64C74852A9DB2105E0b5B482C", // Don't set the local chain that you're deploying
  112: "0xcF6Ce5Fd6bf28bB1AeAc88A55251f6c840059De5",
  110: "0x44dF096D2600C6a6db77899dB3DE3AeCff746cb8",
  111: "0x655e2FE03fe19327239b5294a556965192386a7b",
}

async function main() {
  const args = [weth, wooRouter, stargateRouter];
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.deployed();
  console.log(`${contractName} deployed to: ${contract.address}`);

  await new Promise((resolve) => setTimeout(resolve, 10000));
  // eslint-disable-next-line prefer-const
  for (let chainId in sgChainIdMapping) {
    await contract.setWooCrossChainRouter(chainId, sgChainIdMapping[chainId]);
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

