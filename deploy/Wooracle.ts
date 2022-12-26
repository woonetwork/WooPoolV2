import { Wallet, utils } from "zksync-web3";
import * as ethers from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";

const contractName = "WooracleV2";

export default async function (hre: HardhatRuntimeEnvironment) {
  const privateKey = process.env.PRIVATE_KEY !== undefined ? process.env.PRIVATE_KEY : "";
  const wallet = new Wallet(privateKey);

  const deployer = new Deployer(hre, wallet);
  const artifact = await deployer.loadArtifact(contractName);

  const deploymentFee = await deployer.estimateDeployFee(artifact, []);
  const parsedFee = ethers.utils.formatEther(deploymentFee.toString());
  console.log(`${artifact.contractName} deployment is estimated to cost ${parsedFee} ETH`);

  const contract = await deployer.deploy(artifact, []);
  console.log("constructor args:" + contract.interface.encodeDeploy([]));
  console.log(`${artifact.contractName} was deployed to ${contract.address}`);
}
