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
  IOUVault,
  WooLendingManagerV2,
  WooracleV2,
  WooPPV2,
} from "../../typechain";

import WooracleV2Artifact from "../../artifacts/contracts/wooracle/WooracleV2.sol/WooracleV2.json";
import WooPPV2Artifact from "../../artifacts/contracts/WooPPV2.sol/WooPPV2.json";

import TestERC20TokenArtifact from "../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json";
import WFTMArtifact from "../../artifacts/contracts/test/WFTM.sol/WFTM.json";
import WooAccessManagerArtifact from "../../artifacts/contracts/WooAccessManager.sol/WooAccessManager.json";
import IOUVaultArtifact from "../../artifacts/contracts/earn/IOUVault.sol/IOUVault.json";
import WooLendingManagerV2Artifact from "../../artifacts/contracts/earn/WooLendingManagerV2.sol/WooLendingManagerV2.json";

use(solidity);

const TREASURY_ADDR = "0x815D4517427Fc940A90A5653cdCEA1544c6283c9";

const ONE = ethers.BigNumber.from(10).pow(18);

describe("WooIOUVault WFTM", () => {
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let treasury: SignerWithAddress;

  let wooracle: WooracleV2;
  let wooPP: WooPPV2;

  let accessManager: WooAccessManager;

  let IOUVault: IOUVault;
  let lendingManager: WooLendingManager;

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

      IOUVault = (await deployContract(owner, IOUVaultArtifact, [
        wftm.address,
        want.address,
        accessManager.address,
      ])) as IOUVault;

      lendingManager = (await deployContract(owner, WooLendingManagerV2Artifact, [])) as WooLendingManagerV2;
      await lendingManager.init(
        wftm.address,
        want.address,
        accessManager.address,
        wooPP.address,
        IOUVault.address
      );

      await IOUVault.init(lendingManager.address);

      await wooPP.setAdmin(lendingManager.address, true);
    });

    it("Verify ctor & init", async () => {
      expect(await IOUVault.treasury()).to.eq(TREASURY_ADDR);
      expect(await IOUVault.withdrawFeeRate()).to.eq(30);

      expect(await IOUVault.available()).to.eq(0);
      expect(await IOUVault.balance()).to.eq(0);
      expect(await IOUVault.lendingBalance()).to.eq(0);
      expect(await IOUVault.getPricePerFullShare()).to.eq(utils.parseEther("1.0"));
    });

    it("Integration Test1: status, deposit, withdraw", async () => {
      let amount = utils.parseEther("80");
      let treasuryBalance;
      await want.approve(IOUVault.address, amount);
      await IOUVault["deposit(uint256)"](amount, { value: amount });

      // Check vault status
      console.log(utils.formatEther(await IOUVault.balanceOf(owner.address)));
      console.log(utils.formatEther(await IOUVault.balance()));
      console.log(utils.formatEther(await IOUVault.available()));
      console.log(utils.formatEther(await IOUVault.lendingBalance()));
      console.log(utils.formatEther(await IOUVault.getPricePerFullShare()));

      expect(await IOUVault.costSharePrice(owner.address)).to.eq(utils.parseEther("1.0"));
      expect(await IOUVault.balanceOf(owner.address)).to.eq(amount);
      expect(await IOUVault.balance()).to.eq(amount);
      expect(await IOUVault.lendingBalance()).to.eq(0);
      expect(await IOUVault.available()).to.eq(amount);
      expect(await IOUVault.getPricePerFullShare()).to.eq(utils.parseEther("1.0"));

      // Deposit

      const amount1 = utils.parseEther("20");
      await want.approve(IOUVault.address, amount1.mul(2));
      await IOUVault["deposit(uint256)"](amount1, { value: amount1 });
      amount = amount.add(amount1);
      const cap = amount.div(10);

      console.log(utils.formatEther(await IOUVault.balanceOf(owner.address)));
      console.log(utils.formatEther(await IOUVault.balance()));
      console.log(utils.formatEther(await IOUVault.available()));
      console.log(utils.formatEther(await IOUVault.lendingBalance()));
      console.log(utils.formatEther(await IOUVault.getPricePerFullShare()));

      expect(await IOUVault.costSharePrice(owner.address)).to.eq(utils.parseEther("1.0"));
      expect(await IOUVault.balanceOf(owner.address)).to.eq(amount);
      expect(await IOUVault.balance()).to.eq(amount);
      expect(await IOUVault.lendingBalance()).to.eq(0);
      expect(await IOUVault.available()).to.eq(amount);

      await expect(IOUVault["withdraw(uint256)"](0)).to.be.revertedWith("WooIOUVault: !amount");

      // withdraw

      treasuryBalance = await ethers.provider.getBalance(TREASURY_ADDR);

      expect(treasuryBalance).to.eq(0);

      // let bal1 = await want.balanceOf(owner.address)
      const bal1 = await ethers.provider.getBalance(owner.address);
      const withdrawAmount = amount.div(20); // withdraw = 100 / 20 = 5
  
      await IOUVault["withdraw(uint256)"](withdrawAmount);
      // let bal2 = await want.balanceOf(owner.address)
      const bal2 = await ethers.provider.getBalance(owner.address);

      const rate = await IOUVault.withdrawFeeRate();
      const fee = withdrawAmount.mul(rate).div(10000);
      console.log("rate, fee: ", rate.toNumber(), utils.formatEther(fee));

      treasuryBalance = await ethers.provider.getBalance(TREASURY_ADDR);

      expect(treasuryBalance).to.eq(fee);
      console.log("treasury balance: ", utils.formatEther(treasuryBalance));
      const userReceived = withdrawAmount.sub(fee);
      expect(bal2.sub(bal1).div(ONE)).to.eq(userReceived.div(ONE));

      // Double check the status

      amount = amount.sub(withdrawAmount);
      expect(await IOUVault.costSharePrice(owner.address)).to.eq(utils.parseEther("1.0"));
      expect(await IOUVault.balanceOf(owner.address)).to.eq(amount);
      expect(await IOUVault.balance()).to.eq(amount);
      expect(await IOUVault.lendingBalance()).to.eq(0);
      expect(await IOUVault.available()).to.eq(amount);

      // withdraw all capped amount
      const withdrawAmount2 = amount.div(10).sub(withdrawAmount);
      amount = amount.sub(withdrawAmount2);
      await IOUVault["withdraw(uint256)"](withdrawAmount2);
      expect(await IOUVault.balance()).to.eq(amount);

      // Set balance of treasury to 0
      await ethers.provider.send("hardhat_setBalance", [
        TREASURY_ADDR,
        "0x0" 
      ]);

      treasuryBalance = await ethers.provider.getBalance(TREASURY_ADDR);

      expect(treasuryBalance).to.eq(0);
      
    });

    it("usdc Integration Test2: borrow", async () => {
      // Steps:
      // 1. user deposits 100 usdc
      // 2. borrow 20 + 30 usdc

      let treasuryBalance;
      treasuryBalance = await ethers.provider.getBalance(TREASURY_ADDR);
      expect(treasuryBalance).to.eq(0);
      const amount = utils.parseEther("100");
      await want.approve(IOUVault.address, amount);
      await IOUVault["deposit(uint256)"](amount, { value: amount });

      // Check lending manager status
      await lendingManager.setBorrower(owner.address, true);
      await lendingManager.setInterestRate(1000); // APR - 10%
      await lendingManager.setMaxInterestRate(5000); // APR - 50%

      await expect(lendingManager.setInterestRate(50001)).to.be.revertedWith("RATE_INVALID");

      // 100-10=90 to borrow
      // await expect(lendingManager.borrow(utils.parseEther("100"))).to.be.revertedWith("INSUFF_AMOUNT_FOR_BORROW");
      // await expect(lendingManager.borrow(utils.parseEther("90.0001"))).to.be.revertedWith("INSUFF_AMOUNT_FOR_BORROW");
      await expect(lendingManager.borrow(utils.parseEther("100.0001"))).to.be.revertedWith("INSUFF_AMOUNT_FOR_BORROW");

      // Borrow - 50 in total
      // await lendingManager.borrow(utils.parseEther("20")); // borrow 20 want token
      // await lendingManager.borrow(utils.parseEther("30")); // borrow 30 want token
      await lendingManager.setTargetBorrowedAmount(utils.parseEther("10"));

      expect((await IOUVault.lendingBalance()).div(ONE)).to.eq(10);
      expect((await IOUVault.balance()).div(ONE)).to.eq(100);

      console.log("superCharger balance: ", utils.formatEther(await IOUVault.balance()));

      console.log("Borrowed principal and interest: ",
        utils.formatEther(await lendingManager.borrowedPrincipal()),
        utils.formatEther(await lendingManager.borrowedInterest())
      )

      expect((await IOUVault.available()).div(ONE)).to.eq(90);
      const reapyAmount = utils.parseEther("10");
      await want.approve(lendingManager.address, reapyAmount.mul(2));
      await lendingManager.repayPrincipal(reapyAmount);
      // await lendingManager.repayAll();

      expect((await IOUVault.available()).div(ONE)).to.eq(100);

      // Set balance of treasury to 0
      await ethers.provider.send("hardhat_setBalance", [
        TREASURY_ADDR,
        "0x0" 
      ]);

      treasuryBalance = await ethers.provider.getBalance(TREASURY_ADDR);

      expect(treasuryBalance).to.eq(0);
    });

  });
});
