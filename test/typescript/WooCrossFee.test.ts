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

import { WooracleV2_1, WooPPV3, WooCrossFee, IntegrationHelper } from "../../typechain";
import TestERC20TokenArtifact from "../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json";
import TestUsdtTokenArtifact from "../../artifacts/contracts/test/TestUsdtToken.sol/TestUsdtToken.json";
import WooracleV2_1Artifact from "../../artifacts/contracts/wooracle/WooracleV2_1.sol/WooracleV2_1.json";
import WooPPV3Artifact from "../../artifacts/contracts/WooPPV3/WooPPV3.sol/WooPPV3.json";
import WooCrossFeeArtifact from "../../artifacts/contracts/WooPPV3/WooCrossFee.sol/WooCrossFee.json";
import WooUsdOFTArtifact from "../../artifacts/contracts/WooPPV3/WooUsdOFT.sol/WooUsdOFT.json";
import IntegrationHelperArtifact from "../../artifacts/contracts/IntegrationHelper.sol/IntegrationHelper.json";

use(solidity);

const { BigNumber } = ethers;

const ZERO_ADDR = "0x0000000000000000000000000000000000000000";
const WBNB_ADDR = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";

const BTC_PRICE = 30000;
const WOO_PRICE = 0.25;

const ONE = BigNumber.from(10).pow(18);
const ONE_12 = BigNumber.from(10).pow(12);
const ONE_USD = BigNumber.from(10).pow(6);
const PRICE_DEC = BigNumber.from(10).pow(8);

