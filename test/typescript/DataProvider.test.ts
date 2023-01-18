import { ethers } from "hardhat";
import { expect, use } from "chai";
import { deployContract, deployMockContract, solidity } from "ethereum-waffle";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Contract } from "ethers";
import { DataProvider } from "../../typechain";

import DataProviderArtifact from "../../artifacts/contracts/earn/DataProvider.sol/DataProvider.json";
import WOOFiVaultV2Artifact from "../../artifacts/contracts/earn/VaultV2.sol/WOOFiVaultV2.json";
import IERC20Artifact from "../../artifacts/@openzeppelin/contracts/token/ERC20/IERC20.sol/IERC20.json";
import IMasterChefWooInfoArtifact from "../../artifacts/contracts/interfaces/IDataProvider.sol/IMasterChefWooInfo.json";
import ISuperChargerVaultInfoArtifact from "../../artifacts/contracts/interfaces/IDataProvider.sol/ISuperChargerVaultInfo.json";
import IWithdrawManagerInfoArtifact from "../../artifacts/contracts/interfaces/IDataProvider.sol/IWithdrawManagerInfo.json";


use(solidity);

const mockPid0UserInfo = [10000, 20000];
const mockPid1UserInfo = [30000, 40000];
const mockPid0PendingXWoo = [50000, 60000];
const mockPid1PendingXWoo = [70000, 80000];

const mockRequestedWithdrawAmounts = [1000, 2000]; // [BTC, ETH]
const mockWithdrawAmounts = [10000, 20000]; // [BTC, ETH]

