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
  WooAccessManager,
  WooSuperChargerVaultV2,
  WooLendingManagerV12,
  WooWithdrawManagerV2,
  WOOFiVaultV2,
  WooracleV2,
  WooPPV2,
} from "../../typechain";

import WooracleV2Artifact from "../../artifacts/contracts/wooracle/WooracleV2.sol/WooracleV2.json";
import WooPPV2Artifact from "../../artifacts/contracts/WooPPV2.sol/WooPPV2.json";

import TestERC20TokenArtifact from "../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json";
import WFTMArtifact from "../../artifacts/contracts/test/WFTM.sol/WFTM.json";
import WooAccessManagerArtifact from "../../artifacts/contracts/WooAccessManager.sol/WooAccessManager.json";
import WooSuperChargerVaultArtifact from "../../artifacts/contracts/earn/WooSuperChargerVaultV2.sol/WooSuperChargerVaultV2.json";
import WooLendingManagerV1_2Artifact from "../../artifacts/contracts/earn/WooLendingManagerV1_2.sol/WooLendingManagerV1_2.json";
import WooWithdrawManagerArtifact from "../../artifacts/contracts/earn/WooWithdrawManagerV2.sol/WooWithdrawManagerV2.json";
import WOOFiVaultV2Artifact from "../../artifacts/contracts/earn/VaultV2.sol/WOOFiVaultV2.json";

use(solidity);

const TREASURY_ADDR = "0x815D4517427Fc940A90A5653cdCEA1544c6283c9";

const ONE = ethers.BigNumber.from(10).pow(18);