describe("WooCrossFee Integration Tests", () => {
  let owner: SignerWithAddress;
  let feeAddr: SignerWithAddress;
  let user: SignerWithAddress;

  let wooracle: WooracleV2_1;
  let btcToken: Contract;
  let wooToken: Contract;
  let usdtToken: Contract;
  let usdOFT: WooUsdOFT;

  let helper: IntegrationHelper;
  let crossFee: WooCrossFee;

  before("Deploy ERC20", async () => {
    const signers = await ethers.getSigners();
    owner = signers[0];
    user = signers[1];
    feeAddr = signers[2];
    btcToken = await deployContract(owner, TestERC20TokenArtifact, []);
    wooToken = await deployContract(owner, TestERC20TokenArtifact, []);
    usdtToken = await deployContract(owner, TestUsdtTokenArtifact, []);
    usdOFT = await deployContract(owner, WooUsdOFTArtifact, ["vusd", "vusd", ZERO_ADDR]);

    await usdOFT.setWooPP(owner.address, true);

    wooracle = (await deployContract(owner, WooracleV2_1Artifact, [])) as WooracleV2_1;

    helper = (await deployContract(owner, IntegrationHelperArtifact,
      [usdOFT.address, [btcToken.address, wooToken.address, usdtToken.address]])) as IntegrationHelper;
  });

  describe("Query Functions", () => {
    let wooPP: WooPPV3;

    beforeEach("Deploy WooCrossFee", async () => {
      wooPP = (await deployContract(owner, WooPPV3Artifact, [wooracle.address, feeAddr.address, usdOFT.address])) as WooPPV3;

      await usdOFT.setWooPP(wooPP.address, true);

      await btcToken.mint(owner.address, ONE.mul(100));
      await usdtToken.mint(owner.address, ONE.mul(5000000));
      await wooToken.mint(owner.address, ONE.mul(10000000));

      await btcToken.approve(wooPP.address, ONE.mul(10));
      await wooPP.deposit(btcToken.address, ONE.mul(10));       // TVL: 300000

      await wooToken.approve(wooPP.address, ONE.mul(1000000));
      await wooPP.deposit(wooToken.address, ONE.mul(1000000));  // TVL: 250000

      await usdtToken.approve(wooPP.address, ONE_USD.mul(300000));
      await wooPP.deposit(usdtToken.address, ONE_USD.mul(300000));  // TVL: 300000

      await wooracle.postState(
        btcToken.address,
        PRICE_DEC.mul(BTC_PRICE), // price
        utils.parseEther("0.001"), // spread
        utils.parseEther("0.000000001") // coeff
      );

      await wooracle.postState(
        wooToken.address,
        PRICE_DEC.mul(25).div(100), // price: 0.25
        utils.parseEther("0.001"),
        utils.parseEther("0.000000001")
      );

      await wooracle.postState(
        usdtToken.address,
        PRICE_DEC, // price: 1.0
        utils.parseEther("0.001"),
        utils.parseEther("0.000000001")
      );

      crossFee = (await deployContract(owner, WooCrossFeeArtifact,
        [wooracle.address, wooPP.address, helper.address])) as WooCrossFee;

      await crossFee.setTargetBalance(ONE_USD.mul(800000));
      await crossFee.setFeeInfo(40, 9900, 6000, 500);
    });

    it("WooCrossFee init", async () => {
      const feeInfo = await crossFee.feeInfo();
      expect(feeInfo.k1).to.be.eq(40);
      expect(feeInfo.k2).to.be.eq(9900);
      expect(feeInfo.maxPercent).to.be.eq(6000);
      expect(feeInfo.minPercent).to.be.eq(500);

      const targetBalance = await crossFee.targetBalance();
      expect(targetBalance).to.be.eq(ONE_USD.mul(800000));

      const curBal = await crossFee.currentBalance();
      console.log("current balance: ", curBal.div(ONE_USD).toNumber());
      expect(curBal).to.be.eq(ONE_USD.mul(850000));
    });

    it("fee accuracy1", async () => {
      const fee = await crossFee.ingressFee(ONE_USD.mul(10000));
      console.log("ingress fee1: ", fee.toNumber());
      expect(fee).to.be.eq(0);

      await crossFee.setTargetBalance(ONE_USD.mul(180*1e4));
      const fee2 = await crossFee.ingressFee(ONE_USD.mul(10000));
      console.log("ingress fee2: ", fee2.toNumber());
      expect(fee2).to.be.eq(8);

      await crossFee.setTargetBalance(ONE_USD.mul(300*1e4));
      const fee3 = await crossFee.ingressFee(ONE_USD.mul(10000));
      console.log("ingress fee3: ", fee3.toNumber());
      expect(fee3).to.be.eq(22);

      await crossFee.setTargetBalance(ONE_USD.mul(500*1e4));
      const fee4 = await crossFee.ingressFee(ONE_USD.mul(10000));
      console.log("ingress fee4: ", fee4.toNumber());
      expect(fee4).to.be.eq(31);

      await crossFee.setTargetBalance(ONE_USD.mul(1000*1e4));
      const fee5 = await crossFee.ingressFee(ONE_USD.mul(10000));
      console.log("ingress fee5: ", fee5.toNumber());
      expect(fee5).to.be.eq(37);

      await crossFee.setTargetBalance(ONE_USD.mul(2000*1e4));
      const fee6 = await crossFee.ingressFee(ONE_USD.mul(10000));
      console.log("ingress fee6: ", fee6.toNumber());
      expect(fee6).to.be.eq(1426);
    });

    it("fee accuracy2", async () => {
      const fee = await crossFee.outgressFee(ONE_USD.mul(10000));
      console.log("outgressFee fee1: ", fee.toNumber());
      expect(fee).to.be.eq(0);

      await crossFee.setTargetBalance(ONE_USD.mul(180 * 1e4));
      const fee2 = await crossFee.outgressFee(ONE_USD.mul(10000));
      console.log("outgressFee fee2: ", fee2.toNumber());
      expect(fee2).to.be.eq(9);

      await crossFee.setTargetBalance(ONE_USD.mul(300 * 1e4));
      const fee3 = await crossFee.outgressFee(ONE_USD.mul(10000));
      console.log("outgressFee fee3: ", fee3.toNumber());
      expect(fee3).to.be.eq(23);

      await crossFee.setTargetBalance(ONE_USD.mul(500 * 1e4));
      const fee4 = await crossFee.outgressFee(ONE_USD.mul(10000));
      console.log("outgressFee fee4: ", fee4.toNumber());
      expect(fee4).to.be.eq(31);

      await crossFee.setTargetBalance(ONE_USD.mul(1000 * 1e4));
      const fee5 = await crossFee.outgressFee(ONE_USD.mul(10000));
      console.log("outgressFee fee5: ", fee5.toNumber());
      expect(fee5).to.be.eq(37);

      await crossFee.setTargetBalance(ONE_USD.mul(2000 * 1e4));
      const fee6 = await crossFee.outgressFee(ONE_USD.mul(10000));
      console.log("outgressFee fee6: ", fee6.toNumber());
      expect(fee6).to.be.eq(1624);
    });

    it("ingress & outgress", async () => {
      await crossFee.setTargetBalance(ONE_USD.mul(100*1e4));
      await crossFee.setFeeInfo(40, 9900, 8000, 500);

      const fee = await crossFee.ingressFee(ONE_USD.mul(10*1e4));
      console.log("ingress fee1: ", fee.toNumber());
      expect(fee).to.be.eq(0);

      const fee2 = await crossFee.outgressFee(ONE_USD.mul(10 * 1e4));
      console.log("outgress fee2: ", fee2.toNumber());
      expect(fee2).to.be.eq(2);

      const fee3 = await crossFee.ingressFee(ONE_USD.mul(20*1e4));
      console.log("ingress fee3: ", fee3.toNumber());
      expect(fee3).to.be.eq(0);

      const fee4 = await crossFee.outgressFee(ONE_USD.mul(20 * 1e4));
      console.log("outgress fee4: ", fee4.toNumber());
      expect(fee4).to.be.eq(8);

      const fee5 = await crossFee.ingressFee(ONE_USD.mul(50 * 1e4));
      console.log("ingress fee5: ", fee5.toNumber());
      expect(fee5).to.be.eq(0);

      const fee6 = await crossFee.outgressFee(ONE_USD.mul(50 * 1e4));
      console.log("outgress fee6: ", fee6.toNumber());
      expect(fee6).to.be.eq(24);
    });
  });
});
