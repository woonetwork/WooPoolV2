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

import { WooracleV2_1, WooPPV3, WooRouterV3, WooUsdOFT } from "../../typechain";
import TestERC20TokenArtifact from "../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json";
import WooracleV2_1Artifact from "../../artifacts/contracts/wooracle/WooracleV2_1.sol/WooracleV2_1.json";
import WooPPV3Artifact from "../../artifacts/contracts/WooPPV3/WooPPV3.sol/WooPPV3.json";
import WooUsdOFTArtifact from "../../artifacts/contracts/WooPPV3/WooUsdOFT.sol/WooUsdOFT.json";
import WooRouterV3Artifact from "../../artifacts/contracts/WooPPV3/WooRouterV3.sol/WooRouterV3.json";

use(solidity);

const { BigNumber } = ethers;

const ZERO_ADDR = "0x0000000000000000000000000000000000000000";
const WBNB_ADDR = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";

const BTC_PRICE = 20000;
const WOO_PRICE = 0.15;

const ONE = BigNumber.from(10).pow(18);
const ONE_12 = BigNumber.from(10).pow(12);
const ONE_USD = BigNumber.from(10).pow(6);
const PRICE_DEC = BigNumber.from(10).pow(8);

describe("WooRouterV3 Integration Tests", () => {
  let owner: SignerWithAddress;
  let feeAddr: SignerWithAddress;
  let user: SignerWithAddress;

  let wooracle: WooracleV2;
  let btcToken: Contract;
  let wooToken: Contract;
  let usdtToken: WooUsdOFT;

  before("Deploy ERC20", async () => {
    const signers = await ethers.getSigners();
    owner = signers[0];
    user = signers[1];
    feeAddr = signers[2];
    btcToken = await deployContract(owner, TestERC20TokenArtifact, []);
    wooToken = await deployContract(owner, TestERC20TokenArtifact, []);
    usdtToken = await deployContract(owner, WooUsdOFTArtifact, ["vusd", "vusd", ZERO_ADDR]);

    await usdtToken.setWooPP(owner.address, true);

    wooracle = (await deployContract(owner, WooracleV2_1Artifact, [])) as WooracleV2_1;
  });

  describe("Query Functions", () => {
    let wooPP: WooPPV3;
    let wooRouter: WooRouterV3;

    beforeEach("Deploy WooRouter", async () => {
      wooPP = (await deployContract(owner, WooPPV3Artifact, [wooracle.address, feeAddr.address, usdtToken.address])) as WooPPV3;

      await wooPP.setCapBals(
        [btcToken.address, wooToken.address, usdtToken.address],
        [ONE.mul(1e3), ONE.mul(1e7), ONE_USD.mul(1e8)]);

      await usdtToken.setWooPP(wooPP.address, true);

      wooRouter = (await deployContract(owner, WooRouterV3Artifact, [WBNB_ADDR, wooPP.address])) as WooRouterV3;

      await btcToken.mint(owner.address, ONE.mul(100));
      await usdtToken.mint(owner.address, ONE.mul(5000000));
      await wooToken.mint(owner.address, ONE.mul(10000000));

      await btcToken.approve(wooPP.address, ONE.mul(10));
      await wooPP.deposit(btcToken.address, ONE.mul(10));

      await usdtToken.approve(wooPP.address, ONE.mul(300000));
      await wooPP.deposit(usdtToken.address, ONE.mul(300000));

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

      // console.log(await wooracle.state(btcToken.address))
    });

    it("querySwap accuracy1", async () => {
      const btcNum = 1;
      const amount = await wooRouter.querySwap(btcToken.address, usdtToken.address, ONE.mul(btcNum));
      const amountNum = amount.div(ONE_USD).toNumber();
      const benchmark = BTC_PRICE * btcNum;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.002);
      console.log("Query selling 1 btc for usdt: ", amountNum, slippage);
    });

    it("querySwap accuracy1_2", async () => {
      const btcNum = 3;
      const amount = await wooRouter.querySwap(btcToken.address, usdtToken.address, ONE.mul(btcNum));
      const amountNum = amount.div(ONE_USD).toNumber();
      const benchmark = BTC_PRICE * btcNum;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.005);
      console.log("Query selling 3 btc for usdt: ", amountNum, slippage);
    });

    it("querySwap accuracy1_3", async () => {
      const btcNum = 10;
      const amount = await wooRouter.querySwap(btcToken.address, usdtToken.address, ONE.mul(btcNum));
      const amountNum = amount.div(ONE_USD).toNumber();
      const benchmark = BTC_PRICE * btcNum;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.02);
      console.log("Query selling 10 btc for usdt: ", amountNum, slippage);
    });

    it("querySwap accuracy2_1", async () => {
      const uAmount = 10000;
      const amount = await wooRouter.querySwap(usdtToken.address, btcToken.address, ONE_USD.mul(uAmount));
      const amountNum = Number(utils.formatEther(amount));
      const benchmark = uAmount / BTC_PRICE;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.003);
      console.log("Query selling 10000 usdt for btc: ", amountNum, slippage);
    });

    it("querySwap accuracy2_2", async () => {
      const uAmount = 100000;
      const amount = await wooRouter.querySwap(usdtToken.address, btcToken.address, ONE_USD.mul(uAmount));
      const amountNum = Number(utils.formatEther(amount));
      const benchmark = uAmount / BTC_PRICE;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.003);
      console.log("Query selling 100000 usdt for btc: ", amountNum, slippage);
    });

    it("querySwap revert1", async () => {
      const btcAmount = 100;
      await wooRouter.querySwap(btcToken.address, usdtToken.address, ONE.mul(btcAmount));
    });

    it("querySwap revert2", async () => {
      const uAmount = 300000;
      await expect(wooRouter.querySwap(usdtToken.address, btcToken.address, ONE_USD.mul(uAmount))).to.be.revertedWith(
        "WooPPV3: INSUFF_BALANCE"
      );
    });
  });

  describe("Swap Functions", () => {
    let wooPP: WooPPV3;
    let wooRouter: WooRouterV3;

    beforeEach("Deploy WooRouterV3", async () => {
      wooPP = (await deployContract(owner, WooPPV3Artifact, [wooracle.address, feeAddr.address, usdtToken.address])) as WooPPV3;

      await wooPP.setCapBals(
        [btcToken.address, wooToken.address, usdtToken.address],
        [ONE.mul(1e3), ONE.mul(1e7), ONE_USD.mul(1e8)]);

      await usdtToken.setWooPP(wooPP.address, true);

      wooRouter = (await deployContract(owner, WooRouterV3Artifact, [WBNB_ADDR, wooPP.address])) as WooRouterV3;

      await btcToken.mint(owner.address, ONE.mul(100));
      await usdtToken.mint(owner.address, ONE_USD.mul(5000000));
      await wooToken.mint(owner.address, ONE.mul(10000000));

      await btcToken.approve(wooPP.address, ONE.mul(50));
      await wooPP.deposit(btcToken.address, ONE.mul(50));

      // await usdtToken.approve(wooPP.address, ONE.mul(3000000));
      // await wooPP.deposit(usdtToken.address, ONE.mul(3000000));

      await wooToken.approve(wooPP.address, ONE.mul(3000000));
      await wooPP.deposit(wooToken.address, ONE.mul(3000000));

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

    it("swap btc -> usdt accuracy1", async () => {
      await btcToken.mint(user.address, ONE.mul(1));

      const name = "Swap: btc -> usdt";
      const fromAmount = ONE.mul(1);
      const minToAmount = ONE_USD.mul(BTC_PRICE).mul(998).div(1000);
      const price = BTC_PRICE;
      const minSlippage = 0.002;
      await _testSwap(name, btcToken, usdtToken, fromAmount, minToAmount, price, minSlippage);
    });

    it("swap btc -> usdt accuracy2", async () => {
      await btcToken.mint(user.address, ONE.mul(100));

      const name = "Swap: btc -> usdt";
      const fromAmount = ONE.mul(50);
      const minToAmount = ONE_USD.mul(50).mul(BTC_PRICE).mul(99).div(100);
      const price = BTC_PRICE;
      const minSlippage = 0.01;
      await _testSwap(name, btcToken, usdtToken, fromAmount, minToAmount, price, minSlippage);
    });

    it("swap woo -> usdt accuracy1", async () => {
      await wooToken.mint(user.address, ONE.mul(999999));

      const name = "Swap: woo -> usdt";
      const fromAmount = ONE.mul(10000);
      const minToAmount = ONE_USD.mul(10000).mul(15).div(100).mul(95).div(100);
      const price = WOO_PRICE;
      const minSlippage = 0.035;
      await _testSwap(name, wooToken, usdtToken, fromAmount, minToAmount, price, minSlippage);
    });

    it("Swap: woo -> usdt accuracy2", async () => {
      await wooToken.mint(user.address, ONE.mul(3000000));

      const name = "Swap: woo -> usdt";
      const fromAmount = ONE.mul(200000);
      const minToAmount = ONE_USD.mul(200000).mul(15).div(100).mul(70).div(100);
      const price = WOO_PRICE;
      const minSlippage = 0.3;
      await _testSwap(name, wooToken, usdtToken, fromAmount, minToAmount, price, minSlippage);
    });

    it("swap btc -> woo accuracy1", async () => {
      await btcToken.mint(user.address, ONE.mul(3));

      const name = "Swap: btc -> woo";
      const fromAmount = ONE.mul(1);
      const minToAmount = fromAmount.mul(BTC_PRICE).mul(100).div(15).mul(90).div(100);
      const price = BTC_PRICE / WOO_PRICE;
      const minSlippage = 0.1;
      console.log("minToAmount", utils.formatEther(minToAmount));
      await _testSwap(name, btcToken, wooToken, fromAmount, minToAmount, price, minSlippage);
    });

    it("Swap: btc -> woo accuracy2", async () => {
      await btcToken.mint(user.address, ONE.mul(100));

      const name = "Swap: btc -> woo";
      const fromAmount = ONE.mul(10);
      const minToAmount = fromAmount.mul(BTC_PRICE).mul(100).div(15).mul(80).div(100);
      const price = BTC_PRICE / WOO_PRICE;
      const minSlippage = 0.3;
      await _testSwap(name, btcToken, wooToken, fromAmount, minToAmount, price, minSlippage);
    });

    it("swap usdt -> woo accuracy0", async () => {
      await usdtToken.mint(user.address, ONE.mul(20000));

      const name = "Swap: usdt -> woo";
      const fromAmount = ONE_USD.mul(3000);
      const minToAmount = fromAmount.mul(ONE_12).mul(100).div(15).mul(99).div(100);
      const price = 1.0 / WOO_PRICE;
      const minSlippage = 0.01;
      await _testSwap(name, usdtToken, wooToken, fromAmount, minToAmount, price, minSlippage);
    });

    it("swap usdt -> woo accuracy1", async () => {
      await usdtToken.mint(user.address, ONE.mul(20000));

      const name = "Swap: usdt -> woo";
      const fromAmount = ONE_USD.mul(15000);
      const minToAmount = fromAmount.mul(ONE_12).mul(100).div(15).mul(96).div(100);
      const price = 1.0 / WOO_PRICE;
      const minSlippage = 0.04;
      await _testSwap(name, usdtToken, wooToken, fromAmount, minToAmount, price, minSlippage);
    });

    it("swap usdt -> woo accuracy2", async () => {
      await usdtToken.mint(user.address, ONE.mul(200000));

      const name = "Swap: usdt -> woo";
      const fromAmount = ONE_USD.mul(BTC_PRICE);
      const minToAmount = fromAmount.mul(ONE_12).mul(100).div(15).mul(90).div(100);
      const price = 1.0 / WOO_PRICE;
      const minSlippage = 0.1;
      await _testSwap(name, usdtToken, wooToken, fromAmount, minToAmount, price, minSlippage);
    });

    it("WooRouterV3 swap usdt -> btc accuracy1", async () => {
      await usdtToken.mint(user.address, ONE.mul(200000));

      const name = "Swap: usdt -> btc";
      const fromAmount = ONE_USD.mul(20000);
      const minToAmount = fromAmount.mul(ONE_12).div(BTC_PRICE).mul(995).div(1000);
      const price = 1.0 / BTC_PRICE;
      const minSlippage = 0.003;
      await _testSwap(name, usdtToken, btcToken, fromAmount, minToAmount, price, minSlippage);
    });

    it("WooRouterV3 swap usdt -> btc accuracy2", async () => {
      await usdtToken.mint(user.address, ONE.mul(5000000));

      const name = "Swap: usdt -> btc";
      const fromAmount = ONE_USD.mul(300000);
      const minToAmount = fromAmount.mul(ONE_12).div(BTC_PRICE).mul(99).div(100);
      const price = 1.0 / BTC_PRICE;
      const minSlippage = 0.008;
      await _testSwap(name, usdtToken, btcToken, fromAmount, minToAmount, price, minSlippage);
    });

    // ----- Private test methods ----- //

    async function _testSwap(
      swapName: string,
      token0: Contract,
      token1: Contract,
      fromAmount: BigNumber,
      minToAmount: BigNumber,
      price: number,
      minSlippage: number
    ) {
      const preWooppToken0Amount = await wooPP.poolSize(token0.address);
      const preWooppToken1Amount = await wooPP.poolSize(token1.address);
      const preUserToken0Amount = await token0.balanceOf(user.address);
      const preUserToken1Amount = await token1.balanceOf(user.address);

      await token0.connect(user).approve(wooRouter.address, fromAmount);

      // This is the way to get the tx's return value
      const realToAmount = await wooRouter
        .connect(user)
        .callStatic.swap(token0.address, token1.address, fromAmount, minToAmount, user.address, ZERO_ADDR);

      await wooRouter
        .connect(user)
        .swap(token0.address, token1.address, fromAmount, minToAmount, user.address, ZERO_ADDR);

      const toDec = token1 == usdtToken ? ONE_12 : 1;
      const toNum = Number(utils.formatEther(realToAmount.mul(toDec)));
      const fromDec = token0 == usdtToken ? ONE_12 : 1;
      const fromNum = Number(utils.formatEther(fromAmount.mul(fromDec)));
      const benchmark = price * fromNum;
      expect(toNum).to.lessThan(benchmark);
      const slippage = (benchmark - toNum) / benchmark;
      console.log(`${swapName}: ${fromNum} -> ${toNum} with benchmark ${benchmark} slippage ${slippage}`);
      expect(slippage).to.lessThan(minSlippage);

      const curWooppToken0Amount = await wooPP.poolSize(token0.address);
      const curWooppToken1Amount = await wooPP.poolSize(token1.address);
      const curUserToken0Amount = await token0.balanceOf(user.address);
      const curUserToken1Amount = await token1.balanceOf(user.address);
      if (token0 != usdtToken) {
        expect(curWooppToken0Amount.sub(preWooppToken0Amount)).to.eq(fromAmount);
        expect(preUserToken0Amount.sub(curUserToken0Amount)).to.eq(fromAmount);
      }
      if (token1 != usdtToken) {
        expect(preWooppToken1Amount.sub(curWooppToken1Amount)).to.eq(realToAmount);
        expect(curUserToken1Amount.sub(preUserToken1Amount)).to.eq(realToAmount);
      }
    }
  });

  describe("Try Related Functions", () => {
    let wooPP: WooPPV3;
    let wooRouter: WooRouterV3;

    beforeEach("Deploy WooRouter", async () => {
      wooPP = (await deployContract(owner, WooPPV3Artifact, [wooracle.address, feeAddr.address, usdtToken.address])) as WooPPV3;

      await wooPP.setCapBals(
        [btcToken.address, wooToken.address, usdtToken.address],
        [ONE.mul(1e3), ONE.mul(1e7), ONE_USD.mul(1e8)]);

      await usdtToken.setWooPP(wooPP.address, true);

      await wooPP.setFeeRate(btcToken.address, 100);

      wooRouter = (await deployContract(owner, WooRouterV3Artifact, [WBNB_ADDR, wooPP.address])) as WooRouterV3;

      // await btcToken.mint(owner.address, ONE.mul(100))
      // await usdtToken.mint(owner.address, ONE.mul(5000000))
      // await wooToken.mint(owner.address, ONE.mul(10000000))

      // await btcToken.approve(wooPP.address, ONE.mul(10))
      // await wooPP.deposit(btcToken.address, ONE.mul(10))

      // await usdtToken.approve(wooPP.address, ONE.mul(300000))
      // await wooPP.deposit(usdtToken.address, ONE.mul(300000))

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

      // console.log(await wooracle.state(btcToken.address))
    });

    it("tryQuerySwap accuracy1", async () => {
      const btcNum = 1;

      await wooRouter.querySwap(btcToken.address, usdtToken.address, ONE.mul(btcNum));

      const amount = await wooRouter.tryQuerySwap(btcToken.address, usdtToken.address, ONE.mul(btcNum));
      const amountNum = Number(utils.formatEther(amount.mul(ONE_12)));
      const benchmark = BTC_PRICE * btcNum;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.0021);
      console.log("Query selling 1 btc for usdt: ", amountNum, slippage);
    });

    it("tryQuerySwap accuracy2", async () => {
      const uAmount = 10000;

      await expect(wooRouter.querySwap(usdtToken.address, btcToken.address, ONE_USD.mul(uAmount))).to.be.revertedWith(
        "WooPPV3: INSUFF_BALANCE"
      );

      const amount = await wooRouter.tryQuerySwap(usdtToken.address, btcToken.address, ONE_USD.mul(uAmount));
      const amountNum = Number(utils.formatEther(amount));
      const benchmark = uAmount / BTC_PRICE;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.003);
      console.log("Query selling 10000 usdt for btc: ", amountNum, slippage);
    });

    it("tryQuerySwap accuracy3", async () => {
      const btcNum = 1;

      await expect(wooRouter.querySwap(btcToken.address, wooToken.address, ONE.mul(btcNum))).to.be.revertedWith(
        "WooPPV3: INSUFF_BALANCE"
      );

      const amount = await wooRouter.tryQuerySwap(btcToken.address, wooToken.address, ONE.mul(btcNum));
      const amountNum = Number(utils.formatEther(amount));
      const benchmark = (BTC_PRICE * btcNum) / WOO_PRICE;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.0021);
      console.log("Query selling 1 btc for woo: ", amountNum, slippage);
    });

    it("tryQuerySwap accuracy3_2", async () => {
      await usdtToken.approve(wooPP.address, ONE.mul(150));
      await wooPP.deposit(usdtToken.address, ONE.mul(150));

      const btcNum = 1;

      await expect(wooRouter.querySwap(btcToken.address, wooToken.address, ONE.mul(btcNum))).to.be.revertedWith(
        "WooPPV3: INSUFF_BALANCE"
      );

      const amount = await wooRouter.tryQuerySwap(btcToken.address, wooToken.address, ONE.mul(btcNum));
      const amountNum = Number(utils.formatEther(amount));
      const benchmark = (BTC_PRICE * btcNum) / WOO_PRICE;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.0021);
      console.log("Query selling 1 btc for woo: ", amountNum, slippage);
    });

    it("tryQuerySwap accuracy4", async () => {
      await usdtToken.mint(owner.address, ONE.mul(5000000));
      await wooToken.mint(owner.address, ONE.mul(10000000));

      await wooToken.approve(wooPP.address, ONE.mul(150000));
      await wooPP.deposit(wooToken.address, ONE.mul(150000));

      await usdtToken.approve(wooPP.address, ONE.mul(150000));
      await wooPP.deposit(usdtToken.address, ONE.mul(150000));

      const btcNum = 1;

      const amount1 = await wooRouter.querySwap(btcToken.address, wooToken.address, ONE.mul(btcNum));
      const amount = await wooRouter.tryQuerySwap(btcToken.address, wooToken.address, ONE.mul(btcNum));

      expect(amount1).to.be.eq(amount);
      const amountNum = Number(utils.formatEther(amount));
      const benchmark = (BTC_PRICE * btcNum) / WOO_PRICE;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.0021);
      console.log("Query selling 1 btc for woo: ", amountNum, slippage);
    });

    it("tryQuerySwap accuracy5", async () => {
      await usdtToken.mint(owner.address, ONE.mul(5000000));
      await wooToken.mint(owner.address, ONE.mul(10000000));

      await usdtToken.approve(wooPP.address, ONE.mul(150000));
      await wooPP.deposit(usdtToken.address, ONE.mul(150000));

      const btcNum = 1;

      await expect(wooRouter.querySwap(btcToken.address, wooToken.address, ONE.mul(btcNum))).to.be.revertedWith(
        "WooPPV3: INSUFF_BALANCE"
      );

      const amount = await wooRouter.tryQuerySwap(btcToken.address, wooToken.address, ONE.mul(btcNum));
      const amountNum = Number(utils.formatEther(amount));
      const benchmark = (BTC_PRICE * btcNum) / WOO_PRICE;
      expect(amountNum).to.lessThan(benchmark);
      const slippage = (benchmark - amountNum) / benchmark;
      expect(slippage).to.lessThan(0.0021);
      console.log("Query selling 1 btc for woo: ", amountNum, slippage);
    });
  });
});
