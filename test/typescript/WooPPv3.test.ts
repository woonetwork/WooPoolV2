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

import { WooracleV2_1, WooPPV3, WooUsdOFT } from "../../typechain";
import TestERC20TokenArtifact from "../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json";
import WooracleV2_1Artifact from "../../artifacts/contracts/wooracle/WooracleV2_1.sol/WooracleV2_1.json";
import WooPPV3Artifact from "../../artifacts/contracts/WooPPV3/WooPPV3.sol/WooPPV3.json";
import WooUsdOFTArtifact from "../../artifacts/contracts/WooPPV3/WooUsdOFT.sol/WooUsdOFT.json";

use(solidity);

const { BigNumber } = ethers;

const ZERO_ADDR = "0x0000000000000000000000000000000000000000";

const BTC_PRICE = 20000;
const WOO_PRICE = 0.15;
const FEE = 0.001;

const ONE = BigNumber.from(10).pow(18);
const ONE_USD = BigNumber.from(10).pow(6);
const USD_DEC = BigNumber.from(10).pow(6);
const PRICE_DEC = BigNumber.from(10).pow(8);

describe("WooPPV3 Integration Tests", () => {
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let feeAddr: SignerWithAddress;

  let wooracle: WooracleV2_1;
  let btcToken: Contract;
  let wooToken: Contract;
  let usdtToken: WooUsdOFT;
  let quote: Contract;

  before("Deploy ERC20", async () => {
    [owner, user1, user2, feeAddr] = await ethers.getSigners();
    btcToken = await deployContract(owner, TestERC20TokenArtifact, []);
    wooToken = await deployContract(owner, TestERC20TokenArtifact, []);
    usdtToken = await deployContract(owner, WooUsdOFTArtifact, ["vusd", "vusd", ZERO_ADDR]);
    quote = usdtToken;

    wooracle = (await deployContract(owner, WooracleV2_1Artifact, [])) as WooracleV2_1;

    await btcToken.mint(owner.address, ONE.mul(10000));
    await wooToken.mint(owner.address, ONE.mul(1000000000));

    await usdtToken.setWooPP(owner.address, true);
    await usdtToken.mint(owner.address, ONE_USD.mul(500000000));
  });

  describe("WooPPV3 query", () => {
    let wooPP: WooPPV3;

    beforeEach("Deploy WooPPV3", async () => {
      wooPP = (await deployContract(owner, WooPPV3Artifact, [wooracle.address, feeAddr.address, usdtToken.address])) as WooPPV3;

      await wooPP.setCapBals(
        [btcToken.address, wooToken.address, usdtToken.address],
        [ONE.mul(1e3), ONE.mul(1e7), ONE_USD.mul(1e8)]);

      await usdtToken.setWooPP(wooPP.address, true);
      await wooPP.setFeeRate(btcToken.address, 100);

      await btcToken.approve(wooPP.address, ONE.mul(10));
      await wooPP.deposit(btcToken.address, ONE.mul(10));

      // await usdtToken.approve(wooPP.address, ONE_USD.mul(300000));
      // await wooPP.deposit(usdtToken.address, ONE_USD.mul(300000));

      await wooracle.postState(
        btcToken.address,
        PRICE_DEC.mul(BTC_PRICE), // price
        utils.parseEther("0.001"), // spread
        utils.parseEther("0.000000001") // coeff
      );

      await wooracle.postState(
        wooToken.address,
        PRICE_DEC.mul(15).div(100), // price
        utils.parseEther("0.001"),
        utils.parseEther("0.000000001")
      );

      await wooracle.setAdmin(wooPP.address, true);
    });

    it("query accuracy1", async () => {
      const btcNum = 1;
      const amount = await wooPP.query(btcToken.address, quote.address, ONE.mul(btcNum));
      const amountNum = Number(amount.div(USD_DEC));
      const benchmark = BTC_PRICE * btcNum * (1 - FEE);
      const slippage = (benchmark - amountNum) / benchmark;

      console.log("Query selling 1 btc for usdt: ", amountNum, slippage);
      expect(amountNum).to.lessThan(benchmark);
      expect(slippage).to.lessThan(0.0012);
    });

    it("query accuracy1_2", async () => {
      const btcNum = 3;
      const amount = await wooPP.query(btcToken.address, quote.address, ONE.mul(btcNum));
      const amountNum = Number(amount.div(USD_DEC));
      const benchmark = BTC_PRICE * btcNum * (1 - FEE);
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.0012);
      console.log("Query selling 3 btc for usdt: ", amountNum, slippage);
    });

    it("query accuracy1_3", async () => {
      const btcNum = 10;
      const amount = await wooPP.query(btcToken.address, quote.address, ONE.mul(btcNum));
      const amountNum = Number(amount.div(USD_DEC));
      const benchmark = BTC_PRICE * btcNum * (1 - FEE);
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.0013);
      console.log("Query selling 10 btc for usdt: ", amountNum, slippage);
    });

    it("query accuracy2_1", async () => {
      const uAmount = 10000;
      const amount = await wooPP.query(quote.address, btcToken.address, ONE_USD.mul(uAmount));
      const amountNum = Number(utils.formatEther(amount));
      const benchmark = (uAmount / BTC_PRICE) * (1 - FEE);
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.0012);
      console.log("Query selling 10000 usdt for btc: ", amountNum, slippage);
    });

    it("query accuracy2_2", async () => {
      const uAmount = 100000;
      const amount = await wooPP.query(quote.address, btcToken.address, ONE_USD.mul(uAmount));
      const amountNum = Number(utils.formatEther(amount));
      const benchmark = (uAmount / BTC_PRICE) * (1 - FEE);
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.0012);
      console.log("Query selling 100000 usdt for btc: ", amountNum, slippage);
    });

    it("query revert1", async () => {
      const btcAmount = 100;
      await wooPP.query(btcToken.address, quote.address, ONE.mul(btcAmount));
    });

    it("query revert2", async () => {
      const uAmount = 300000;
      await expect(wooPP.query(quote.address, btcToken.address, ONE_USD.mul(uAmount))).to.be.revertedWith(
        "WooPPV3: INSUFF_BALANCE"
      );
    });

    it("query revert3", async () => {
      const btcAmount = 100;
      await expect(wooPP.query(btcToken.address, wooToken.address, ONE.mul(btcAmount))).to.be.revertedWith(
        "WooPPV3: INSUFF_BALANCE"
      );
    });
  });

  describe("WooPPV3 swap", () => {
    let wooPP: WooPPV3;

    beforeEach("Deploy WooPPV3", async () => {
      wooPP = (await deployContract(owner, WooPPV3Artifact,
        [wooracle.address, feeAddr.address, usdtToken.address])) as WooPPV3;

      await wooPP.setCapBals(
        [btcToken.address, wooToken.address, usdtToken.address],
        [ONE.mul(1e3), ONE.mul(1e7), ONE_USD.mul(1e8)]);

      await usdtToken.setWooPP(wooPP.address, true);

      await wooPP.setFeeRate(btcToken.address, 100);

      await btcToken.mint(owner.address, ONE.mul(10));
      await usdtToken.mint(owner.address, ONE_USD.mul(300000));
      await wooToken.mint(owner.address, ONE.mul(3000000));

      await btcToken.approve(wooPP.address, ONE.mul(10));
      await wooPP.deposit(btcToken.address, ONE.mul(10));

      // await usdtToken.approve(wooPP.address, ONE_USD.mul(300000));
      // await wooPP.deposit(usdtToken.address, ONE_USD.mul(300000));

      await wooracle.postState(
        btcToken.address,
        PRICE_DEC.mul(BTC_PRICE), // price
        utils.parseEther("0.001"), // spread
        utils.parseEther("0.000000001") // coeff
      );

      await wooracle.setAdmin(wooPP.address, true);
    });

    it("sellBase accuracy1", async () => {
      await btcToken.mint(user1.address, ONE.mul(3));
      const preUserUsdt = await usdtToken.balanceOf(user1.address);
      const preUserBtc = await btcToken.balanceOf(user1.address);

      const baseAmount = ONE.mul(1);
      const minQuoteAmount = ONE_USD.mul(BTC_PRICE).mul(99).div(100);

      const preUnclaimedFee = await wooPP.unclaimedFee();
      const preWooppUsdtSize = await wooPP.poolSize(usdtToken.address);
      const preBtcSize = await wooPP.poolSize(btcToken.address);

      const quoteAmount = await wooPP.query(btcToken.address, quote.address, baseAmount);

      await btcToken.connect(user1).approve(wooPP.address, baseAmount);
      await btcToken.connect(user1).transfer(wooPP.address, baseAmount);
      await wooPP
        .connect(user1)
        .swap(btcToken.address, quote.address, baseAmount, minQuoteAmount, user1.address, ZERO_ADDR);

      console.log("swap query quote:", quoteAmount.div(ONE_USD).toString());
      console.log("unclaimed fee:", (await wooPP.unclaimedFee()).div(ONE_USD).toString());

      const wppUsdtSize = await wooPP.poolSize(usdtToken.address);
      const unclaimedFee = await wooPP.unclaimedFee();
      const fee = unclaimedFee.sub(preUnclaimedFee);
      console.log("balance usdt: ", (await usdtToken.balanceOf(wooPP.address)).div(ONE_USD).toString());
      console.log("pool usdt: ", wppUsdtSize.div(ONE_USD).toString());
      console.log("balance delta: ", preWooppUsdtSize.sub(wppUsdtSize).div(ONE_USD).toString());
      console.log("fee: ", preUnclaimedFee.div(ONE_USD).toString(), unclaimedFee.div(ONE_USD).toString());
      expect(fee).to.be.closeTo(quoteAmount.mul(100).div(1e5), 1e5);

      const userUsdt = await usdtToken.balanceOf(user1.address);
      expect(quoteAmount).to.eq(userUsdt.sub(preUserUsdt));

      const btcSize = await wooPP.poolSize(btcToken.address);
      expect(btcSize.sub(preBtcSize)).to.eq(baseAmount);

      const userBtc = await btcToken.balanceOf(user1.address);
      expect(btcSize.sub(preBtcSize)).to.eq(preUserBtc.sub(userBtc));

      console.log("user1 usdt: ", preUserUsdt.div(ONE_USD).toString(), userUsdt.div(ONE_USD).toString());
      console.log("user1 btc: ", utils.formatEther(preUserBtc), utils.formatEther(userBtc));

      console.log("wooPP usdt: ", preWooppUsdtSize.div(ONE_USD).toString(), wppUsdtSize.div(ONE_USD).toString());
      console.log("wooPP btc: ", utils.formatEther(preBtcSize), utils.formatEther(btcSize));
    });

    it("sellBase accuracy2", async () => {
      await btcToken.mint(user1.address, ONE.mul(3));
      const preUserUsdt = await usdtToken.balanceOf(user1.address);
      const preUserBtc = await btcToken.balanceOf(user1.address);

      const baseAmount = ONE.mul(3);
      const minQuoteAmount = ONE_USD.mul(BTC_PRICE).mul(99).div(100);

      const preUnclaimedFee = await wooPP.unclaimedFee();
      const preWooppUsdtSize = await wooPP.poolSize(usdtToken.address);
      const preBtcSize = await wooPP.poolSize(btcToken.address);

      const quoteAmount = await wooPP.query(btcToken.address, quote.address, baseAmount);

      await btcToken.connect(user1).approve(wooPP.address, baseAmount);
      await btcToken.connect(user1).transfer(wooPP.address, baseAmount);
      await wooPP
        .connect(user1)
        .swap(btcToken.address, quote.address, baseAmount, minQuoteAmount, user1.address, ZERO_ADDR);

      console.log("swap query quote:", quoteAmount.div(ONE_USD).toString());
      console.log("unclaimed fee:", (await wooPP.unclaimedFee()).div(ONE_USD).toString());

      const wppUsdtSize = await wooPP.poolSize(usdtToken.address);
      const unclaimedFee = await wooPP.unclaimedFee();
      const fee = unclaimedFee.sub(preUnclaimedFee);
      console.log("balance usdt: ", (await usdtToken.balanceOf(wooPP.address)).div(ONE_USD).toString());
      console.log("pool usdt: ", wppUsdtSize.div(ONE_USD).toString());
      console.log("balance delta: ", preWooppUsdtSize.sub(wppUsdtSize).div(ONE_USD).toString());
      console.log("fee: ", preUnclaimedFee.div(ONE_USD).toString(), unclaimedFee.div(ONE_USD).toString());
      expect(fee).to.be.closeTo(quoteAmount.mul(100).div(1e5), 1e5);

      const userUsdt = await usdtToken.balanceOf(user1.address);
      expect(quoteAmount).to.eq(userUsdt.sub(preUserUsdt));

      const btcSize = await wooPP.poolSize(btcToken.address);
      expect(btcSize.sub(preBtcSize)).to.eq(baseAmount);

      const userBtc = await btcToken.balanceOf(user1.address);
      expect(btcSize.sub(preBtcSize)).to.eq(preUserBtc.sub(userBtc));

      console.log("user1 usdt: ", preUserUsdt.div(ONE_USD).toString(), userUsdt.div(ONE_USD).toString());
      console.log("user1 btc: ", utils.formatEther(preUserBtc), utils.formatEther(userBtc));

      console.log("wooPP usdt: ", preWooppUsdtSize.div(ONE_USD).toString(), wppUsdtSize.div(ONE_USD).toString());
      console.log("wooPP btc: ", utils.formatEther(preBtcSize), utils.formatEther(btcSize));
    });

    it("sellBase fail1", async () => {
      await expect(wooPP.swap(btcToken.address, quote.address, ONE, 0, user2.address, ZERO_ADDR)).to.be.revertedWith(
        "WooPPV3: BASE_BALANCE_NOT_ENOUGH"
      );

      await expect(wooPP.swap(ZERO_ADDR, quote.address, ONE, 0, user2.address, ZERO_ADDR)).to.be.revertedWith(
        "WooPPV3: !baseToken"
      );

      await expect(wooPP.swap(usdtToken.address, quote.address, ONE, 0, user2.address, ZERO_ADDR)).to.be.revertedWith(
        "WooPPV3: !baseToken"
      );

      await expect(wooPP.swap(btcToken.address, quote.address, ONE, 0, ZERO_ADDR, ZERO_ADDR)).to.be.revertedWith(
        "WooPPV3: !to"
      );
    });

    it("sellBase fail2", async () => {
      await btcToken.approve(wooPP.address, ONE);
      await btcToken.transfer(wooPP.address, ONE);
      await expect(
        wooPP.swap(btcToken.address, quote.address, ONE, ONE_USD.mul(BTC_PRICE), user2.address, ZERO_ADDR)
      ).to.be.revertedWith("WooPPV3: quoteAmount_LT_minQuoteAmount");
    });

    it("sellQuote accuracy1", async () => {
      await btcToken.mint(user1.address, ONE.mul(3));
      await usdtToken.mint(user1.address, ONE_USD.mul(100000));
      const preUserUsdt = await usdtToken.balanceOf(user1.address);
      const preUserBtc = await btcToken.balanceOf(user1.address);

      const quoteAmount = ONE_USD.mul(20000);
      const minBaseAmount = ONE.div(BTC_PRICE).mul(99).div(100);

      const preUnclaimedFee = await wooPP.unclaimedFee();
      const preWooppUsdtSize = await wooPP.poolSize(usdtToken.address);
      const preBtcSize = await wooPP.poolSize(btcToken.address);

      const baseAmount = await wooPP.query(quote.address, btcToken.address, quoteAmount);

      await usdtToken.connect(user1).approve(wooPP.address, quoteAmount);
      await usdtToken.connect(user1).transfer(wooPP.address, quoteAmount);
      await wooPP
        .connect(user1)
        .swap(quote.address, btcToken.address, quoteAmount, minBaseAmount, user1.address, ZERO_ADDR);

      console.log("swap query base:", baseAmount.div(ONE).toString());
      console.log("unclaimed fee:", (await wooPP.unclaimedFee()).div(ONE_USD).toString());

      const wppUsdtSize = await wooPP.poolSize(usdtToken.address);
      const unclaimedFee = await wooPP.unclaimedFee();
      const fee = unclaimedFee.sub(preUnclaimedFee);
      console.log("balance usdt: ", (await usdtToken.balanceOf(wooPP.address)).div(ONE_USD).toString());
      console.log("pool usdt: ", wppUsdtSize.div(ONE_USD).toString());
      console.log("balance delta: ", preWooppUsdtSize.sub(wppUsdtSize).div(ONE_USD).toString());
      console.log("fee: ", preUnclaimedFee.div(ONE_USD).toString(), unclaimedFee.div(ONE_USD).toString());
      expect(fee).to.be.closeTo(quoteAmount.mul(100).div(1e5), 1e5);

      const userUsdt = await usdtToken.balanceOf(user1.address);
      expect(quoteAmount).to.eq(preUserUsdt.sub(userUsdt));

      const btcSize = await wooPP.poolSize(btcToken.address);
      expect(preBtcSize.sub(btcSize)).to.eq(baseAmount);

      const userBtc = await btcToken.balanceOf(user1.address);
      expect(preBtcSize.sub(btcSize)).to.eq(userBtc.sub(preUserBtc));

      console.log("user1 usdt: ", preUserUsdt.div(ONE_USD).toString(), userUsdt.div(ONE_USD).toString());
      console.log("user1 btc: ", utils.formatEther(preUserBtc), utils.formatEther(userBtc));

      console.log("wooPP usdt: ", preWooppUsdtSize.div(ONE_USD).toString(), wppUsdtSize.div(ONE_USD).toString());
      console.log("wooPP btc: ", utils.formatEther(preBtcSize), utils.formatEther(btcSize));
    });

    it("sellQuote accuracy2", async () => {
      await btcToken.mint(user1.address, ONE.mul(3));
      await usdtToken.mint(user1.address, ONE_USD.mul(100000));
      const preUserUsdt = await usdtToken.balanceOf(user1.address);
      const preUserBtc = await btcToken.balanceOf(user1.address);

      const quoteAmount = ONE_USD.mul(100000);
      const minBaseAmount = quoteAmount.div(BTC_PRICE).mul(99).div(100);

      const preUnclaimedFee = await wooPP.unclaimedFee();
      const preWooppUsdtSize = await wooPP.poolSize(usdtToken.address);
      const preBtcSize = await wooPP.poolSize(btcToken.address);

      const baseAmount = await wooPP.query(quote.address, btcToken.address, quoteAmount);

      await usdtToken.connect(user1).approve(wooPP.address, quoteAmount);
      await usdtToken.connect(user1).transfer(wooPP.address, quoteAmount);
      await wooPP
        .connect(user1)
        .swap(quote.address, btcToken.address, quoteAmount, minBaseAmount, user1.address, ZERO_ADDR);

      console.log("swap query base:", baseAmount.div(ONE).toString());
      console.log("unclaimed fee:", utils.formatEther(await wooPP.unclaimedFee()));

      const wppUsdtSize = await wooPP.poolSize(usdtToken.address);
      const unclaimedFee = await wooPP.unclaimedFee();
      const fee = unclaimedFee.sub(preUnclaimedFee);
      console.log("balance usdt: ", (await usdtToken.balanceOf(wooPP.address)).div(ONE_USD).toString());
      console.log("pool usdt: ", wppUsdtSize.div(ONE_USD).toString());
      console.log("balance delta: ", preWooppUsdtSize.sub(wppUsdtSize).div(ONE_USD).toString());
      console.log("fee: ", preUnclaimedFee.div(ONE).toString(), unclaimedFee.div(ONE_USD).toString());
      expect(fee).to.be.closeTo(quoteAmount.mul(100).div(1e5), 1e5);

      const userUsdt = await usdtToken.balanceOf(user1.address);
      expect(quoteAmount).to.eq(preUserUsdt.sub(userUsdt));

      const btcSize = await wooPP.poolSize(btcToken.address);
      expect(preBtcSize.sub(btcSize)).to.eq(baseAmount);

      const userBtc = await btcToken.balanceOf(user1.address);
      expect(preBtcSize.sub(btcSize)).to.eq(userBtc.sub(preUserBtc));

      console.log("user1 usdt: ", preUserUsdt.div(ONE_USD).toString(), userUsdt.div(ONE_USD).toString());
      console.log("user1 btc: ", utils.formatEther(preUserBtc), utils.formatEther(userBtc));

      console.log("wooPP usdt: ", preWooppUsdtSize.div(ONE_USD).toString(), wppUsdtSize.div(ONE_USD).toString());
      console.log("wooPP btc: ", utils.formatEther(preBtcSize), utils.formatEther(btcSize));
    });

    it("sellQuote fail1", async () => {
      const quoteAmount = ONE_USD.mul(20000);
      await expect(wooPP.swap(quote.address, btcToken.address, quoteAmount, 0, user2.address, ZERO_ADDR)).to.be.revertedWith(
        "WooPPV3: USD_BALANCE_NOT_ENOUGH"
      );

      await expect(wooPP.swap(quote.address, ZERO_ADDR, quoteAmount, 0, user2.address, ZERO_ADDR)).to.be.revertedWith(
        "WooPPV3: !baseToken"
      );

      await expect(wooPP.swap(quote.address, usdtToken.address, quoteAmount, 0, user2.address, ZERO_ADDR)).to.be.revertedWith(
        "WooPPV3: !baseToken"
      );

      await expect(wooPP.swap(quote.address, btcToken.address, quoteAmount, 0, ZERO_ADDR, ZERO_ADDR)).to.be.revertedWith(
        "WooPPV3: !to"
      );
    });

    it("sellQuote fail2", async () => {
      const quoteAmount = ONE_USD.mul(20000);
      await usdtToken.approve(wooPP.address, quoteAmount);
      await usdtToken.transfer(wooPP.address, quoteAmount);
      const minBaseAmount = ONE.mul(20000).div(BTC_PRICE);
      await expect(
        wooPP.swap(quote.address, btcToken.address, quoteAmount, minBaseAmount, user2.address, ZERO_ADDR)
      ).to.be.revertedWith("WooPPV3: baseAmount_LT_minBaseAmount");
    });

    it("balance accuracy", async () => {
      const bal1 = await wooPP.balance(usdtToken.address);
      const bal2 = await wooPP.balance(btcToken.address);
      expect(bal1).to.be.eq(ONE_USD.mul(0));
      expect(bal2).to.be.eq(ONE.mul(10));

      await btcToken.transfer(wooPP.address, ONE);

      expect(await wooPP.balance(btcToken.address)).to.be.eq(bal2.add(ONE));
    });

    it("balance failure", async () => {
      await expect(wooPP.balance(ZERO_ADDR)).to.be.revertedWith("WooPPV3: !BALANCE");
      console.log(await wooPP.balance(wooToken.address));
    });

    it("poolSize accuracy", async () => {
      const bal1 = await wooPP.poolSize(usdtToken.address);
      const bal2 = await wooPP.poolSize(btcToken.address);
      expect(bal1).to.be.eq(ONE_USD.mul(0));
      expect(bal2).to.be.eq(ONE.mul(10));

      await btcToken.transfer(wooPP.address, ONE);

      expect(await wooPP.balance(btcToken.address)).to.be.eq(bal2.add(ONE));

      expect(await wooPP.poolSize(btcToken.address)).to.be.not.eq(bal2.add(ONE));
      expect(await wooPP.poolSize(btcToken.address)).to.be.eq(bal2);
    });
  });

  describe("WooPPV3 admins", () => {
    let wooPP: WooPPV3;

    beforeEach("Deploy WooPPV3", async () => {
      wooPP = (await deployContract(owner, WooPPV3Artifact,
        [wooracle.address, feeAddr.address, usdtToken.address])) as WooPPV3;

      await wooPP.setCapBals(
        [btcToken.address, wooToken.address, usdtToken.address],
        [ONE.mul(1e3), ONE.mul(1e7), ONE_USD.mul(1e8)]);

      await usdtToken.setWooPP(wooPP.address, true);

      await wooPP.setFeeRate(btcToken.address, 100);

      await btcToken.mint(owner.address, ONE.mul(10));
      await usdtToken.mint(owner.address, ONE_USD.mul(300000));
      await wooToken.mint(owner.address, ONE.mul(3000000));

      await btcToken.approve(wooPP.address, ONE.mul(10));
      await wooPP.deposit(btcToken.address, ONE.mul(10));

      // await usdtToken.approve(wooPP.address, ONE_USD.mul(300000));
      // await wooPP.deposit(usdtToken.address, ONE_USD.mul(300000));

      await wooracle.postState(
        btcToken.address,
        PRICE_DEC.mul(BTC_PRICE), // price
        utils.parseEther("0.001"), // spread
        utils.parseEther("0.000000001") // coeff
      );

      await wooracle.setAdmin(wooPP.address, true);
    });

    it("deposit accuracy", async () => {
      expect(await wooPP.balance(btcToken.address)).to.be.eq(ONE.mul(10));
      expect(await wooPP.balance(usdtToken.address)).to.be.eq(ONE_USD.mul(0));

      expect(await wooPP.poolSize(btcToken.address)).to.be.eq(ONE.mul(10));
      expect(await wooPP.poolSize(usdtToken.address)).to.be.eq(ONE_USD.mul(0));
    });

    it("after swap: poolSize & balance accuracy1", async () => {
      const btcBal = await wooPP.balance(btcToken.address);
      const btcPool = await wooPP.poolSize(btcToken.address);
      expect(btcBal).to.be.eq(btcPool);

      const usdtBal = await wooPP.balance(usdtToken.address);
      const usdtPool = await wooPP.poolSize(usdtToken.address);
      expect(usdtBal).to.be.eq(usdtPool);

      const btcTradeAmount = ONE;
      const minToAmount = ONE_USD.mul(BTC_PRICE).mul(997).div(1000);

      const realToAmount = await wooPP.query(btcToken.address, quote.address, btcTradeAmount);

      await btcToken.transfer(wooPP.address, btcTradeAmount);
      await wooPP.swap(btcToken.address, quote.address, btcTradeAmount, minToAmount, owner.address, ZERO_ADDR);

      const newBtcBal = await wooPP.balance(btcToken.address);
      const newBtcPool = await wooPP.poolSize(btcToken.address);
      expect(btcBal).to.be.eq(btcPool);
      expect(newBtcBal).to.be.eq(btcBal.add(btcTradeAmount));
      expect(newBtcPool).to.be.eq(btcBal.add(btcTradeAmount));

      const newUsdtBal = await wooPP.balance(usdtToken.address);
      const newUsdtPool = await wooPP.poolSize(usdtToken.address);
      const fee = await wooPP.unclaimedFee();
      expect(fee).to.be.closeTo(realToAmount.mul(100).div(1e5), 1e5);
    });

    it("after swap: poolSize & balance accuracy2", async () => {
      const btcBal = await wooPP.balance(btcToken.address);
      const btcPool = await wooPP.poolSize(btcToken.address);
      expect(btcBal).to.be.eq(btcPool);

      const usdtBal = await wooPP.balance(usdtToken.address);
      const usdtPool = await wooPP.poolSize(usdtToken.address);
      expect(usdtBal).to.be.eq(usdtPool);

      const btcTradeAmount = ONE;
      const minToAmount = ONE_USD.mul(BTC_PRICE).mul(997).div(1000);

      const realToAmount = await wooPP.query(btcToken.address, usdtToken.address, btcTradeAmount);

      await btcToken.transfer(wooPP.address, btcTradeAmount);
      await wooPP.swap(btcToken.address, usdtToken.address, btcTradeAmount, minToAmount, wooPP.address, ZERO_ADDR);

      const newBtcBal = await wooPP.balance(btcToken.address);
      const newBtcPool = await wooPP.poolSize(btcToken.address);
      expect(btcBal).to.be.eq(btcPool);
      expect(newBtcBal).to.be.eq(btcBal.add(btcTradeAmount));
      expect(newBtcPool).to.be.eq(btcBal.add(btcTradeAmount));

      const newUsdtBal = await wooPP.balance(usdtToken.address);
      const newUsdtPool = await wooPP.poolSize(usdtToken.address);
      const fee = await wooPP.unclaimedFee();

      expect(fee).to.be.closeTo(realToAmount.mul(100).div(1e5), 1e5);
    });

    it("migrate accuracy", async () => {
      const newPool = (await deployContract(owner, WooPPV3Artifact, [wooracle.address, feeAddr.address, usdtToken.address])) as WooPPV3;

      expect(newPool.address).to.not.be.eq(wooPP.address);

      expect(await wooPP.balance(btcToken.address)).to.be.eq(ONE.mul(10));
      expect(await wooPP.balance(usdtToken.address)).to.be.eq(ONE_USD.mul(0));
      expect(await wooPP.poolSize(btcToken.address)).to.be.eq(ONE.mul(10));
      expect(await wooPP.poolSize(usdtToken.address)).to.be.eq(ONE_USD.mul(0));

      expect(await newPool.balance(btcToken.address)).to.be.eq(ONE.mul(0));
      expect(await newPool.balance(usdtToken.address)).to.be.eq(ONE_USD.mul(0));
      expect(await newPool.poolSize(btcToken.address)).to.be.eq(ONE.mul(0));
      expect(await newPool.poolSize(usdtToken.address)).to.be.eq(ONE_USD.mul(0));

      await newPool.setAdmin(wooPP.address, true);

      await wooPP.migrateToNewPool(btcToken.address, newPool.address);
      await wooPP.migrateToNewPool(usdtToken.address, newPool.address);

      expect(await wooPP.balance(btcToken.address)).to.be.eq(ONE.mul(0));
      expect(await wooPP.balance(usdtToken.address)).to.be.eq(ONE_USD.mul(0));
      expect(await wooPP.poolSize(btcToken.address)).to.be.eq(ONE.mul(0));
      expect(await wooPP.poolSize(usdtToken.address)).to.be.eq(ONE_USD.mul(0));

      expect(await newPool.balance(btcToken.address)).to.be.eq(ONE.mul(10));
      expect(await newPool.balance(usdtToken.address)).to.be.eq(ONE_USD.mul(0));
      expect(await newPool.poolSize(btcToken.address)).to.be.eq(ONE.mul(10));
      expect(await newPool.poolSize(usdtToken.address)).to.be.eq(ONE_USD.mul(0));
    });
  });

  describe("WooPPV3 BaseToBase Functions", () => {
    let wooPP: WooPPV3;

    beforeEach("Deploy WooPPV3", async () => {
      wooPP = (await deployContract(owner, WooPPV3Artifact, [wooracle.address, feeAddr.address, usdtToken.address])) as WooPPV3;

      await wooPP.setCapBals(
        [btcToken.address, wooToken.address, usdtToken.address],
        [ONE.mul(1e3), ONE.mul(1e7), ONE_USD.mul(1e8)]);

      await usdtToken.setWooPP(wooPP.address, true);

      await wooPP.setFeeRate(btcToken.address, 100);

      // await btcToken.approve(wooPP.address, ONE.mul(10))
      // await wooPP.deposit(btcToken.address, ONE.mul(10))

      // await usdtToken.approve(wooPP.address, ONE.mul(300000))
      // await wooPP.deposit(usdtToken.address, ONE.mul(300000))

      // await wooToken.approve(wooPP.address, ONE.mul(1000000))
      // await wooPP.deposit(wooToken.address, ONE.mul(1000000))

      await wooracle.postState(
        btcToken.address,
        PRICE_DEC.mul(BTC_PRICE), // price
        utils.parseEther("0.001"), // spread
        utils.parseEther("0.000000001") // coeff
      );

      await wooracle.postState(
        wooToken.address,
        PRICE_DEC.mul(15).div(100), // price
        utils.parseEther("0.001"),
        utils.parseEther("0.000000001")
      );

      await wooracle.setAdmin(wooPP.address, true);
    });

    it("queryBaseToBase accuracy1", async () => {
      await wooToken.approve(wooPP.address, ONE.mul(1000000));
      await wooPP.deposit(wooToken.address, ONE.mul(1000000));

      const btcNum = 1;
      const amount = await wooPP.query(btcToken.address, wooToken.address, ONE.mul(btcNum));
      const amountNum = Number(utils.formatEther(amount));
      const benchmark = (BTC_PRICE * btcNum * (1 - FEE)) / WOO_PRICE;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.0012);
      console.log("Query selling 1 btc for woo: ", amountNum, slippage);
    });

    it("queryBaseToBase accuracy2", async () => {
      const btcNum = 1;

      await expect(wooPP.query(btcToken.address, wooToken.address, ONE.mul(btcNum))).to.be.revertedWith(
        "WooPPV3: INSUFF_BALANCE"
      );

      await wooToken.approve(wooPP.address, ONE.mul(1000000));
      await wooPP.deposit(wooToken.address, ONE.mul(1000000));

      const amount = await wooPP.query(btcToken.address, wooToken.address, ONE.mul(btcNum));
      const amountNum = Number(utils.formatEther(amount));
      const benchmark = (BTC_PRICE * btcNum * (1 - FEE)) / WOO_PRICE;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.0012);
      console.log("Query selling 1 btc for woo: ", amountNum, slippage);
    });

    it("queryBaseToBase revert1", async () => {
      // await quote.approve(wooPP.address, ONE.mul(1000))
      // await wooPP.deposit(quote.address, ONE.mul(1000))

      const btcNum = 1;
      await expect(wooPP.query(btcToken.address, wooToken.address, ONE.mul(btcNum))).to.be.revertedWith(
        "WooPPV3: INSUFF_BALANCE"
      );

      await wooToken.approve(wooPP.address, ONE.mul(1000000));
      await wooPP.deposit(wooToken.address, ONE.mul(1000000));

      await wooPP.query(btcToken.address, wooToken.address, ONE.mul(btcNum));
    });

    it("queryBaseToBase revert2", async () => {
      const btcNum = 1;
      await expect(wooPP.query(btcToken.address, wooToken.address, ONE.mul(btcNum))).to.be.revertedWith(
        "WooPPV3: INSUFF_BALANCE"
      );
    });

    it("tryQueryBaseToBase accuracy1", async () => {
      const btcNum = 1;

      await expect(wooPP.query(btcToken.address, wooToken.address, ONE.mul(btcNum))).to.be.revertedWith(
        "WooPPV3: INSUFF_BALANCE"
      );

      const amount = await wooPP.tryQuery(btcToken.address, wooToken.address, ONE.mul(btcNum));
      const amountNum = Number(utils.formatEther(amount));
      const benchmark = (BTC_PRICE * btcNum * (1 - FEE)) / WOO_PRICE;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.0012);
      console.log("Query selling 1 btc for woo: ", amountNum, slippage);
    });

    it("tryQueryBaseToBase accuracy1", async () => {
      expect(await wooPP.tryQuery(ZERO_ADDR, wooToken.address, ONE)).to.be.equal(0);
      expect(await wooPP.tryQuery(btcToken.address, ZERO_ADDR, ONE)).to.be.equal(0);
      expect(await wooPP.tryQuery(ZERO_ADDR, ZERO_ADDR, ONE)).to.be.equal(0);
    });

    it("swapBaseToBase accuracy1", async () => {
      _clearUser1Balance();

      await btcToken.approve(wooPP.address, ONE.mul(10));
      await wooPP.deposit(btcToken.address, ONE.mul(10));

      await wooToken.approve(wooPP.address, ONE.mul(1000000));
      await wooPP.deposit(wooToken.address, ONE.mul(1000000));

      await btcToken.mint(user1.address, ONE.mul(3));
      await usdtToken.mint(user1.address, ONE_USD.mul(100000));
      const preUserWoo = await wooToken.balanceOf(user1.address);
      const preUserBtc = await btcToken.balanceOf(user1.address);

      const base1Amount = ONE;
      const minBase2Amount = base1Amount.mul(BTC_PRICE).mul(100).div(15).mul(997).div(1000);

      const preUnclaimedFee = await wooPP.unclaimedFee();
      const preWooppWooSize = await wooPP.poolSize(wooToken.address);
      const preWooppUsdtSize = await wooPP.poolSize(usdtToken.address);
      const preBtcSize = await wooPP.poolSize(btcToken.address);

      const baseAmount = await wooPP.query(btcToken.address, wooToken.address, base1Amount);

      await btcToken.connect(user1).approve(wooPP.address, base1Amount);
      await btcToken.connect(user1).transfer(wooPP.address, base1Amount);
      await wooPP
        .connect(user1)
        .swap(btcToken.address, wooToken.address, base1Amount, minBase2Amount, user1.address, ZERO_ADDR);

      console.log("swap query base:", baseAmount.div(ONE).toString());
      console.log("unclaimed fee:", (await wooPP.unclaimedFee()).div(ONE_USD).toNumber());

      const wppUsdtSize = await wooPP.poolSize(usdtToken.address);
      const unclaimedFee = await wooPP.unclaimedFee();
      const fee = unclaimedFee.sub(preUnclaimedFee);
      console.log("balance usdt: ", (await usdtToken.balanceOf(wooPP.address)).div(ONE_USD).toString());
      console.log("pool usdt: ", wppUsdtSize.div(ONE_USD).toString());
      console.log("balance delta: ", preWooppUsdtSize.sub(wppUsdtSize).div(ONE_USD).toString());
      console.log("fee: ", preUnclaimedFee.div(ONE).toString(), unclaimedFee.div(ONE_USD).toString());
      expect(fee).to.closeTo(ONE_USD.mul(BTC_PRICE).mul(100).div(1e5), 1e5);

      const userWoo = await wooToken.balanceOf(user1.address);
      // expect(wppUsdtSize.sub(preWooppUsdtSize).add(fee)).to.eq(preUserUsdt.sub(userUsdt))
      // console.log('woo balance of wooPP: ', wppWooSize, preWooppWooSize)
      // console.log('woo balance of user: ', preUserWoo, userWoo)

      const wooSize = await wooPP.poolSize(wooToken.address);
      const btcSize = await wooPP.poolSize(btcToken.address);
      expect(btcSize.sub(preBtcSize)).to.eq(base1Amount);

      const userBtc = await btcToken.balanceOf(user1.address);
      expect(btcSize.sub(preBtcSize)).to.eq(preUserBtc.sub(userBtc));

      console.log("user1 woo: ", utils.formatEther(preUserWoo), utils.formatEther(userWoo));
      console.log("user1 btc: ", utils.formatEther(preUserBtc), utils.formatEther(userBtc));

      // console.log("wooPP usdt: ", utils.formatEther(preWooppUsdtSize), utils.formatEther(wppUsdtSize));
      console.log("wooPP btc: ", utils.formatEther(preBtcSize), utils.formatEther(btcSize));
      console.log("wooPP woo: ", utils.formatEther(preWooppWooSize), utils.formatEther(wooSize));

      console.log("wooPP fee: ", preUnclaimedFee.div(ONE_USD).toNumber(), unclaimedFee.div(ONE_USD).toNumber());
    });

    it("swapBaseToBase accuracy2", async () => {
      _clearUser1Balance();

      await btcToken.approve(wooPP.address, ONE.mul(10));
      await wooPP.deposit(btcToken.address, ONE.mul(10));

      // await usdtToken.approve(wooPP.address, ONE.mul(300000));
      // await wooPP.deposit(usdtToken.address, ONE.mul(300000));

      await wooToken.approve(wooPP.address, ONE.mul(1000000));
      await wooPP.deposit(wooToken.address, ONE.mul(1000000));

      await btcToken.mint(user1.address, ONE.mul(3));
      await wooToken.mint(user1.address, ONE.mul(500000));
      const preUserWoo = await wooToken.balanceOf(user1.address);
      const preUserBtc = await btcToken.balanceOf(user1.address);

      const base1Amount = ONE.mul(300000);
      const minBase2Amount = base1Amount.div(BTC_PRICE).mul(15).div(100).mul(997).div(1000);

      const preUnclaimedFee = await wooPP.unclaimedFee();
      const preWooppWooSize = await wooPP.poolSize(wooToken.address);
      const preWooppUsdtSize = await wooPP.poolSize(usdtToken.address);
      const preBtcSize = await wooPP.poolSize(btcToken.address);

      const baseAmount = await wooPP.query(wooToken.address, btcToken.address, base1Amount);

      await wooToken.connect(user1).approve(wooPP.address, base1Amount);
      await wooToken.connect(user1).transfer(wooPP.address, base1Amount);
      await wooPP
        .connect(user1)
        .swap(wooToken.address, btcToken.address, base1Amount, minBase2Amount, user1.address, ZERO_ADDR);

      console.log("swap query base:", baseAmount.div(ONE).toString());
      console.log("unclaimed fee:", utils.formatEther(await wooPP.unclaimedFee()));

      const wppUsdtSize = await wooPP.poolSize(usdtToken.address);
      const unclaimedFee = await wooPP.unclaimedFee();
      const fee = unclaimedFee.sub(preUnclaimedFee);
      console.log("balance usdt: ", (await usdtToken.balanceOf(wooPP.address)).div(ONE_USD).toString());
      console.log("pool usdt: ", wppUsdtSize.div(ONE_USD).toString());
      console.log("balance delta: ", preWooppUsdtSize.sub(wppUsdtSize).div(ONE_USD).toString());
      console.log("fee: ", preUnclaimedFee.div(ONE_USD).toString(), unclaimedFee.div(ONE_USD).toString());

      const userWoo = await wooToken.balanceOf(user1.address);
      // expect(wppUsdtSize.sub(preWooppUsdtSize).add(fee)).to.eq(preUserUsdt.sub(userUsdt))
      // console.log('woo balance of wooPP: ', wppWooSize, preWooppWooSize)
      // console.log('woo balance of user: ', preUserWoo, userWoo)

      const wooSize = await wooPP.poolSize(wooToken.address);
      expect(wooSize.sub(preWooppWooSize)).to.eq(base1Amount);
      const btcSize = await wooPP.poolSize(btcToken.address);

      const userBtc = await btcToken.balanceOf(user1.address);

      console.log("user1 woo: ", utils.formatEther(preUserWoo), utils.formatEther(userWoo));
      console.log("user1 btc: ", utils.formatEther(preUserBtc), utils.formatEther(userBtc));

      console.log("wooPP btc: ", utils.formatEther(preBtcSize), utils.formatEther(btcSize));
      console.log("wooPP woo: ", utils.formatEther(preWooppWooSize), utils.formatEther(wooSize));

      console.log("wooPP fee: ", preUnclaimedFee.div(ONE_USD).toNumber(), unclaimedFee.div(ONE_USD).toNumber());
    });

    it("swapBaseToBase revert1", async () => {
      // _clearUser1Balance();

      // await btcToken.approve(wooPP.address, ONE.mul(10))
      // await wooPP.deposit(btcToken.address, ONE.mul(10))

      // await usdtToken.approve(wooPP.address, ONE.mul(300000));
      // await wooPP.deposit(usdtToken.address, ONE.mul(300000));

      // await wooToken.approve(wooPP.address, ONE.mul(1000000))
      // await wooPP.deposit(wooToken.address, ONE.mul(1000000))

      await btcToken.mint(user1.address, ONE.mul(3));
      await wooToken.mint(user1.address, ONE.mul(500000));

      const base1Amount = ONE.mul(300000);
      const minBase2Amount = base1Amount.div(BTC_PRICE).mul(15).div(100).mul(997).div(1000);

      await wooToken.connect(user1).approve(wooPP.address, base1Amount);
      await wooToken.connect(user1).transfer(wooPP.address, base1Amount);
      await expect(
        wooPP
          .connect(user1)
          .swap(wooToken.address, btcToken.address, base1Amount, minBase2Amount, user1.address, ZERO_ADDR)
      ).to.be.reverted;
    });

    it("swapBaseToBase revert2", async () => {
      // _clearUser1Balance();

      await btcToken.approve(wooPP.address, ONE.mul(10));
      await wooPP.deposit(btcToken.address, ONE.mul(10));

      // // await usdtToken.approve(wooPP.address, ONE.mul(300000))
      // // await wooPP.deposit(usdtToken.address, ONE.mul(300000))

      await wooToken.approve(wooPP.address, ONE.mul(1000000));
      await wooPP.deposit(wooToken.address, ONE.mul(1000000));

      await btcToken.mint(user1.address, ONE.mul(3));
      await wooToken.mint(user1.address, ONE.mul(500000));

      const base1Amount = ONE.mul(300000);
      const minBase2Amount = base1Amount.div(BTC_PRICE).mul(15).div(100).mul(997).div(1000);

      await wooToken.connect(user1).approve(wooPP.address, base1Amount);
      await wooToken.connect(user1).transfer(wooPP.address, base1Amount);
      await wooPP.connect(user1)
          .swap(wooToken.address, btcToken.address, base1Amount, minBase2Amount, user1.address, ZERO_ADDR);
    });
  });

  async function _clearUser1Balance() {
    await wooToken.connect(user1).transfer(owner.address, await wooToken.balanceOf(user1.address));
    await btcToken.connect(user1).transfer(owner.address, await btcToken.balanceOf(user1.address));
    await usdtToken.connect(user1).transfer(owner.address, await usdtToken.balanceOf(user1.address));
  }
});
