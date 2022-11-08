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
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
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

const ONE = ethers.BigNumber.from(10).pow(18);

describe("WooSuperChargerVault CornerCase", () => {
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
    wftm = await deployContract(owner, TestERC20TokenArtifact, []);
    want = usdcToken;
    quote = usdcToken;

    accessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager;

    reserveVault = (await deployContract(owner, WOOFiVaultV2Artifact, [
      wftm.address,
      want.address,
      accessManager.address,
    ])) as WOOFiVaultV2;

    await wftm.mint(owner.address, utils.parseEther("10000"));
    await usdcToken.mint(owner.address, utils.parseEther("5000"));

    await wftm.mint(user1.address, utils.parseEther("20000"));
    await usdcToken.mint(user1.address, utils.parseEther("3000"));

    wooracle = (await deployContract(owner, WooracleV2Artifact, [])) as WooracleV2;

    wooPP = (await deployContract(owner, WooPPV2Artifact, [quote.address])) as WooPPV2;

    await wooPP.init(wooracle.address, treasury.address);
    await wooPP.setFeeRate(wftm.address, 100);

    await wooracle.setAdmin(wooPP.address, true);
  });

  describe("ctor, init & basic func", () => {
    beforeEach("Deploy WooVaultManager", async () => {
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
      await superChargerVault.setTreasury(treasury.address);

      await wooPP.setAdmin(lendingManager.address, true);
    });

    it("Integration Test1: request withdraw, borrow, weekly settle, withdraw", async () => {
      // Steps:
      // 1. user deposits 100 usdc
      // 2. request withdraw 10 usdc
      // 3. borrow 20 + 10 usdc
      // 4. repaid 15 usdc
      // 5. weekly settle

      const amount = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault.deposit(amount);

      // Check vault status
      expect(await superChargerVault.costSharePrice(owner.address)).to.eq(utils.parseEther("1.0"));
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);

      expect(await superChargerVault.instantWithdrawCap()).to.eq(amount.div(10));
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(0);

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.requestedTotalAmount()).to.eq(0);
      expect(await superChargerVault.requestedWithdrawAmount(owner.address)).to.eq(0);

      // Request withdraw 10

      const rwAmount = utils.parseEther("10");
      await superChargerVault.approve(superChargerVault.address, rwAmount);
      await superChargerVault.requestWithdraw(rwAmount);

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.requestedTotalAmount()).to.eq(rwAmount);
      expect(await superChargerVault.requestedWithdrawAmount(owner.address)).to.eq(rwAmount);

      // Check lending manager status
      await lendingManager.setBorrower(owner.address, true);
      await lendingManager.setInterestRate(1000); // APR - 10%
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);
      expect(await lendingManager.borrowedPrincipal()).to.eq(0);
      expect(await lendingManager.borrowedInterest()).to.eq(0);
      expect(await lendingManager.debt()).to.eq(0);
      expect(await lendingManager.interestRate()).to.eq(1000);
      expect(await lendingManager.isBorrower(owner.address)).to.eq(true);
      expect(await lendingManager.isBorrower(user1.address)).to.eq(false);

      // Borrow
      await expect(lendingManager.connect(user1.address).borrow(100)).to.be.revertedWith(
        "WooLendingManager: !borrower"
      );

      let borrowAmount = utils.parseEther("20");
      const bal1 = await wooPP.poolSize(want.address);
      await lendingManager.borrow(borrowAmount); // borrow 20 want token
      const bal2 = await wooPP.poolSize(want.address);
      expect(bal2.sub(bal1)).to.eq(borrowAmount);

      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);
      expect(await lendingManager.borrowedPrincipal()).to.eq(borrowAmount);
      expect(await lendingManager.borrowedInterest()).to.eq(0);
      expect(await lendingManager.debt()).to.eq(borrowAmount);

      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount.sub(borrowAmount));
      expect(await superChargerVault.lendingBalance()).to.eq(borrowAmount);
      expect(await superChargerVault.available()).to.eq(0);

      const borrowAmount1 = utils.parseEther("10");
      borrowAmount = borrowAmount.add(borrowAmount1);
      await lendingManager.borrow(borrowAmount1); // borrow 10 want token
      const wooBal = await wooPP.poolSize(want.address);
      expect(wooBal.sub(bal2)).to.eq(borrowAmount1);

      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);
      expect(await lendingManager.borrowedPrincipal()).to.eq(borrowAmount);
      expect(await lendingManager.borrowedInterest()).to.gt(0);

      const inst = await lendingManager.borrowedInterest();
      const rate = await lendingManager.perfRate();
      const instAfterFee = inst.sub(inst.mul(rate).div(10000));

      expect(await superChargerVault.balance()).to.eq(amount.add(instAfterFee));
      expect(await superChargerVault.reserveBalance()).to.eq(amount.sub(borrowAmount));
      expect(await superChargerVault.lendingBalance()).to.eq(borrowAmount.add(instAfterFee));

      // Repay
      const repaidAmount = utils.parseEther("15");
      const bal3 = await want.balanceOf(owner.address);
      await want.approve(lendingManager.address, repaidAmount);
      await lendingManager.repay(repaidAmount);

      const bal4 = await want.balanceOf(owner.address);
      expect(bal3.sub(bal4)).to.eq(repaidAmount);

      // borrowed 30, repaid 15, then the debt left is 15
      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(15);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(10);

      console.log("superCharger balance: ", utils.formatEther(await superChargerVault.balance()));
      console.log("superCharger reserveBalance: ", utils.formatEther(await superChargerVault.reserveBalance()));

      console.log("lendingManager debt: ", utils.formatEther(await lendingManager.debt()));
      console.log(
        "lendingManager weeklyNeededAmountForWithdraw: ",
        utils.formatEther(await superChargerVault.weeklyNeededAmountForWithdraw())
      );

      // Settle

      await superChargerVault.startWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(true);
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(15);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(10);

      await superChargerVault.endWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(15);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(0);

      expect((await withdrawManager.withdrawAmount(owner.address)).div(ONE)).to.eq(10);
    });

    it("Integration Test2: no requested amount during settling", async () => {
      // Steps:
      // 1. user deposits 100 usdc
      // 2. request withdraw 10 usdc
      // 3. borrow 20 + 10 usdc
      // 4. repaid 15 usdc
      // 5. weekly settle

      const amount = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault.deposit(amount);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);

      await superChargerVault.startWeeklySettle();

      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);
      expect(await superChargerVault.isSettling()).to.eq(true);

      await superChargerVault.endWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(false);
    });

    it("Integration Test3: request withdraw amount exceeds MAX", async () => {
      const amount = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault.deposit(amount);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);

      await expect(superChargerVault.requestWithdraw(0)).to.be.revertedWith("WooSuperChargerVault: !amount");
      await expect(superChargerVault.requestWithdraw(amount.add(1))).to.be.reverted;

      await expect(superChargerVault.connect(user1.address).requestWithdraw(utils.parseEther("1"))).to.be.reverted;

      await superChargerVault.approve(superChargerVault.address, amount);
      await superChargerVault.requestWithdraw(amount);
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(0);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
    });

    it("Integration Test4: instant withdraw amount exceeds MAX", async () => {
      const amount = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault.deposit(amount);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);

      await expect(superChargerVault.instantWithdraw(0)).to.be.revertedWith("WooSuperChargerVault: !amount");
      await expect(superChargerVault.instantWithdraw(amount)).to.be.revertedWith("WooSuperChargerVault: OUT_OF_CAP");
      await expect(superChargerVault.instantWithdraw(amount.div(10).add(1))).to.be.revertedWith(
        "WooSuperChargerVault: OUT_OF_CAP"
      );

      await superChargerVault.instantWithdraw(amount.div(10));
      const leftBal = amount.sub(amount.div(10));
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(leftBal);
      expect(await superChargerVault.balance()).to.eq(leftBal);
      expect(await superChargerVault.reserveBalance()).to.eq(leftBal);
    });

    it("Integration Test5: request and instant withdraw NOT ALLOWED during settling", async () => {
      const amount = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault.deposit(amount);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);

      await expect(superChargerVault.instantWithdraw(0)).to.be.revertedWith("WooSuperChargerVault: !amount");
      await expect(superChargerVault.instantWithdraw(amount)).to.be.revertedWith("WooSuperChargerVault: OUT_OF_CAP");
      await expect(superChargerVault.instantWithdraw(amount.div(10).add(1))).to.be.revertedWith(
        "WooSuperChargerVault: OUT_OF_CAP"
      );

      await superChargerVault.instantWithdraw(amount.div(10));
      const leftBal = amount.sub(amount.div(10));
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(leftBal);
      expect(await superChargerVault.balance()).to.eq(leftBal);
      expect(await superChargerVault.reserveBalance()).to.eq(leftBal);

      await superChargerVault.startWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(true);

      await expect(superChargerVault.requestWithdraw(utils.parseEther("1"))).to.be.revertedWith(
        "WooSuperChargerVault: CANNOT_WITHDRAW_IN_SETTLING"
      );
      await expect(superChargerVault.instantWithdraw(utils.parseEther("0.5"))).to.be.revertedWith(
        "WooSuperChargerVault: NOT_ALLOWED_IN_SETTLING"
      );

      await expect(superChargerVault.startWeeklySettle()).to.be.revertedWith("IN_SETTLING");

      await superChargerVault.endWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(false);

      await expect(superChargerVault.endWeeklySettle()).to.be.revertedWith("!SETTLING");
    });

    it("Integration Test6: repay in settling", async () => {
      const amount = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault.deposit(amount);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);

      // Check lending manager status
      await lendingManager.setBorrower(owner.address, true);
      await lendingManager.setInterestRate(1000); // APR - 10%

      const borrowAmount = utils.parseEther("20"); // Borrow 20
      await lendingManager.borrow(borrowAmount);

      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);

      await superChargerVault.instantWithdraw(utils.parseEther("10"));

      await superChargerVault.approve(superChargerVault.address, utils.parseEther("1000"));
      await superChargerVault.requestWithdraw(utils.parseEther("50"));

      console.log("balance: ", utils.formatEther(await superChargerVault.balance()));
      console.log("reserve balance: ", utils.formatEther(await superChargerVault.reserveBalance()));
      console.log("requested balance: ", utils.formatEther(await superChargerVault.requestedTotalAmount()));
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);

      console.log("max borrowable: ", utils.formatEther(await superChargerVault.maxBorrowableAmount()));

      await lendingManager.borrow(utils.parseEther("40")); // Borrow 40
      console.log("reserve balance: ", utils.formatEther(await superChargerVault.reserveBalance()));
      console.log("return: ", utils.formatEther(await superChargerVault.weeklyNeededAmountForWithdraw()));
      expect((await superChargerVault.weeklyNeededAmountForWithdraw()).div(ONE)).to.eq(24);

      // Settle

      await superChargerVault.startWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(true);
      expect((await superChargerVault.weeklyNeededAmountForWithdraw()).div(ONE)).to.eq(24);

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(60);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(50);

      await expect(superChargerVault.endWeeklySettle()).to.be.revertedWith("WEEKLY_REPAY_NOT_CLEARED");

      await want.approve(lendingManager.address, utils.parseEther("100"));
      await lendingManager.repayWeekly();

      expect(await superChargerVault.isSettling()).to.eq(true);
      expect((await superChargerVault.weeklyNeededAmountForWithdraw()).div(ONE)).to.eq(0);

      await superChargerVault.endWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect((await superChargerVault.weeklyNeededAmountForWithdraw()).div(ONE)).to.eq(0);
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.gt(0);
    });

    it("Integration Test7: deposit in settling", async () => {
      const amount = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault.deposit(amount);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);

      // Check lending manager status
      await lendingManager.setBorrower(owner.address, true);
      await lendingManager.setInterestRate(1000); // APR - 10%

      const borrowAmount = utils.parseEther("20"); // Borrow 20
      await lendingManager.borrow(borrowAmount);

      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);

      await superChargerVault.instantWithdraw(utils.parseEther("10"));

      await superChargerVault.approve(superChargerVault.address, utils.parseEther("1000"));
      await superChargerVault.requestWithdraw(utils.parseEther("50"));

      console.log("balance: ", utils.formatEther(await superChargerVault.balance()));
      console.log("reserve balance: ", utils.formatEther(await superChargerVault.reserveBalance()));
      console.log("requested balance: ", utils.formatEther(await superChargerVault.requestedTotalAmount()));
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);

      console.log("max borrowable: ", utils.formatEther(await superChargerVault.maxBorrowableAmount()));

      await lendingManager.borrow(utils.parseEther("40")); // Borrow 40
      console.log("reserve balance: ", utils.formatEther(await superChargerVault.reserveBalance()));
      console.log("return: ", utils.formatEther(await superChargerVault.weeklyNeededAmountForWithdraw()));
      expect((await superChargerVault.weeklyNeededAmountForWithdraw()).div(ONE)).to.eq(24);

      // Settle

      await superChargerVault.startWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(true);
      expect((await superChargerVault.weeklyNeededAmountForWithdraw()).div(ONE)).to.eq(24);

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(60);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(50);

      await expect(superChargerVault.endWeeklySettle()).to.be.revertedWith("WEEKLY_REPAY_NOT_CLEARED");

      await want.approve(superChargerVault.address, utils.parseEther("100"));
      await superChargerVault.deposit(utils.parseEther("26.7"));

      console.log("return: ", utils.formatEther(await superChargerVault.weeklyNeededAmountForWithdraw()));

      expect((await superChargerVault.weeklyNeededAmountForWithdraw()).div(ONE)).to.eq(0);

      await superChargerVault.endWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect((await superChargerVault.weeklyNeededAmountForWithdraw()).div(ONE)).to.eq(0);
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);
    });

    it("Integration Test8: instantWithdrawAll", async () => {
      const amount = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault.deposit(amount);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);

      await expect(superChargerVault.instantWithdrawAll()).to.be.revertedWith('WooSuperChargerVault: OUT_OF_CAP')

      const user1Amount = amount.mul(10);
      await want.connect(user1).approve(superChargerVault.address, user1Amount);
      await superChargerVault.connect(user1).deposit(user1Amount);

      const curBal = await want.balanceOf(owner.address);
      const preTreasuryBal = await want.balanceOf(treasury.address);
      await superChargerVault.instantWithdrawAll();
      const newBal = await want.balanceOf(owner.address);
      const treasuryBal = (await want.balanceOf(treasury.address)).sub(preTreasuryBal);
      expect(treasuryBal).to.eq(amount.mul(await superChargerVault.instantWithdrawFeeRate()).div(10000));
      expect(newBal.sub(curBal).add(treasuryBal)).to.eq(amount);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(0);
      expect(await superChargerVault.balance()).to.eq(user1Amount);
      expect(await superChargerVault.reserveBalance()).to.eq(user1Amount);
    })

    it("Integration Test9: requestWithdrawAll", async () => {
      const amount = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault.deposit(amount);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);

      const user1Amount = amount.mul(10);
      await want.connect(user1).approve(superChargerVault.address, user1Amount);
      await superChargerVault.connect(user1).deposit(user1Amount);

      const userBal = await superChargerVault.balanceOf(owner.address);
      await superChargerVault.approve(superChargerVault.address, userBal);
      await superChargerVault.requestWithdrawAll();

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.requestedTotalAmount()).to.eq(amount);
      expect(await superChargerVault.requestedWithdrawAmount(owner.address)).to.eq(amount);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(0);
      expect(await superChargerVault.balance()).to.eq(amount.add(user1Amount));
      expect(await superChargerVault.reserveBalance()).to.eq(amount.add(user1Amount));
    })
  });
});
