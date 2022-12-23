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
import WFTMArtifact from "../../artifacts/contracts/test/WFTM.sol/WFTM.json";
import WooAccessManagerArtifact from "../../artifacts/contracts/WooAccessManager.sol/WooAccessManager.json";
import WooSuperChargerVaultArtifact from "../../artifacts/contracts/earn/WooSuperChargerVault.sol/WooSuperChargerVault.json";
import WooLendingManagerArtifact from "../../artifacts/contracts/earn/WooLendingManager.sol/WooLendingManager.json";
import WooWithdrawManagerArtifact from "../../artifacts/contracts/earn/WooWithdrawManager.sol/WooWithdrawManager.json";

import WOOFiVaultV2Artifact from "../../artifacts/contracts/earn/VaultV2.sol/WOOFiVaultV2.json";

use(solidity);

const TREASURY_ADDR = "0x815D4517427Fc940A90A5653cdCEA1544c6283c9";

const ONE = ethers.BigNumber.from(10).pow(18);

describe("WooSuperChargerVault USDC", () => {
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
    want = usdcToken;
    quote = usdcToken;

    accessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager;

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

    it("Integration Test: status, deposit, instant withdraw", async () => {
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

      // InstantWithdraw

      const bal1 = await want.balanceOf(owner.address);
      const instantWithdrawAmount = amount.div(20); // instant withdraw = 100 / 20 = 5
      await superChargerVault["instantWithdraw(uint256)"](instantWithdrawAmount);
      const bal2 = await want.balanceOf(owner.address);

      const rate = await superChargerVault.instantWithdrawFeeRate();
      const fee = instantWithdrawAmount.mul(rate).div(10000);
      expect(await want.balanceOf(TREASURY_ADDR)).to.eq(fee);

      const userReceived = instantWithdrawAmount.sub(fee);
      expect(bal2.sub(bal1)).to.eq(userReceived);

      // Double check the status

      const withdrawCap = amount.div(10);
      amount = amount.sub(instantWithdrawAmount);
      expect(await superChargerVault.costSharePrice(owner.address)).to.eq(utils.parseEther("1.0"));
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);

      expect(await superChargerVault.instantWithdrawCap()).to.eq(withdrawCap);
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(instantWithdrawAmount);

      // Instant withdraw all capped amount
      const instantWithdrawAmount2 = withdrawCap.sub(instantWithdrawAmount);
      amount = amount.sub(instantWithdrawAmount2);
      await superChargerVault["instantWithdraw(uint256)"](instantWithdrawAmount2);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);

      expect(await superChargerVault.instantWithdrawCap()).to.eq(withdrawCap);
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(instantWithdrawAmount2.add(instantWithdrawAmount));
    });

    it("Integration Test: request withdraw, weekly settle, withdraw", async () => {
      let amount = utils.parseEther("100");
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

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.requestedTotalAmount()).to.eq(0);
      expect(await superChargerVault.requestedWithdrawAmount(owner.address)).to.eq(0);

      // Request Withdrawn

      await expect(superChargerVault["requestWithdraw(uint256)"](0)).to.be.revertedWith("WooSuperChargerVault: !amount");
      await expect(superChargerVault["requestWithdraw(uint256)"](utils.parseEther("1000"))).to.be.revertedWith("");

      // Double check the status

      let rwAmount = utils.parseEther("10");
      await superChargerVault.approve(superChargerVault.address, rwAmount);
      await superChargerVault["requestWithdraw(uint256)"](rwAmount);

      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount.sub(rwAmount));
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.reserveBalance()).to.eq(amount);
      expect(await superChargerVault.lendingBalance()).to.eq(0);
      expect(await superChargerVault.available()).to.eq(0);

      expect(await superChargerVault.instantWithdrawCap()).to.eq(amount.div(10));
      expect(await superChargerVault.instantWithdrawnAmount()).to.eq(0);

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.requestedTotalAmount()).to.eq(rwAmount);
      expect(await superChargerVault.requestedWithdrawAmount(owner.address)).to.eq(rwAmount);

      const rwAmount1 = utils.parseEther("5");
      await superChargerVault.approve(superChargerVault.address, rwAmount1);
      await superChargerVault["requestWithdraw(uint256)"](rwAmount1);
      rwAmount = rwAmount.add(rwAmount1);
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount.sub(rwAmount));
      expect(await superChargerVault.balance()).to.eq(amount);

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.requestedTotalAmount()).to.eq(rwAmount);
      expect(await superChargerVault.requestedWithdrawAmount(owner.address)).to.eq(rwAmount);

      await expect(superChargerVault.connect(user1).startWeeklySettle()).to.be.revertedWith(
        "WooSuperChargerVault: !ADMIN"
      );

      await superChargerVault.startWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(true);
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount.sub(rwAmount));
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.requestedTotalAmount()).to.eq(rwAmount);
      expect(await superChargerVault.requestedWithdrawAmount(owner.address)).to.eq(rwAmount);

      // No need to repay, so just end the weekly settle

      await expect(superChargerVault.connect(user1).endWeeklySettle()).to.be.revertedWith(
        "WooSuperChargerVault: !ADMIN"
      );

      await superChargerVault.endWeeklySettle();

      amount = amount.sub(rwAmount);
      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.balanceOf(owner.address)).to.eq(amount);
      expect(await superChargerVault.balance()).to.eq(amount);
      expect(await superChargerVault.requestedTotalAmount()).to.eq(0);
      expect(await superChargerVault.requestedWithdrawAmount(owner.address)).to.eq(0);

      // Withdraw from with manager

      expect(await want.balanceOf(withdrawManager.address)).to.eq(rwAmount);
      expect(await withdrawManager.withdrawAmount(owner.address)).to.eq(rwAmount);
      const bal1 = await want.balanceOf(owner.address);
      await withdrawManager.withdraw();
      const bal2 = await want.balanceOf(owner.address);
      expect(bal2.sub(bal1)).to.eq(rwAmount);

      expect(await want.balanceOf(withdrawManager.address)).to.eq(0);
      expect(await withdrawManager.withdrawAmount(owner.address)).to.eq(0);
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

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.requestedTotalAmount()).to.eq(0);
      expect(await superChargerVault.requestedWithdrawAmount(owner.address)).to.eq(0);

      // Request withdraw 10

      const rwAmount = utils.parseEther("10");
      await superChargerVault.approve(superChargerVault.address, rwAmount);
      await superChargerVault["requestWithdraw(uint256)"](rwAmount);

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

    it("Integration Test2: request withdraw, borrow, weekly settle, withdraw", async () => {
      // Steps:
      // 1. user deposits 100 usdc
      // 2. request withdraw 40 usdc
      // 3. borrow 20 + 30 usdc
      // 4. weekly settle
      // 5. repaid weekly amount

      const amount = utils.parseEther("100");
      await want.approve(superChargerVault.address, amount);
      await superChargerVault["deposit(uint256)"](amount);

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

      console.log("lendingManager debt: ", utils.formatEther(await lendingManager.debt()));
      console.log(
        "lendingManager weeklyNeededAmountForWithdraw: ",
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
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);

      expect((await superChargerVault.lendingBalance()).div(ONE)).to.eq(50 - 23);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(0);

      expect(await want.balanceOf(await lendingManager.treasury())).to.gt(0);

      expect((await withdrawManager.withdrawAmount(owner.address)).div(ONE)).to.eq(40 + 30);
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

      expect((await withdrawManager.withdrawAmount(owner.address)).div(ONE)).to.eq(30);
      expect((await withdrawManager.withdrawAmount(user1.address)).div(ONE)).to.eq(10);

      expect(await want.balanceOf(await lendingManager.treasury())).to.gt(0);

      console.log("share_price: ", utils.formatEther(await superChargerVault.getPricePerFullShare()));
      console.log("balance: ", utils.formatEther(await superChargerVault.balance()));

      // Withdraw

      let bal1 = await want.balanceOf(owner.address);
      await withdrawManager.withdraw();
      let bal2 = await want.balanceOf(owner.address);
      const gas = utils.parseEther("0.001");
      expect(bal2.sub(bal1).add(gas).div(ONE)).to.eq(30);

      bal1 = await want.balanceOf(user1.address);
      await withdrawManager.connect(user1).withdraw();
      bal2 = await want.balanceOf(user1.address);
      expect(bal2.sub(bal1).add(gas).div(ONE)).to.eq(10);
    });

    it("Integration Test4: borrow and repay with WooPPV2", async () => {
      // Steps:
      // 1. user deposits 100 usdc
      // 2. request withdraw 10 usdc
      // 3. borrow 20 + 10 usdc
      // 4. WooPP repay

      const amount = utils.parseEther("100");
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

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.requestedTotalAmount()).to.eq(0);
      expect(await superChargerVault.requestedWithdrawAmount(owner.address)).to.eq(0);

      // Request withdraw 10

      const rwAmount = utils.parseEther("10");
      await superChargerVault.approve(superChargerVault.address, rwAmount);
      await superChargerVault["requestWithdraw(uint256)"](rwAmount);

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
      const wooppSize = await wooPP.poolSize(want.address);
      console.log('wooPP size', utils.formatEther(wooppSize));
      expect(wooppSize.sub(bal2)).to.eq(borrowAmount1);

      // Repay
      await expect(wooPP.connect(user1).repayWeeklyLending(want.address)).to.be.revertedWith("WooPPV2: !admin");

      const rw2Amount = utils.parseEther("80");
      await superChargerVault.approve(superChargerVault.address, rw2Amount);
      await superChargerVault["requestWithdraw(uint256)"](rw2Amount);

      console.log('weekly repayment: ', utils.formatEther(await lendingManager.weeklyRepayment()));

      await superChargerVault.startWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(true);
      expect((await superChargerVault.requestedTotalAmount()).div(ONE)).to.eq(90);

      // Repay

      const weeklyRepayAmount = await lendingManager.weeklyRepayment();
      console.log('needed repay amount: ', utils.formatEther(weeklyRepayAmount));

      const prePoolSize = await wooPP.poolSize(want.address);
      await wooPP.repayWeeklyLending(want.address);
      const poolSizeDelta = prePoolSize.sub(await wooPP.poolSize(want.address));

      await superChargerVault.endWeeklySettle();

      expect(await superChargerVault.isSettling()).to.eq(false);
      expect(await superChargerVault.weeklyNeededAmountForWithdraw()).to.eq(0);

      expect(poolSizeDelta.mul(1e6).div(ONE)).to.be.eq(weeklyRepayAmount.mul(1e6).div(ONE))
    })

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
