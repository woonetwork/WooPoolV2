// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooCrossChainRouter";

// Specify need before deploying contract
const weth = "0x4200000000000000000000000000000000000006";
const wooRouter = "0xEAf1Ac8E89EA0aE13E0f03634A4FF23502527024";
const stargateRouter = "0xB0D502E938ed5f4df2E681fE6E419ff29631d62b";
const owner = "0x7C8A5d20b22Ce9b369C043A3E0091b5575B732d9";

const sgChainIdMapping: {[key: number]: string} = {
  102: "0x53E255e8Bbf4EDF16797f9885291B3Ca0C70B59f",
  106: "0xdF37F7A85D4563f39A78494568824b4dF8669B7a",
  109: "0x376d567C5794cfc64C74852A9DB2105E0b5B482C",
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