describe("WooSuperChargerVault WFTM", () => {
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let treasury: SignerWithAddress;

  let wooracle: WooracleV2;
  let wooPP: WooPPV2;
  let wooPP2: WooPPV2;

  let accessManager: WooAccessManager;
  let reserveVault: WOOFiVaultV2;

  let superChargerVault: WooSuperChargerVault;
  let lendingManager: WooLendingManagerV12;
  let withdrawManager: WooWithdrawManager;

  let want: Contract;
  let wftm: Contract;
  let usdcToken: Contract;
  let quote: Contract;

  before("Tests Init", async () => {
    [owner, user1, treasury] = await ethers.getSigners();
    usdcToken = await deployContract(owner, TestERC20TokenArtifact, []);
    wftm = await deployContract(owner, WFTMArtifact, []);
    want = wftm;
    quote = usdcToken;

    accessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager;

    await wftm.mint(owner.address, utils.parseEther("10000"));
    await usdcToken.mint(owner.address, utils.parseEther("5000"));

    await wftm.mint(user1.address, utils.parseEther("20000"));
    await usdcToken.mint(user1.address, utils.parseEther("6000"));

    wooracle = (await deployContract(owner, WooracleV2Artifact, [])) as WooracleV2;

    wooPP = (await deployContract(owner, WooPPV2Artifact, [quote.address])) as WooPPV2;

    await wooPP.init(wooracle.address, treasury.address);
    await wooPP.setFeeRate(wftm.address, 100);

    wooPP2 = (await deployContract(owner, WooPPV2Artifact, [quote.address])) as WooPPV2;

    await wooPP2.init(wooracle.address, treasury.address);
    await wooPP2.setFeeRate(wftm.address, 100);

    await wooracle.setAdmin(wooPP.address, true);
    await wooracle.setAdmin(wooPP2.address, true);
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

      lendingManager = (await deployContract(owner, WooLendingManagerV1_2Artifact, [])) as WooLendingManagerV12;
      await lendingManager.init(
        wftm.address,
        want.address,
        accessManager.address,
        superChargerVault.address
      );

      await lendingManager.addWooPP(wooPP.address);
      await lendingManager.addWooPP(wooPP2.address);

      withdrawManager = (await deployContract(owner, WooWithdrawManagerArtifact, [])) as WooWithdrawManager;
      await withdrawManager.init(wftm.address, want.address, accessManager.address, superChargerVault.address);

      await superChargerVault.init(reserveVault.address, lendingManager.address, withdrawManager.address);

      await wooPP.setAdmin(lendingManager.address, true);

      await wooPP2.setAdmin(lendingManager.address, true);
    });

    it("Verify ctor & init", async () => {
      expect(await superChargerVault.treasury()).to.eq(TREASURY_ADDR);
      expect(await superChargerVault.instantWithdrawFeeRate()).to.eq(30);
      expect(await superChargerVault.instantWithdrawCap()).to.eq(0);
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(0);

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.available()).to.eq(0);
      expect(await superChargerVault.balance()).to.eq(0);
      expect(await superChargerVault.reserveBalance()).to.eq(0);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.getPricePerFullShare()).to.eq(utils.parseEther("1.0"));
    });

    it("Integration3 test: multiple woopp for lending manager", async () => {
      // Steps:
      // multiple deposits and multiple withdrawals; verify the result.

      const amount1 = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount1);
      await superChargerVault["deposit(uint256)"](amount1, { value: amount1 });

      const amount2 = utils.parseEther("20");
      await want.connect(user1).approve(superChargerVault.address, amount2);
      await superChargerVault.connect(user1)["deposit(uint256)"](amount2, { value: amount2 });

      const rwAmount1 = utils.parseEther("30");
      await superChargerVault.approve(superChargerVault.address, rwAmount1);
      await superChargerVault["requestWithdraw(uint256)"](rwAmount1);

      const rwAmount2 = utils.parseEther("10");
      await superChargerVault.connect(user1).approve(superChargerVault.address, rwAmount2);
      await superChargerVault.connect(user1)["requestWithdraw(uint256)"](rwAmount2);

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.requestedTotalAmount()).to.eq(rwAmount1.add(rwAmount2));
      expect(await superChargerVault.requestedWithdrawAmount(owner.address)).to.eq(rwAmount1);
      expect(await superChargerVault.requestedWithdrawAmount(user1.address)).to.eq(rwAmount2);

      // Check lending manager status
      await lendingManager.setBorrower(owner.address, true);
      await lendingManager.setInterestRate(1000); // APR - 10%

      // Borrow - 50 in total
      await lendingManager.borrow(wooPP.address, utils.parseEther("1")); // borrow 20 want token
      await lendingManager.borrow(wooPP2.address, utils.parseEther("49")); // borrow 30 want token

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(50);
      expect((await superChargerVault.balance()).div(ONE)).to.eq(120);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(40);

      console.log("Part1")
      await logBalance();

      let rwAmount = utils.parseEther("30");
      await superChargerVault.approve(superChargerVault.address, rwAmount);
      await superChargerVault["requestWithdraw(uint256)"](rwAmount);

      // Settle

      await superChargerVault.startWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(true);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(70);

      // Repay

      const repayAmount = await superChargerVault.weeklyNeededAmountForWithdraw();
      expect(repayAmount).to.gt(0);

      console.log("Part2 repayAmount: %s", utils.formatEther(repayAmount));
      await logBalance();
      await want.approve(lendingManager.address, repayAmount.mul(2));
      await lendingManager.weeklyRepayment();
      await lendingManager.repayWeekly();

      await superChargerVault.endWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(false);
      await logBalance();
      expect((await superChargerVault.weeklyNeededAmountForWithdraw()).div(ONE)).to.eq(0);
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.gt(0);

      // Put 10% total balance to reserve vault.
      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(50-5);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(0);

      await logWooPP(wooPP.address);
      await logWooPP(wooPP2.address);

      expect((await withdrawManager.withdrawAmount(owner.address)).div(ONE)).to.eq(60);
      expect((await withdrawManager.withdrawAmount(user1.address)).div(ONE)).to.eq(10);

      expect(await want.balanceOf(await lendingManager.treasury())).to.gt(0);

      console.log("share_price: ", utils.formatEther(await superChargerVault.getPricePerFullShare()));
      console.log("balance: ", utils.formatEther(await superChargerVault.balance()));

      // Withdraw

      let bal1 = await ethers.provider.getBalance(owner.address);
      await withdrawManager.withdraw();
      let bal2 = await ethers.provider.getBalance(owner.address);
      const gas = utils.parseEther("0.001");
      expect(bal2.sub(bal1).add(gas).div(ONE)).to.eq(60);

      bal1 = await ethers.provider.getBalance(user1.address);
      await withdrawManager.connect(user1).withdraw();
      bal2 = await ethers.provider.getBalance(user1.address);
      expect(bal2.sub(bal1).add(gas).div(ONE)).to.eq(10);
    });

    async function logWooPP(wooPP: string) {
      let principal = await lendingManager.principals(wooPP);
      let interest = await lendingManager.interests(wooPP);
      console.log("WooPP: %s principal: %s interest: %s", wooPP, principal, interest);
    }

    async function logBalance() {
      let reserveBalance = utils.formatEther(await superChargerVault.reserveBalance());
      let balance = utils.formatEther(await superChargerVault.balance());
      let lendingBalance = utils.formatEther(await superChargerVault.lendingBalance());
      let requestedTotal = utils.formatEther(await superChargerVault.requestedTotalAmount());
      console.log("SuperChargerVault requestedTotal: %s balance: %s reserveBalance: %s lendingBalance: %s",
        requestedTotal, balance, reserveBalance, lendingBalance);
    }
  });
});
