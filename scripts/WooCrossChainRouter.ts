// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooCrossChainRouter";

// Specify need before deploying contract
const weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
const wooPool = "0x86b1742A1D7c963D3E8985829D722725316aBF0A";
const stargateRouter = "0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614";
const owner = "0x7C8A5d20b22Ce9b369C043A3E0091b5575B732d9";

const sgChainIdMapping: {[key: number]: string} = {
  102: "0x53E255e8Bbf4EDF16797f9885291B3Ca0C70B59f",
  106: "0xdF37F7A85D4563f39A78494568824b4dF8669B7a",
  109: "0x376d567C5794cfc64C74852A9DB2105E0b5B482C",
  112: "0xcF6Ce5Fd6bf28bB1AeAc88A55251f6c840059De5",
}

async function main() {
  const args = [weth, wooPool, stargateRouter];
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

