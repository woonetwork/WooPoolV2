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

import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { deployContract } from "ethereum-waffle";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { WooracleV2, TestChainLink, TestQuoteChainLink } from "../../typechain";
import WooracleV2Artifact from "../../artifacts/contracts/WooracleV2.sol/WooracleV2.json";
import TestChainLinkArtifact from "../../artifacts/contracts/test/TestChainLink.sol/TestChainLink.json";
import TestQuoteChainLinkArtifact from "../../artifacts/contracts/test/TestChainLink.sol/TestQuoteChainLink.json";

const BN_1E18 = BigNumber.from(10).pow(18);
const BN_2E18 = BN_1E18.mul(2);
const BN_1E8 = BigNumber.from(10).pow(8);

const BN_1E16 = BigNumber.from(10).pow(18);
const BN_2E16 = BN_1E16.mul(2);
const ZERO = 0;

async function getCurrentBlockTimestamp() {
  const blockNum = await ethers.provider.getBlockNumber();
  const block = await ethers.provider.getBlock(blockNum);
  return block.timestamp;
}

async function checkWooracleTimestamp(wooracle: WooracleV2) {
  const currentBlockTimestamp = await getCurrentBlockTimestamp();
  expect(await wooracle.timestamp()).to.gte(currentBlockTimestamp);
}

describe("Wooracle", () => {
  let owner: SignerWithAddress;
  let baseToken: SignerWithAddress;

  let wooracle: WooracleV2;
  let chainlinkOne: TestChainLink;
  let chainlinkTwo: TestQuoteChainLink;

  beforeEach(async () => {
    const signers = await ethers.getSigners();
    owner = signers[0];
    baseToken = signers[1];
    wooracle = (await deployContract(owner, WooracleV2Artifact, [])) as WooracleV2;

    chainlinkOne = (await deployContract(owner, TestChainLinkArtifact, [])) as TestChainLink;
    chainlinkTwo = (await deployContract(owner, TestQuoteChainLinkArtifact, [])) as TestQuoteChainLink;
  });

  it("Init with correct owner", async () => {
    expect(await wooracle.owner()).to.eq(owner.address);
  });

  it("setStaleDuration", async () => {
    const newStableDuration = 500;
    await wooracle.setStaleDuration(newStableDuration);
    expect(await wooracle.staleDuration()).to.eq(newStableDuration);
  });

  it("woPrice function", async () => {
    await wooracle.postPrice(baseToken.address, BN_2E18);
    await checkWooracleTimestamp(wooracle);
    const priceResult = await wooracle.woPrice(baseToken.address);
    expect(priceResult[0]).to.eq(BN_2E18);
  });

  it("cloPrice function", async () => {
    const roundData = await chainlinkOne.latestRoundData();
    const price = roundData[1].toNumber();
    expect(price).to.greaterThan(0);

    const btc = "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c";
    const usdt = "0x55d398326f99059fF775485246999027B3197955";
    await wooracle.setQuoteToken(usdt, chainlinkTwo.address);
    await wooracle.setCLOracle(btc, chainlinkOne.address, true);
    const cloPriceResult = await wooracle.cloPrice(btc);
    const cloPriceNow = cloPriceResult[0];
    expect(cloPriceNow.toNumber()).to.eq(2119683140878);
  });

  it("price function", async () => {
    const btc = "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c";
    const usdt = "0x55d398326f99059fF775485246999027B3197955";
    const eth = "0x2170Ed0880ac9A755fd29B2688956BD959F933F8";
    await wooracle.setQuoteToken(usdt, chainlinkTwo.address);
    await wooracle.setCLOracle(btc, chainlinkOne.address, true);
    const priceOneResult = await wooracle.price(btc);
    const priceOne = priceOneResult[0];
    expect(priceOne.toNumber()).to.eq(2119683140878);

    const quoteToken = await wooracle.quoteToken();
    expect(quoteToken).to.eq(usdt);

    await wooracle.postPrice(btc, 2119683140000);
    const [priceTwo, feasibleTwo] = await wooracle.price(btc);
    expect(priceTwo.toNumber()).to.eq(2119683140000);
    expect(feasibleTwo).to.eq(true);

    const woTimestamp = await wooracle.timestamp();
    console.log("Wooracle timestamp:", woTimestamp.toNumber());

    const [priceETH, feasible] = await wooracle.price(eth);
    expect(priceETH.toNumber()).to.eq(0);
    expect(feasible).to.eq(false);
  });

  it("bound function", async () => {
    await wooracle.setBound(BN_2E16);
    expect(await wooracle.bound()).to.eq(BN_2E16);
  });

  it("isWoFeasible function", async () => {
    await wooracle.postPrice(baseToken.address, 0);
    let isWoFeasible = await wooracle.isWoFeasible(baseToken.address);
    expect(isWoFeasible).to.eq(false);

    await wooracle.postPrice(baseToken.address, BN_2E18);
    isWoFeasible = await wooracle.isWoFeasible(baseToken.address);
    expect(isWoFeasible).to.eq(true);

    await wooracle.setStaleDuration(0);
    isWoFeasible = await wooracle.isWoFeasible(baseToken.address);
    expect(isWoFeasible).to.eq(false);
    await wooracle.setStaleDuration(300);
    isWoFeasible = await wooracle.isWoFeasible(baseToken.address);
    expect(isWoFeasible).to.eq(true);
  });

  it("state function", async () => {
    const emptyState = await wooracle.state(baseToken.address);
    expect(emptyState.woFeasible).to.eq(false);
    expect(emptyState.price).to.eq(ZERO);
    expect(emptyState.spread).to.eq(ZERO);
    expect(emptyState.coeff).to.eq(ZERO);
    await wooracle.postState(baseToken.address, BN_1E8, BN_1E18, BN_1E18);
    const oracleState = await wooracle.state(baseToken.address);
    expect(oracleState.woFeasible).to.eq(true);
    expect(oracleState.price).to.eq(BN_1E8);
    expect(oracleState.spread).to.eq(BN_1E18);
    expect(oracleState.coeff).to.eq(BN_1E18);

    const woStateNow = await wooracle.woState(baseToken.address);
    expect(woStateNow.woFeasible).to.eq(true);
    expect(woStateNow.price).to.eq(BN_1E8);
    expect(woStateNow.spread).to.eq(BN_1E18);
    expect(woStateNow.coeff).to.eq(BN_1E18);
  });
});