describe("DataProvider.sol", () => {
  let owner: SignerWithAddress;
  let user: SignerWithAddress;
  let dataProvider: DataProvider;
  let masterChefWoo: Contract;
  let btcSuperChargerVault: Contract;
  let btcWithdrawManager: Contract;
  let ethSuperChargerVault: Contract;
  let ethWithdrawManager: Contract;
  let vaults: Contract[] = [];
  let vaultAddresses: string[] = [];
  let tokenAddresses: string[] = [];

  before(async () => {
    [owner, user] = await ethers.getSigners();
    console.log(user.address);
    console.log((await user.getBalance()).toString());

    // Deploy DataProvider Contract
    dataProvider = (await deployContract(owner, DataProviderArtifact, [])) as DataProvider;

    // Deploy MasterChefWoo
    masterChefWoo = await deployMockContract(owner, IMasterChefWooInfoArtifact.abi);
    await masterChefWoo.mock.userInfo.withArgs(0, user.address).returns(...mockPid0UserInfo);
    await masterChefWoo.mock.userInfo.withArgs(1, user.address).returns(...mockPid1UserInfo);
    await masterChefWoo.mock.pendingXWoo.withArgs(0, user.address).returns(...mockPid0PendingXWoo);
    await masterChefWoo.mock.pendingXWoo.withArgs(1, user.address).returns(...mockPid1PendingXWoo);

    // Deploy WooSuperChargerVault & WooWithdrawManager
    btcSuperChargerVault = await deployMockContract(owner, ISuperChargerVaultInfoArtifact.abi);
    btcWithdrawManager = await deployMockContract(owner, IWithdrawManagerInfoArtifact.abi);
    await btcSuperChargerVault.mock.requestedWithdrawAmount.withArgs(user.address).returns(mockRequestedWithdrawAmounts[0]);
    await btcWithdrawManager.mock.withdrawAmount.withArgs(user.address).returns(mockWithdrawAmounts[0]);

    ethSuperChargerVault = await deployMockContract(owner, ISuperChargerVaultInfoArtifact.abi);
    ethWithdrawManager = await deployMockContract(owner, IWithdrawManagerInfoArtifact.abi);
    await ethSuperChargerVault.mock.requestedWithdrawAmount.withArgs(user.address).returns(mockRequestedWithdrawAmounts[1]);
    await ethWithdrawManager.mock.withdrawAmount.withArgs(user.address).returns(mockWithdrawAmounts[1]);

    // Deploy Vault Contract
    let deployVaultCount = 20;
    for (let i = 0; i < deployVaultCount; i++) {
      let vault = await deployMockContract(owner, WOOFiVaultV2Artifact.abi);
      await vault.mock.balanceOf.returns(i);
      await vault.mock.getPricePerFullShare.returns(i);
      await vault.mock.costSharePrice.returns(i);
      vaults.push(vault);
      vaultAddresses.push(vault.address);

      let token = await deployMockContract(owner, IERC20Artifact.abi);
      await token.mock.balanceOf.returns(i);
      tokenAddresses.push(token.address);
    }
  })

  it("Check costSharePrice", async () => {
    let iterationGet: Number[] = [];
    for (let i = 0; i < vaults.length; i++) {
      let cost = await vaults[i].costSharePrice(user.address);
      iterationGet.push(cost.toNumber());
    }
    console.log(iterationGet);

    let bnCosts = await dataProvider.costSharePrices(user.address, vaultAddresses);
    let batchGet: Number[] = [];
    for (let i = 0; i < bnCosts.length; i++) {
      batchGet.push(bnCosts[i].toNumber());
    }
    console.log(batchGet);
  })

  it("Get vaultInfos only", async () => {
    let results = await dataProvider.infos(user.address, masterChefWoo.address, vaultAddresses, [], [], [], []);

    for (let key in results.vaultInfos) {
      let batchGet: Number[] = [];
      console.log(key);
      for (let i = 0; i < results.vaultInfos[key].length; i++) {
        let value = results.vaultInfos[key][i].toNumber();
        batchGet.push(value);
      }
      console.log(batchGet);
    }

    console.log(results.tokenInfos);
  })

  it("Get tokenInfos only", async () => {
    let results = await dataProvider.infos(user.address, masterChefWoo.address, [], tokenAddresses, [], [], []);

    for (let key in results.tokenInfos) {
      if (key == "nativeBalance") {
        console.log(results.tokenInfos.nativeBalance.toString());
        continue;
      }

      let batchGet: Number[] = [];
      console.log(key);
      for (let i = 0; i < results.tokenInfos.balancesOf.length; i++) {
        let value = results.tokenInfos.balancesOf[i].toNumber();
        batchGet.push(value);
      }
      console.log(batchGet);
    }

    console.log(results.vaultInfos);
  })

  it("Get whole infos", async () => {
    let results = await dataProvider.infos(
      user.address,
      masterChefWoo.address,
      vaultAddresses,
      tokenAddresses,
      [btcSuperChargerVault.address, ethSuperChargerVault.address],
      [btcWithdrawManager.address, ethWithdrawManager.address],
      [0, 1]
    );

    for (let key in results.vaultInfos) {
      let batchGet: Number[] = [];
      console.log(key);
      for (let i = 0; i < results.vaultInfos[key].length; i++) {
        let value = results.vaultInfos[key][i].toNumber();
        batchGet.push(value);
      }
      console.log(batchGet);
    }

    for (let key in results.tokenInfos) {
      if (key == "nativeBalance") {
        console.log(results.tokenInfos.nativeBalance.toString());
        continue;
      }

      let batchGet: Number[] = [];
      console.log(key);
      for (let i = 0; i < results.tokenInfos.balancesOf.length; i++) {
        let value = results.tokenInfos.balancesOf[i].toNumber();
        batchGet.push(value);
      }
      console.log(batchGet);
    }

    let amounts = results.masterChefWooInfos.amounts;
    let rewardDebts = results.masterChefWooInfos.rewardDebts;
    expect(amounts[0]).to.eq(mockPid0UserInfo[0]);
    expect(rewardDebts[0]).to.eq(mockPid0UserInfo[1]);

    expect(amounts[1]).to.eq(mockPid1UserInfo[0]);
    expect(rewardDebts[1]).to.eq(mockPid1UserInfo[1]);

    let pendingXWooAmounts = results.masterChefWooInfos.pendingXWooAmounts;
    let pendingWooAmounts = results.masterChefWooInfos.pendingWooAmounts;
    expect(pendingXWooAmounts[0]).to.eq(mockPid0PendingXWoo[0]);
    expect(pendingWooAmounts[0]).to.eq(mockPid0PendingXWoo[1]);

    expect(pendingXWooAmounts[1]).to.eq(mockPid1PendingXWoo[0]);
    expect(pendingWooAmounts[1]).to.eq(mockPid1PendingXWoo[1]);

    let requestedWithdrawAmounts = results.superChargerRelatedInfos.requestedWithdrawAmounts;
    let withdrawAmounts = results.superChargerRelatedInfos.withdrawAmounts;

    for (let i = 0; i < requestedWithdrawAmounts.length; i++) {
      expect(requestedWithdrawAmounts[i]).to.eq(mockRequestedWithdrawAmounts[i]);
    }

    for (let i = 0; i < withdrawAmounts.length; i++) {
      expect(withdrawAmounts[i]).to.eq(mockWithdrawAmounts[i]);
    }
  })
})
