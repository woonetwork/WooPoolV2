// eslint-disable-next-line node/no-unpublished-import
import { ethers, run } from "hardhat";

// eslint-disable-next-line prefer-const
let contractName = "WooracleV2";

const quoteToken = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const owner = "0x7C8A5d20b22Ce9b369C043A3E0091b5575B732d9";
const tokenToCLOracle: {[key: string]: string} = {
  "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270": "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0", // WMATIC
  "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619": "0xF9680D99D6C9589e2a93a78A04A279e509205945", // WETH
  "0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6": "0xDE31F8bFBD8c84b5360CFACCa3539B938dd78ae6", // WBTC
  "0x1B815d120B3eF02039Ee11dC2d33DE7aA4a8C603": "0x6a99EC84819FB7007dd5D032068742604E755c56", // WOO
  "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174": "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7", // USDC
};

async function main() {
  const factory = await ethers.getContractFactory(contractName);
  const contract = await factory.deploy();
  await contract.deployed();
  console.log(`${contractName} deployed to: ${contract.address}`);

  await new Promise((resolve) => setTimeout(resolve, 10000));
  await contract.setQuoteToken(quoteToken, tokenToCLOracle[quoteToken]);
  
  await new Promise((resolve) => setTimeout(resolve, 10000));

  for (let token in tokenToCLOracle) {
    await contract.setCLOracle(token, tokenToCLOracle[token], true);
    await new Promise((resolve) => setTimeout(resolve, 10000));
  }

  // await contract.setAdmin(wooPPV2, true); // Set WooPPV2 as admin manually

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
