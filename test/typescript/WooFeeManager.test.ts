/*

░██╗░░░░░░░██╗░█████╗░░█████╗░░░░░░░███████╗██╗
░██║░░██╗░░██║██╔══██╗██╔══██╗░░░░░░██╔════╝██║
░╚██╗████╗██╔╝██║░░██║██║░░██║█████╗█████╗░░██║
░░████╔═████║░██║░░██║██║░░██║╚════╝██╔══╝░░██║
░░╚██╔╝░╚██╔╝░╚█████╔╝╚█████╔╝░░░░░░██║░░░░░██║
░░░╚═╝░░░╚═╝░░░╚════╝░░╚════╝░░░░░░░╚═╝░░░░░╚═╝

*
* MIT License
* ===========
*
* Copyright (c) 2020 WooTrade
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

import { expect, use } from "chai";
import { Contract, utils } from "ethers";
import { ethers } from "hardhat";
import { deployContract, deployMockContract, solidity } from "ethereum-waffle";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import { WooFeeManager, WooRebateManager, WooAccessManager, WooVaultManager } from "../../typechain";
import WooFeeManagerArtifact from "../../artifacts/contracts/WooFeeManager.sol/WooFeeManager.json";
import WooVaultManagerArtifact from "../../artifacts/contracts/WooVaultManager.sol/WooVaultManager.json";
import WooRebateManagerArtifact from "../../artifacts/contracts/WooRebateManager.sol/WooRebateManager.json";
import WooAccessManagerArtifact from "../../artifacts/contracts/WooAccessManager.sol/WooAccessManager.json";
import TestERC20TokenArtifact from "../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json";

use(solidity);

const {
  BigNumber,
  constants: { MaxUint256 },
} = ethers;

const ONE = BigNumber.from(10).pow(18);
const FEE_RATE = utils.parseEther("0.001");
const REBATE_RATE = utils.parseEther("0.1");

describe("WooFeeManager Info", () => {
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let broker1: SignerWithAddress;
  let broker2: SignerWithAddress;
  let treasury: SignerWithAddress;

  let feeManager: WooFeeManager;

  let btcToken: Contract;
  let usdtToken: Contract;
  let wooToken: Contract;

  let rebateManager: Contract;
  let vaultManager: Contract;
  let wooAccessManager: Contract;

  before("Deploy Contracts", async () => {
    [owner, user1, broker1, broker2, treasury] = await ethers.getSigners();
    btcToken = await deployContract(owner, TestERC20TokenArtifact, []);
    usdtToken = await deployContract(owner, TestERC20TokenArtifact, []);
    wooToken = await deployContract(owner, TestERC20TokenArtifact, []);

    rebateManager = await deployMockContract(owner, WooRebateManagerArtifact.abi);
    await rebateManager.mock.rebateRate.returns(REBATE_RATE);
    await rebateManager.mock.addRebate.returns();

    vaultManager = await deployMockContract(owner, WooVaultManagerArtifact.abi);
    wooAccessManager = await deployMockContract(owner, WooFeeManagerArtifact.abi);
  });

  describe("ctor, init & basic func", () => {
    beforeEach("Deploy WooFeeManager", async () => {
      feeManager = (await deployContract(owner, WooFeeManagerArtifact, [
        usdtToken.address,
        rebateManager.address,
        vaultManager.address,
        wooAccessManager.address,
        treasury.address,
      ])) as WooFeeManager;
    });

    it("Owner", async () => {
      expect(await feeManager.owner()).to.eq(owner.address);
    });

    it("Get fee rate", async () => {
      expect(await feeManager.feeRate(btcToken.address)).to.eq(0);
      expect(await feeManager.feeRate(usdtToken.address)).to.eq(0);
    });

    it("Set fee rate", async () => {
      await feeManager.setFeeRate(btcToken.address, FEE_RATE);
      expect(await feeManager.feeRate(btcToken.address)).to.eq(FEE_RATE);
    });

    it("Set fee rate revert", async () => {
      await expect(feeManager.setFeeRate(btcToken.address, ONE)).to.be.revertedWith("WooFeeManager: FEE_RATE>1%");
    });
  });

  describe("withdraw", () => {
    let quoteToken: Contract;

    beforeEach("deploy WooFeeManager", async () => {
      quoteToken = await deployContract(owner, TestERC20TokenArtifact, []);

      feeManager = (await deployContract(owner, WooFeeManagerArtifact, [
        usdtToken.address,
        rebateManager.address,
        vaultManager.address,
        wooAccessManager.address,
        treasury.address,
      ])) as WooFeeManager;

      await quoteToken.mint(feeManager.address, 30000);
      await quoteToken.mint(owner.address, 100);
    });

    it("inCaseTokenGotStuck accuracy1", async () => {
      expect(await quoteToken.balanceOf(owner.address)).to.eq(100);
      expect(await quoteToken.balanceOf(feeManager.address)).to.eq(30000);

      await feeManager.inCaseTokenGotStuck(quoteToken.address);

      expect(await quoteToken.balanceOf(owner.address)).to.eq(30100);
      expect(await quoteToken.balanceOf(feeManager.address)).to.eq(0);
    });
  });

  describe("collectFee & Distribute", () => {
    beforeEach("deploy WooFeeManager", async () => {
      rebateManager = (await deployContract(owner, WooRebateManagerArtifact, [
        usdtToken.address,
        wooToken.address,
        wooAccessManager.address,
      ])) as WooRebateManager;

      vaultManager = (await deployContract(owner, WooVaultManagerArtifact, [
        usdtToken.address,
        wooToken.address,
        wooAccessManager.address,
      ])) as WooVaultManager;

      feeManager = (await deployContract(owner, WooFeeManagerArtifact, [
        usdtToken.address,
        rebateManager.address,
        vaultManager.address,
        wooAccessManager.address,
        treasury.address,
      ])) as WooFeeManager;

      await usdtToken.mint(feeManager.address, 1000);
      await usdtToken.mint(owner.address, 100000);
    });

    it("collectFee accuracy1", async () => {
      const ownerBalance = await usdtToken.balanceOf(owner.address);
      const feeManagerBalance = await usdtToken.balanceOf(feeManager.address);
      const rebateManagerBalance = await usdtToken.balanceOf(rebateManager.address);
      const vaultManagerBalance = await usdtToken.balanceOf(vaultManager.address);
      const brokerBalance = await usdtToken.balanceOf(broker1.address);

      await usdtToken.approve(feeManager.address, 100);
      await feeManager.collectFee(100, broker1.address);

      expect(await usdtToken.balanceOf(owner.address)).to.eq(ownerBalance.sub(100));
      expect(await usdtToken.balanceOf(feeManager.address)).to.eq(feeManagerBalance.add(100));
    });

    it("distribute fee accuracy1", async () => {
      const ownerBalance = await usdtToken.balanceOf(owner.address);
      const feeManagerBalance = await usdtToken.balanceOf(feeManager.address);
      const rebateManagerBalance = await usdtToken.balanceOf(rebateManager.address);
      const vaultManagerBalance = await usdtToken.balanceOf(vaultManager.address);
      const brokerBalance = await usdtToken.balanceOf(broker1.address);

      await usdtToken.approve(feeManager.address, 100);
      await feeManager.collectFee(100, broker1.address);

      expect(await usdtToken.balanceOf(owner.address)).to.eq(ownerBalance.sub(100));
      expect(await usdtToken.balanceOf(feeManager.address)).to.eq(feeManagerBalance.add(100));

      await usdtToken.approve(feeManager.address, 300);
      await feeManager.collectFee(300, broker1.address);

      expect(await usdtToken.balanceOf(owner.address)).to.eq(ownerBalance.sub(400));
      expect(await usdtToken.balanceOf(feeManager.address)).to.eq(feeManagerBalance.add(400));

      await feeManager.distributeFees();

      expect(await usdtToken.balanceOf(vaultManager.address)).to.eq(vaultManagerBalance.add(1400));
      expect(await usdtToken.balanceOf(treasury.address)).to.eq(0);
    });

    it("distribute fee accuracy2", async () => {
      const ownerBalance = await usdtToken.balanceOf(owner.address);
      const feeManagerBalance = await usdtToken.balanceOf(feeManager.address);
      const rebateManagerBalance = await usdtToken.balanceOf(rebateManager.address);
      const vaultManagerBalance = await usdtToken.balanceOf(vaultManager.address);
      const brokerBalance = await usdtToken.balanceOf(broker1.address);

      await usdtToken.approve(feeManager.address, 100);
      await feeManager.collectFee(100, broker1.address);

      expect(await usdtToken.balanceOf(owner.address)).to.eq(ownerBalance.sub(100));
      expect(await usdtToken.balanceOf(feeManager.address)).to.eq(feeManagerBalance.add(100));

      await usdtToken.approve(feeManager.address, 300);
      await feeManager.collectFee(300, broker1.address);

      expect(await usdtToken.balanceOf(owner.address)).to.eq(ownerBalance.sub(400));
      expect(await usdtToken.balanceOf(feeManager.address)).to.eq(feeManagerBalance.add(400));

      await feeManager.setVaultRewardRate(utils.parseEther("0.8"));
      await feeManager.distributeFees();

      expect(await usdtToken.balanceOf(vaultManager.address)).to.eq(vaultManagerBalance.add(1400 * 0.8));
      expect(await usdtToken.balanceOf(treasury.address)).to.eq(1400 * 0.2);
    });

    it("addRebates", async () => {
      // Real WooAccessManager, not mock
      const wam = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager;

      // Real WooRebateManager, not mock
      const wrmArgs = [usdtToken.address, usdtToken.address, wam.address];
      const wrm = (await deployContract(owner, WooRebateManagerArtifact, wrmArgs)) as WooRebateManager;

      // Real WooFeeManager, not mock
      const wfmArgs = [usdtToken.address, wrm.address, vaultManager.address, wam.address, treasury.address];
      const wfm = (await deployContract(owner, WooFeeManagerArtifact, wfmArgs)) as WooFeeManager;

      await wam.setRebateAdmin(wfm.address, true);
      expect(await wam.isRebateAdmin(wfm.address)).to.equal(true);

      expect(await wfm.rebateAmount()).to.equal(0);

      await wfm.connect(owner).addRebates([broker1.address, broker2.address], [100, 100]);

      expect(await wfm.rebateAmount()).to.equal(200);
    });
  });
});

describe("WooFeeManager Access Control", () => {
  let owner: SignerWithAddress;
  let admin: SignerWithAddress;
  let user: SignerWithAddress;
  let treasury: SignerWithAddress;

  let wooFeeManager: WooFeeManager;
  let token: Contract;
  let rebateManager: SignerWithAddress;
  let newRebateManager: SignerWithAddress;
  let vaultManager: SignerWithAddress;
  let newVaultManager: SignerWithAddress;
  let wooAccessManager: WooAccessManager;
  let newWooAccessManager: WooAccessManager;

  let onlyOwnerRevertedMessage: string;
  let onlyAdminRevertedMessage: string;

  const mintToken = BigNumber.from(30000);

  before(async () => {
    [owner, admin, user, rebateManager, newRebateManager, vaultManager, newVaultManager, treasury] =
      await ethers.getSigners();
    token = await deployContract(owner, TestERC20TokenArtifact, []);
    wooAccessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager;
    await wooAccessManager.setFeeAdmin(admin.address, true);
    newWooAccessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager;

    wooFeeManager = (await deployContract(owner, WooFeeManagerArtifact, [
      token.address,
      rebateManager.address,
      vaultManager.address,
      wooAccessManager.address,
      treasury.address,
    ])) as WooFeeManager;

    await token.mint(wooFeeManager.address, mintToken);

    onlyOwnerRevertedMessage = "Ownable: caller is not the owner";
    onlyAdminRevertedMessage = "WooFeeManager: !admin";
  });

  it("Only admin able to setFeeRate", async () => {
    expect(await wooFeeManager.feeRate(token.address)).to.eq(BigNumber.from(0));
    let newFeeRate = ONE.div(BigNumber.from(100));
    expect(await wooAccessManager.isFeeAdmin(user.address)).to.eq(false);
    await expect(wooFeeManager.connect(user).setFeeRate(token.address, newFeeRate)).to.be.revertedWith(
      onlyAdminRevertedMessage
    );
    expect(await wooAccessManager.isFeeAdmin(admin.address)).to.eq(true);
    await wooFeeManager.connect(admin).setFeeRate(token.address, newFeeRate);
    expect(await wooFeeManager.feeRate(token.address)).to.eq(newFeeRate);

    newFeeRate = newFeeRate.div(BigNumber.from(10));
    await wooFeeManager.connect(owner).setFeeRate(token.address, newFeeRate);
    expect(await wooFeeManager.feeRate(token.address)).to.eq(newFeeRate);
  });

  it("Only admin able to setRebateManager", async () => {
    expect(await wooFeeManager.rebateManager()).to.eq(rebateManager.address);
    await expect(wooFeeManager.connect(user).setRebateManager(newRebateManager.address)).to.be.revertedWith(
      onlyAdminRevertedMessage
    );
    await wooFeeManager.connect(admin).setRebateManager(newRebateManager.address);
    expect(await wooFeeManager.rebateManager()).to.eq(newRebateManager.address);

    await wooFeeManager.connect(owner).setRebateManager(rebateManager.address);
    expect(await wooFeeManager.rebateManager()).to.eq(rebateManager.address);
  });

  it("Only admin able to setVaultManager", async () => {
    expect(await wooFeeManager.vaultManager()).to.eq(vaultManager.address);
    await expect(wooFeeManager.connect(user).setVaultManager(newVaultManager.address)).to.be.revertedWith(
      onlyAdminRevertedMessage
    );
    await wooFeeManager.connect(admin).setVaultManager(newVaultManager.address);
    expect(await wooFeeManager.vaultManager()).to.eq(newVaultManager.address);

    await wooFeeManager.connect(owner).setVaultManager(vaultManager.address);
    expect(await wooFeeManager.vaultManager()).to.eq(vaultManager.address);
  });

  it("Only admin able to setVaultRewardRate", async () => {
    let newVaultRewardRate = ONE.div(BigNumber.from(10));
    await expect(wooFeeManager.connect(user).setVaultRewardRate(newVaultRewardRate)).to.be.revertedWith(
      onlyAdminRevertedMessage
    );

    await wooFeeManager.connect(admin).setVaultRewardRate(newVaultRewardRate);

    newVaultRewardRate = newVaultRewardRate.div(BigNumber.from(10));
    await wooFeeManager.connect(owner).setVaultRewardRate(newVaultRewardRate);
  });

  it("Only owner able to inCaseTokenGotStuck", async () => {
    expect(await token.balanceOf(user.address)).to.eq(BigNumber.from(0));
    await expect(wooFeeManager.connect(user).inCaseTokenGotStuck(token.address)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    );
    expect(await token.balanceOf(user.address)).to.eq(BigNumber.from(0));

    expect(await token.balanceOf(admin.address)).to.eq(BigNumber.from(0));
    await expect(wooFeeManager.connect(admin).inCaseTokenGotStuck(token.address)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    );
    expect(await token.balanceOf(admin.address)).to.eq(BigNumber.from(0));

    expect(await token.balanceOf(owner.address)).to.eq(BigNumber.from(0));
    await wooFeeManager.connect(owner).inCaseTokenGotStuck(token.address);
    expect(await token.balanceOf(owner.address)).to.eq(mintToken);
  });

  it("Only owner able to setAccessManager", async () => {
    expect(await wooFeeManager.accessManager()).to.eq(wooAccessManager.address);
    await expect(wooFeeManager.connect(user).setAccessManager(newWooAccessManager.address)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    );
    await expect(wooFeeManager.connect(admin).setAccessManager(newWooAccessManager.address)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    );
    await wooFeeManager.connect(owner).setAccessManager(newWooAccessManager.address);
    expect(await wooFeeManager.accessManager()).to.eq(newWooAccessManager.address);
  });
});
