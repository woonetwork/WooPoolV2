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
import { deployContract, solidity } from "ethereum-waffle";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

import {
  WooracleV2,
  WooPPV2,
  WooAccessManager,
  WooSuperChargerVault,
  WooLendingManager,
  WooWithdrawManager,
  WOOFiVaultV2,
} from "../../typechain";
import WooracleV2Artifact from "../../artifacts/contracts/WooracleV2.sol/WooracleV2.json";
import WooPPV2Artifact from "../../artifacts/contracts/WooPPV2.sol/WooPPV2.json";

import TestERC20TokenArtifact from "../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json";
import WooAccessManagerArtifact from "../../artifacts/contracts/WooAccessManager.sol/WooAccessManager.json";
import WooSuperChargerVaultArtifact from "../../artifacts/contracts/earn/WooSuperChargerVault.sol/WooSuperChargerVault.json";
import WooLendingManagerArtifact from "../../artifacts/contracts/earn/WooLendingManager.sol/WooLendingManager.json";
import WooWithdrawManagerArtifact from "../../artifacts/contracts/earn/WooWithdrawManager.sol/WooWithdrawManager.json";

import WOOFiVaultV2Artifact from "../../artifacts/contracts/earn/VaultV2.sol/WOOFiVaultV2.json";

use(solidity);

const TREASURY_ADDR = "0x815D4517427Fc940A90A5653cdCEA1544c6283c9";

const ONE = ethers.BigNumber.from(10).pow(18);

describe("WooSuperChargerVault deposit USDC", () => {
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let treasury: SignerWithAddress;

  let wooracle: WooracleV2;
  let wooPP: WooPPV2;

  let accessManager: WooAccessManager;
  let reserveVault: WOOFiVaultV2;

  let superChargerVault: WooSuperChargerVault;
  let lendingManager: WooLendingManager;
  let withdrawManager: WooWithdrawManager;

  let want: Contract;
  let wftm: Contract;
  let usdcToken: Contract;
  let quote: Contract;

  before("Tests Init", async () => {
    [owner, user1, user2, treasury] = await ethers.getSigners();
    usdcToken = await deployContract(owner, TestERC20TokenArtifact, []);
    wftm = await deployContract(owner, TestERC20TokenArtifact, []);
    want = usdcToken;
    quote = usdcToken;

    accessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager;

    await wftm.mint(owner.address, utils.parseEther("10000"));
    await usdcToken.mint(owner.address, utils.parseEther("5000"));

    await wftm.mint(user1.address, utils.parseEther("20000"));
    await usdcToken.mint(user1.address, utils.parseEther("3000"));

    await wftm.mint(user2.address, utils.parseEther("10000"));
    await usdcToken.mint(user2.address, utils.parseEther("1000"));

    wooracle = (await deployContract(owner, WooracleV2Artifact, [])) as WooracleV2;

    wooPP = (await deployContract(owner, WooPPV2Artifact, [quote.address])) as WooPPV2;

    await wooPP.init(wooracle.address, treasury.address);
    await wooPP.setFeeRate(wftm.address, 100);

    await wooracle.setAdmin(wooPP.address, true);
  });

  describe("ctor, init & basic func", () => {
    beforeEach("Deploy WooVaultManager", async () => {
      reserveVault = (await deployContract(owner, WOOFiVaultV2Artifact, [
        wftm.address,
        want.address,
        accessManager.address,
      ])) as WOOFiVaultV2;

      superChargerVault = (await deployContract(owner, WooSuperChargerVaultArtifact, [
        wftm.address,
        want.address,
        accessManager.address,
      ])) as WooSuperChargerVault;

      lendingManager = (await deployContract(owner, WooLendingManagerArtifact, [])) as WooLendingManager;
      await lendingManager.init(
        wftm.address,
        want.address,
        accessManager.address,
        wooPP.address,
        superChargerVault.address
      );
      await lendingManager.setTreasury(treasury.address);

      withdrawManager = (await deployContract(owner, WooWithdrawManagerArtifact, [])) as WooWithdrawManager;
      await withdrawManager.init(wftm.address, want.address, accessManager.address, superChargerVault.address);

      await superChargerVault.init(reserveVault.address, lendingManager.address, withdrawManager.address);

      await wooPP.setLendManager(lendingManager.address);
      await lendingManager.setBorrower(wooPP.address, true);
    });

    it("Deposit test1", async () => {
      let amount = utils.parseEther("80");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault["deposit(uint256)"](amount);

      // Check vault status
      expect(await superChargerVault.costSharePrice(owner.address)).to.eq(utils.parseEther("1.0"));
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);

      expect(await superChargerVault.instantWithdrawCap()).to.eq(amount.div(10));
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(0);

      // Deposit

      const amount1 = utils.parseEther("20");
      await want.approve(superChargerVault.address, amount1);
      await superChargerVault["deposit(uint256)"](amount1);
      amount = amount.add(amount1);

      expect(await superChargerVault.costSharePrice(owner.address)).to.eq(utils.parseEther("1.0"));
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);

      expect(await superChargerVault.instantWithdrawCap()).to.eq(amount.div(10));
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(0);

      await expect(superChargerVault["instantWithdraw(uint256)"](0)).to.be.revertedWith("WooSuperChargerVault: !amount");
      await expect(superChargerVault["instantWithdraw(uint256)"](amount.div(2))).to.be.revertedWith(
        "WooSuperChargerVault: OUT_OF_CAP"
      );

    });

    it("Deposit test2", async () => {
      let bal1 = await want.balanceOf(owner.address);
      let amount = utils.parseEther("80");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault["deposit(uint256,address)"](amount, user1.address);
      let bal2 = await want.balanceOf(owner.address);

      expect(bal1.sub(bal2)).to.be.eq(amount);

      // Check vault status
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(0);
      expect(await superChargerVault.balanceOf(user1.address)).to.eq(amount);

      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);

      expect(await superChargerVault.instantWithdrawCap()).to.eq(amount.div(10));
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(0);

      // Deposit
      let amount1 = utils.parseEther("20");
      await want.approve(superChargerVault.address, amount1);
      await superChargerVault["deposit(uint256,address)"](amount1, owner.address);
      let totalAmount = amount.add(amount1);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount1);
      expect(await superChargerVault.balanceOf(user1.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(totalAmount);
      expect(await superChargerVault.reserveBalance()).to.eq(totalAmount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);

      expect(await superChargerVault.instantWithdrawCap()).to.eq(totalAmount.div(10));
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(0);

      await expect(superChargerVault["instantWithdraw(uint256)"](0)).to.be.revertedWith("WooSuperChargerVault: !amount");
      await expect(superChargerVault["instantWithdraw(uint256)"](totalAmount.div(2))).to.be.revertedWith(
        "WooSuperChargerVault: OUT_OF_CAP"
      );

      // Deposit
      const amount2 = utils.parseEther("30");
      await want.approve(superChargerVault.address, amount2);
      await superChargerVault["deposit(uint256)"](amount2);
      totalAmount = totalAmount.add(amount2);
      amount1 = amount1.add(amount2);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount1);
      expect(await superChargerVault.balanceOf(user1.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(totalAmount);
      expect(await superChargerVault.reserveBalance()).to.eq(totalAmount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);
    });

  });
});
