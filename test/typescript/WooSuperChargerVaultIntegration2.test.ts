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
  WooLendingManager,
  WooWithdrawManagerV2,
  WOOFiVaultV2,
  WooracleV2,
  WooPPV2,
} from "../../typechain";

import WooracleV2Artifact from "../../artifacts/contracts/WooracleV2.sol/WooracleV2.json";
import WooPPV2Artifact from "../../artifacts/contracts/WooPPV2.sol/WooPPV2.json";

import TestERC20TokenArtifact from "../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json";
import WFTMArtifact from "../../artifacts/contracts/test/WFTM.sol/WFTM.json";
import WooAccessManagerArtifact from "../../artifacts/contracts/WooAccessManager.sol/WooAccessManager.json";
import WooSuperChargerVaultArtifact from "../../artifacts/contracts/earn/WooSuperChargerVaultV2.sol/WooSuperChargerVaultV2.json";
import WooLendingManagerArtifact from "../../artifacts/contracts/earn/WooLendingManager.sol/WooLendingManager.json";
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

      withdrawManager = (await deployContract(owner, WooWithdrawManagerArtifact, [])) as WooWithdrawManager;
      await withdrawManager.init(wftm.address, want.address, accessManager.address, superChargerVault.address);

      await superChargerVault.init(reserveVault.address, lendingManager.address, withdrawManager.address);

      await wooPP.setAdmin(lendingManager.address, true);
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

    it("Integration Test1: status, deposit, instant withdraw", async () => {
      let amount = utils.parseEther("80");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault["deposit(uint256)"](amount, { value: amount });

      // Check vault statu
      console.log(utils.formatEther(await superChargerVault.balanceOf(owner.address)));
      console.log(utils.formatEther(await superChargerVault.balance()));
      console.log(utils.formatEther(await superChargerVault.available()));
      console.log(utils.formatEther(await superChargerVault.reserveBalance()));
      console.log(utils.formatEther(await superChargerVault.lendingBalance()));
      console.log(utils.formatEther(await superChargerVault.getPricePerFullShare()));

      expect(await superChargerVault.costSharePrice(owner.address)).to.eq(utils.parseEther("1.0"));
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);
      expect(await superChargerVault.getPricePerFullShare()).to.eq(utils.parseEther("1.0"));

      expect(await superChargerVault.instantWithdrawCap()).to.eq(amount.div(10));
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(0);

      // Deposit

      const amount1 = utils.parseEther("20");
      await want.approve(superChargerVault.address, amount1.mul(2));
      await superChargerVault["deposit(uint256)"](amount1, { value: amount1 });
      amount = amount.add(amount1);
      const cap = amount.div(10);

      console.log(utils.formatEther(await superChargerVault.balanceOf(owner.address)));
      console.log(utils.formatEther(await superChargerVault.balance()));
      console.log(utils.formatEther(await superChargerVault.available()));
      console.log(utils.formatEther(await superChargerVault.reserveBalance()));
      console.log(utils.formatEther(await superChargerVault.lendingBalance()));
      console.log(utils.formatEther(await superChargerVault.getPricePerFullShare()));

      expect(await superChargerVault.costSharePrice(owner.address)).to.eq(utils.parseEther("1.0"));
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);

      expect(await superChargerVault.instantWithdrawCap()).to.eq(cap);
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(0);

      await expect(superChargerVault["instantWithdraw(uint256)"](0)).to.be.revertedWith("WooSuperChargerVault: !amount");
      await expect(superChargerVault["instantWithdraw(uint256)"](amount.div(2))).to.be.revertedWith(
        "WooSuperChargerVault: OUT_OF_CAP"
      );

      // InstantWithdraw

      // let bal1 = await want.balanceOf(owner.address)
      const bal1 = await ethers.provider.getBalance(owner.address);
      const instantWithdrawAmount = amount.div(20); // instant withdraw = 100 / 20 = 5
      await superChargerVault["instantWithdraw(uint256)"](instantWithdrawAmount);
      // let bal2 = await want.balanceOf(owner.address)
      const bal2 = await ethers.provider.getBalance(owner.address);

      const rate = await superChargerVault.instantWithdrawFeeRate();
      const fee = instantWithdrawAmount.mul(rate).div(10000);
      console.log("rate, fee: ", rate.toNumber(), utils.formatEther(fee));

      const treasuryBalance = await ethers.provider.getBalance(TREASURY_ADDR);

      expect(treasuryBalance).to.eq(fee);
      console.log("treasury balance: ", utils.formatEther(treasuryBalance));

      const userReceived = instantWithdrawAmount.sub(fee);
      expect(bal2.sub(bal1).div(ONE)).to.eq(userReceived.div(ONE));

      // Double check the status

      amount = amount.sub(instantWithdrawAmount);
      expect(await superChargerVault.costSharePrice(owner.address)).to.eq(utils.parseEther("1.0"));
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);

      expect(await superChargerVault.instantWithdrawCap()).to.eq(cap);
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(instantWithdrawAmount);

      // Instant withdraw all capped amount
      const instantWithdrawAmount2 = amount.div(10).sub(instantWithdrawAmount);
      amount = amount.sub(instantWithdrawAmount2);
      await superChargerVault["instantWithdraw(uint256)"](instantWithdrawAmount2);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);

      expect(await superChargerVault.instantWithdrawCap()).to.eq(cap);
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(instantWithdrawAmount2.add(instantWithdrawAmount));
    });

    it("usdc Integration Test2: request withdraw, borrow, weekly settle, withdraw", async () => {
      // Steps:
      // 1. user deposits 100 usdc
      // 2. request withdraw 40 usdc
      // 3. borrow 20 + 30 usdc
      // 4. weekly settle
      // 5. repaid weekly amount

      const amount = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault["deposit(uint256)"](amount, { value: amount });

      let rwAmount = utils.parseEther("40");
      await superChargerVault.approve(superChargerVault.address, rwAmount);
      await superChargerVault["requestWithdraw(uint256)"](rwAmount);

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.requestedTotalAmount()).to.eq(rwAmount);
      expect(await superChargerVault.requestedWithdrawAmount(owner.address)).to.eq(rwAmount);

      // Check lending manager status
      await lendingManager.setBorrower(owner.address, true);
      await lendingManager.setInterestRate(1000); // APR - 10%

      await expect(lendingManager.setInterestRate(50001)).to.be.revertedWith("RATE_INVALID");

      // 100-10=90 to borrow
      await expect(lendingManager.borrow(utils.parseEther("100"))).to.be.revertedWith("INSUFF_AMOUNT_FOR_BORROW");
      await expect(lendingManager.borrow(utils.parseEther("90.0001"))).to.be.revertedWith("INSUFF_AMOUNT_FOR_BORROW");

      // Borrow - 50 in total
      await lendingManager.borrow(utils.parseEther("20")); // borrow 20 want token
      await lendingManager.borrow(utils.parseEther("30")); // borrow 30 want token

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(50);
      expect((await superChargerVault.balance()).div(ONE)).to.eq(100);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(40);

      console.log("superCharger balance: ", utils.formatEther(await superChargerVault.balance()));
      console.log("superCharger reserveBalance: ", utils.formatEther(await superChargerVault.reserveBalance()));

      console.log("Borrowed principal and interest: ",
        utils.formatEther(await lendingManager.borrowedPrincipal()),
        utils.formatEther(await lendingManager.borrowedInterest())
      )
      console.log(
        "superChargerVault weeklyNeededAmountForWithdraw: ",
        utils.formatEther(await superChargerVault.weeklyNeededAmountForWithdraw())
      );

      // Settle

      await superChargerVault.startWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(true);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(40);
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);

      // Repay

      let repayAmount = await superChargerVault.weeklyNeededAmountForWithdraw();
      await want.approve(lendingManager.address, repayAmount.mul(2));
      await lendingManager.repayWeekly();

      await superChargerVault.endWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(50);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(0);

      expect((await withdrawManager.withdrawAmount(owner.address)).div(ONE)).to.eq(40);

      console.log("share_price: ", utils.formatEther(await superChargerVault.getPricePerFullShare()));
      console.log("balance: ", utils.formatEther(await superChargerVault.balance()));

      console.log("Borrowed principal and interest: ",
        utils.formatEther(await lendingManager.borrowedPrincipal()),
        utils.formatEther(await lendingManager.borrowedInterest())
      )

      // Request 30 again

      rwAmount = utils.parseEther("30");
      await superChargerVault.approve(superChargerVault.address, rwAmount);
      await superChargerVault["requestWithdraw(uint256)"](rwAmount);

      // Settle

      await superChargerVault.startWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(true);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(30);
      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(50);
      expect((await superChargerVault.weeklyNeededAmountForWithdraw()).div(ONE)).to.eq(23);

      // Repay 23 usdc

      repayAmount = await superChargerVault.weeklyNeededAmountForWithdraw();
      await want.approve(lendingManager.address, repayAmount.mul(2));
      await lendingManager.repayWeekly();

      await superChargerVault.endWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect((await superChargerVault.weeklyNeededAmountForWithdraw()).div(ONE)).to.eq(0);
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.gt(0);

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(50 - 23);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(0);

      expect((await withdrawManager.withdrawAmount(owner.address)).div(ONE)).to.eq(40 + 30);
      expect(await want.balanceOf(await lendingManager.treasury())).to.gt(0);

      console.log("Borrowed principal and interest: ",
        utils.formatEther(await lendingManager.borrowedPrincipal()),
        utils.formatEther(await lendingManager.borrowedInterest())
      )

      // Withdraw

      const bal1 = await ethers.provider.getBalance(owner.address);
      await withdrawManager.withdraw();
      const bal2 = await ethers.provider.getBalance(owner.address);
      const gas = utils.parseEther("0.001");
      expect(bal2.sub(bal1).add(gas).div(ONE)).to.eq(40 + 30);
    });

    it("Integration Test3: multiple deposits and requests withdraw", async () => {
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
      await lendingManager.borrow(utils.parseEther("20")); // borrow 20 want token
      await lendingManager.borrow(utils.parseEther("30")); // borrow 30 want token

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(50);
      expect((await superChargerVault.balance()).div(ONE)).to.eq(120);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(40);

      console.log("superCharger balance: ", utils.formatEther(await superChargerVault.balance()));
      console.log("superCharger reserveBalance: ", utils.formatEther(await superChargerVault.reserveBalance()));

      console.log("lendingManager debt: ", utils.formatEther(await lendingManager.debt()));
      console.log(
        "superChargerVault weeklyNeededAmountForWithdraw: ",
        utils.formatEther(await superChargerVault.weeklyNeededAmountForWithdraw())
      );

      // Settle

      await superChargerVault.startWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(true);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(40);

      // Repay

      const repayAmount = await superChargerVault.weeklyNeededAmountForWithdraw();
      await want.approve(lendingManager.address, repayAmount.mul(2));
      await lendingManager.repayWeekly();

      await superChargerVault.endWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(50);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(0);

      expect(await want.balanceOf(await lendingManager.treasury())).to.gt(0);

      expect((await withdrawManager.withdrawAmount(owner.address)).div(ONE)).to.eq(30);
      expect((await withdrawManager.withdrawAmount(user1.address)).div(ONE)).to.eq(10);

      console.log("share_price: ", utils.formatEther(await superChargerVault.getPricePerFullShare()));
      console.log("balance: ", utils.formatEther(await superChargerVault.balance()));

      // Withdraw

      let bal1 = await ethers.provider.getBalance(owner.address);
      await withdrawManager.withdraw();
      let bal2 = await ethers.provider.getBalance(owner.address);
      const gas = utils.parseEther("0.001");
      expect(bal2.sub(bal1).add(gas).div(ONE)).to.eq(30);

      bal1 = await ethers.provider.getBalance(user1.address);
      await withdrawManager.connect(user1).withdraw();
      bal2 = await ethers.provider.getBalance(user1.address);
      expect(bal2.sub(bal1).add(gas).div(ONE)).to.eq(10);
    });

    it("WFTM Integration Test5: multiple deposits and request all", async () => {
      // Steps:
      // multiple deposits and multiple withdrawals; verify the result.

      const amount1 = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount1);
      await superChargerVault["deposit(uint256)"](amount1, { value: amount1 });

      const amount2 = utils.parseEther("20");
      await want.connect(user1).approve(superChargerVault.address, amount2);
      await superChargerVault.connect(user1)["deposit(uint256)"](amount2, { value: amount2 });

      // Check lending manager status
      await lendingManager.setBorrower(owner.address, true);
      await lendingManager.setInterestRate(1000); // APR - 10%

      // Borrow - 100 in total
      await lendingManager.borrow(utils.parseEther("20")); // borrow 20 want token
      await lendingManager.borrow(utils.parseEther("80")); // borrow 80 want token

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(100);
      expect((await superChargerVault.balance()).div(ONE)).to.eq(120);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(0);

      console.log("superCharger balance: ", utils.formatEther(await superChargerVault.balance()));
      console.log("superCharger reserveBalance: ", utils.formatEther(await superChargerVault.reserveBalance()));
      console.log("lendingManager debt: ", utils.formatEther(await lendingManager.debt()));
      console.log(
        "superChargerVault weeklyNeededAmountForWithdraw: ",
        utils.formatEther(await superChargerVault.weeklyNeededAmountForWithdraw())
      );

      // Request - 120 in total
      const rwAmount1 = utils.parseEther("100");
      await superChargerVault.approve(superChargerVault.address, rwAmount1);
      await superChargerVault.requestWithdrawAll();

      const rwAmount2 = utils.parseEther("20");
      await superChargerVault.connect(user1).approve(superChargerVault.address, rwAmount2);
      await superChargerVault.connect(user1).requestWithdrawAll();

      // Settle

      await superChargerVault.startWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(true);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(120);

      // Repay

      const repayAmount = await superChargerVault.weeklyNeededAmountForWithdraw();
      await want.approve(lendingManager.address, repayAmount.mul(2));
      await lendingManager.repayWeekly();

      await superChargerVault.endWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(0);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(0);

      expect((await withdrawManager.withdrawAmount(owner.address)).div(ONE)).to.eq(100);
      expect((await withdrawManager.withdrawAmount(user1.address)).div(ONE)).to.eq(20);

      expect(await want.balanceOf(await lendingManager.treasury())).to.gt(0);

      console.log("share_price: ", utils.formatEther(await superChargerVault.getPricePerFullShare()));
      console.log("superCharger balance raw: ", await superChargerVault.balance());
      console.log("superCharger balance: ", utils.formatEther(await superChargerVault.balance()));
      console.log("superCharger reserveBalance: ", utils.formatEther(await superChargerVault.reserveBalance()));
      console.log("lendingManager debt: ", utils.formatEther(await lendingManager.debt()));
      console.log("lendingManager borrowed principal: ", utils.formatEther(await lendingManager.borrowedPrincipal()));
      console.log("lendingManager borrowed interest: ", utils.formatEther(await lendingManager.borrowedInterest()));
      console.log(
        "superChargerVault weeklyNeededAmountForWithdraw: ",
        utils.formatEther(await superChargerVault.weeklyNeededAmountForWithdraw())
      );
    });

    it("Integration Test: migrate reserve vault", async () => {
      let amount = utils.parseEther("80");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault["deposit(uint256)"](amount, { value: amount });

      expect(await superChargerVault.costSharePrice(owner.address)).to.eq(utils.parseEther("1.0"));
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);
      expect(await superChargerVault.getPricePerFullShare()).to.eq(utils.parseEther("1.0"));
      expect(await superChargerVault.instantWithdrawCap()).to.eq(amount.div(10));
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(0);

      // Deposit

      const amount1 = utils.parseEther("50");
      await want.approve(superChargerVault.address, amount1);
      await superChargerVault["deposit(uint256)"](amount1, { value: amount1 });
      amount = amount.add(amount1);

      console.log(utils.formatEther(await superChargerVault.balanceOf(owner.address)));
      console.log(utils.formatEther(await superChargerVault.balance()));
      console.log(utils.formatEther(await superChargerVault.available()));
      console.log(utils.formatEther(await superChargerVault.reserveBalance()));
      console.log(utils.formatEther(await superChargerVault.lendingBalance()));
      console.log(utils.formatEther(await superChargerVault.getPricePerFullShare()));

      expect(await superChargerVault.costSharePrice(owner.address)).to.eq(utils.parseEther("1.0"));
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);
      expect(await superChargerVault.instantWithdrawCap()).to.eq(amount.div(10));
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(0);

      // Total reserve vault: 130 tokens

      const newVault = (await deployContract(owner, WOOFiVaultV2Artifact, [
        wftm.address,
        want.address,
        accessManager.address,
      ])) as WOOFiVaultV2;

      expect(await newVault.balance()).to.eq(0);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);

      await superChargerVault.migrateReserveVault(newVault.address);

      expect(await newVault.balance()).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
    });
  });
});
