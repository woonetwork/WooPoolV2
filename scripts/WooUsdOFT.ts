// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooUsdOFT";

// Specify need before deploying contract
const name = "WooUSD";
const symbol = "WooUSD";
// DOC: https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids
// Polygon network
const lzEndpoint = "0x3c2269811836af69497E5F486A85D7316753cf62";
const wooPPAddr = "";
const owner = "";

async function main() {
  const args = [
    name,
    symbol,
    lzEndpoint,
  ];
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.deployed();
  console.log(`${contractName} deployed to: ${contract.address}`);

//   await new Promise((resolve) => setTimeout(resolve, 10000));
//   await contract.setWooPP(wooPPAddr); // Set wooPP Address

//   await contract.transferOwnership(owner);
  
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
