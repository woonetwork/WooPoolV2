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
import { deployContract, deployMockContract, solidity } from "ethereum-waffle";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  WooFeeManager,
  WooRouterV2,
  WooPPV2,
  WooVaultManager,
  WooRebateManager,
  WooAccessManager,
} from "../../typechain";
import WooAccessManagerArtifact from "../../artifacts/contracts/WooAccessManager.sol/WooAccessManager.json";
import WooVaultManagerArtifact from "../../artifacts/contracts/WooVaultManager.sol/WooVaultManager.json";
import WooRebateManagerArtifact from "../../artifacts/contracts/WooRebateManager.sol/WooRebateManager.json";
import WooFeeManagerArtifact from "../../artifacts/contracts/WooFeeManager.sol/WooFeeManager.json";
import WooRouterV2Artifact from "../../artifacts/contracts/WooRouterV2.sol/WooRouterV2.json";
import WooPPV2Artifact from "../../artifacts/contracts/WooPPV2.sol/WooPPV2.json";
import WooracleV2Artifact from "../../artifacts/contracts/WooracleV2.sol/WooracleV2.json";
import TestERC20TokenArtifact from "../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json";

use(solidity);

const {
  BigNumber,
  constants: { MaxUint256 },
} = ethers;

// WooracleV2 price decimals is 8
const BTC_PRICE = 50000 * 1e8;
const WOO_PRICE = 1.2 * 1e8;

const ONE = utils.parseEther("1");

const SWAP_FEE_RATE = utils.parseEther("0.00025"); // 2.5 bps
const BROKER1_REBATE_RATE = utils.parseEther("0.2"); // 20% fee -> 0.5 bps
const BROKER2_REBATE_RATE = utils.parseEther("0.2"); // 20% fee -> 0.5 bps
const VAULT_REWARD_RATE = utils.parseEther("0.8"); // 80%

const VAULT1_WEIGHT = 20;
const VAULT2_WEIGHT = 80;
const TOTAL_WEIGHT = VAULT1_WEIGHT + VAULT2_WEIGHT;

const BASE = utils.parseEther("0.001"); // 1e-3 usdt

const BASE_FEE_RATE = 25;

describe("Rebate Fee Vault Integration Test", () => {
  let owner: SignerWithAddress;
  let user: SignerWithAddress;
  let broker1: SignerWithAddress;
  let broker2: SignerWithAddress;
  let vault1: SignerWithAddress;
  let vault2: SignerWithAddress;
  let treasury: SignerWithAddress;

  let wooracle: Contract;

  let wethToken: Contract;
  let btcToken: Contract;
  let wooToken: Contract;
  let usdtToken: Contract;

  let wooPP: WooPPV2;
  let wooRouter: WooRouterV2;
  let feeManager: WooFeeManager;
  let rebateManager: WooRebateManager;
  let vaultManager: WooVaultManager;
  let accessManager: WooAccessManager;

  before("Deploy Contracts", async () => {
    [owner, user, broker1, broker2, vault1, vault2, treasury] = await ethers.getSigners();
    wethToken = await deployContract(owner, TestERC20TokenArtifact, []);
    btcToken = await deployContract(owner, TestERC20TokenArtifact, []);
    wooToken = await deployContract(owner, TestERC20TokenArtifact, []);
    usdtToken = await deployContract(owner, TestERC20TokenArtifact, []);

    accessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager;

    wooracle = await deployMockContract(owner, WooracleV2Artifact.abi);
    await wooracle.mock.timestamp.returns(BigNumber.from(1634180070));
    await wooracle.mock.state.withArgs(btcToken.address).returns({
      price: BTC_PRICE.toString(),
      spread: utils.parseEther("0.0001"),
      coeff: utils.parseEther("0.000000001"),
      woFeasible: true,
    });
    await wooracle.mock.state.withArgs(wooToken.address).returns({
      price: WOO_PRICE.toString(),
      spread: utils.parseEther("0.002"),
      coeff: utils.parseEther("0.00000005"),
      woFeasible: true,
    });

    await wooracle.mock.decimals.returns(8);
    await wooracle.mock.postPrice.returns();

    console.log(BTC_PRICE.toString());
    console.log(WOO_PRICE.toString());
  });

  beforeEach("Deploy WooPP RebateManager and Vault Manager", async () => {
    rebateManager = (await deployContract(owner, WooRebateManagerArtifact, [
      usdtToken.address,
      wooToken.address,
      accessManager.address,
    ])) as WooRebateManager;

    vaultManager = (await deployContract(owner, WooVaultManagerArtifact, [
      usdtToken.address,
      wooToken.address,
      accessManager.address,
    ])) as WooVaultManager;

    feeManager = (await deployContract(owner, WooFeeManagerArtifact, [
      usdtToken.address,
      rebateManager.address,
      vaultManager.address,
      accessManager.address,
      treasury.address,
    ])) as WooFeeManager;

    wooPP = (await deployContract(owner, WooPPV2Artifact, [usdtToken.address])) as WooPPV2;

    await wooPP.init(wooracle.address, feeManager.address);
    await wooPP.setFeeRate(btcToken.address, BASE_FEE_RATE);
    await wooPP.setFeeRate(wooToken.address, BASE_FEE_RATE);

    wooRouter = (await deployContract(owner, WooRouterV2Artifact, [wethToken.address, wooPP.address])) as WooRouterV2;

    await rebateManager.setWooRouter(wooRouter.address);
    await rebateManager.setRebateRate(broker1.address, BROKER1_REBATE_RATE);
    await rebateManager.setRebateRate(broker2.address, BROKER2_REBATE_RATE);

    await vaultManager.setWooRouter(wooRouter.address);
    await vaultManager.setVaultWeight(vault1.address, VAULT1_WEIGHT);
    await vaultManager.setVaultWeight(vault2.address, VAULT2_WEIGHT);

    await feeManager.setFeeRate(btcToken.address, SWAP_FEE_RATE);
    await feeManager.setFeeRate(wooToken.address, SWAP_FEE_RATE);
    await feeManager.setVaultRewardRate(VAULT_REWARD_RATE);

    await accessManager.setRebateAdmin(feeManager.address, true);

    await btcToken.mint(owner.address, ONE.mul(100));
    await btcToken.approve(wooPP.address, ONE.mul(100));
    await wooPP.deposit(btcToken.address, ONE.mul(100));

    await usdtToken.mint(owner.address, ONE.mul(10000000));
    await usdtToken.approve(wooPP.address, ONE.mul(10000000));
    await wooPP.deposit(usdtToken.address, ONE.mul(10000000));

    await wooToken.mint(owner.address, ONE.mul(10000000));
    await wooToken.approve(wooPP.address, ONE.mul(10000000));
    await wooPP.deposit(wooToken.address, ONE.mul(10000000));

    await btcToken.mint(user.address, utils.parseEther("10"));
    await usdtToken.mint(user.address, utils.parseEther("300000"));
    await wooToken.mint(user.address, utils.parseEther("100000"));
  });

  it("integration test", async () => {
    await wooracle.mock.isAdmin.withArgs(wooPP.address).returns(true);
    console.log("Set WooPP as Wooracle admin", await wooracle.isAdmin(wooPP.address));

    expect(await wooPP.quoteToken()).to.equal(usdtToken.address);
    const quote1 = await wooRouter.querySwap(btcToken.address, usdtToken.address, ONE);

    const vol1 = quote1.mul(ONE.add(SWAP_FEE_RATE)).div(ONE);
    console.log("Rebate rate: broker1 20%=0.5bps, broker2 20%=0.5bps");
    console.log("1 btc -> usdt swap volume: ", utils.formatEther(vol1));

    await btcToken.connect(user).approve(wooRouter.address, ONE.mul(10));

    // Sell 1 btc
    await wooRouter
      .connect(user)
      .swap(btcToken.address, usdtToken.address, ONE.mul(1), 0, user.address, broker1.address);

    _bal("User btc balance: ", btcToken, user.address);
    _bal("User usdt balance: ", usdtToken, user.address);
    _bal("WooPP btc balance: ", btcToken, wooPP.address);
    _bal("WooPP usdt balance: ", usdtToken, wooPP.address);

    _allManagerBal();

    _bal("Broker1 usdt balance: ", usdtToken, broker1.address);
    _bal("Broker2 usdt balance: ", usdtToken, broker2.address);

    _allPendingRebate();

    const quote2 = await wooRouter.querySwap(btcToken.address, usdtToken.address, ONE.mul(3));
    const vol2 = quote2.mul(ONE.add(SWAP_FEE_RATE)).div(ONE);
    console.log("3 btc -> usdt swap volume: ", utils.formatEther(vol2));

    // Sell 3 btcs
    await wooRouter
      .connect(user)
      .swap(btcToken.address, usdtToken.address, ONE.mul(3), 0, user.address, broker2.address);

    _bal("User btc balance: ", btcToken, user.address);
    _bal("User usdt balance: ", usdtToken, user.address);
    _bal("WooPP btc balance: ", btcToken, wooPP.address);
    _bal("WooPP usdt balance: ", usdtToken, wooPP.address);

    _allManagerBal();

    _bal("Broker1 usdt balance: ", usdtToken, broker1.address);
    _bal("Broker2 usdt balance: ", usdtToken, broker2.address);

    _allPendingRebate();

    const fee1 = vol1.mul(SWAP_FEE_RATE).div(ONE);
    const rebate1 = fee1.mul(BROKER1_REBATE_RATE).div(ONE);
    const reward1 = fee1.mul(VAULT_REWARD_RATE).div(ONE);

    const fee2 = vol2.mul(SWAP_FEE_RATE).div(ONE);
    const rebate2 = fee2.mul(BROKER2_REBATE_RATE).div(ONE);
    const reward2 = fee2.mul(VAULT_REWARD_RATE).div(ONE);

    expect(await wooPP.feeAddr()).to.equal(feeManager.address);
    expect(await usdtToken.balanceOf(feeManager.address)).to.equal(0);
    // Claim fee from WooPP
    await wooPP.claimFee();
    expect((await usdtToken.balanceOf(feeManager.address)).div(BASE)).to.equal(fee1.add(fee2).div(BASE));

    expect(await rebateManager.pendingRebate(broker1.address)).to.equal(0);
    expect(await rebateManager.pendingRebate(broker2.address)).to.equal(0);
    await feeManager.addRebates([broker1.address, broker2.address], [rebate1, rebate2]);
    console.log(rebate1.toString());
    console.log(rebate2.toString());
    expect(await rebateManager.pendingRebate(broker1.address)).to.equal(rebate1);
    expect(await rebateManager.pendingRebate(broker2.address)).to.equal(rebate2);

    expect(await usdtToken.balanceOf(rebateManager.address)).to.equal(0);

    // Distribute all the rewards

    expect(await vaultManager.pendingAllReward()).to.equal(0);
    expect(await vaultManager.pendingReward(vault1.address)).to.equal(0);
    expect(await vaultManager.pendingReward(vault2.address)).to.equal(0);

    await feeManager.distributeFees();

    const vaultRewards = reward1.add(reward2);
    const vaultReward1 = vaultRewards.mul(VAULT1_WEIGHT).div(TOTAL_WEIGHT);
    const vaultReward2 = vaultRewards.mul(VAULT2_WEIGHT).div(TOTAL_WEIGHT);
    const pendingAllRewards = await vaultManager.pendingAllReward();
    // Make sure USDT balance in VaultManager is equal to pendingAllRewards
    expect(await usdtToken.balanceOf(vaultManager.address)).to.eq(pendingAllRewards);
    // For calculation round down reason, vaultRewards add 1
    expect(pendingAllRewards.div(BASE)).to.eq(vaultRewards.div(BASE).add(1));

    expect((await vaultManager.pendingReward(vault1.address)).div(BASE)).to.gte(vaultReward1.div(BASE));
    expect((await vaultManager.pendingReward(vault2.address)).div(BASE)).to.gte(vaultReward2.div(BASE));

    expect((await wooToken.balanceOf(vault1.address)).div(BASE)).to.eq(0);
    expect((await wooToken.balanceOf(vault2.address)).div(BASE)).to.eq(0);

    const prevPendingReward = await vaultManager.pendingAllReward();

    await vaultManager.distributeAllReward();

    expect((await vaultManager.pendingAllReward()).div(BASE)).to.eq(0);

    await wooPP.claimFee();
    await feeManager.distributeFees();

    // NOTE: distribute -> swap quote to reward token -> generate a little pending reward
    const newPendingReward = prevPendingReward.mul(SWAP_FEE_RATE).div(ONE).mul(VAULT_REWARD_RATE).div(ONE);
    expect((await vaultManager.pendingAllReward()).div(BASE)).to.eq(newPendingReward.div(BASE));
    expect((await vaultManager.pendingReward(vault1.address)).div(BASE)).to.eq(
      newPendingReward.mul(VAULT1_WEIGHT).div(TOTAL_WEIGHT).div(BASE)
    );
    expect((await vaultManager.pendingReward(vault2.address)).div(BASE)).to.eq(
      newPendingReward.mul(VAULT2_WEIGHT).div(TOTAL_WEIGHT).div(BASE)
    );

    const wooReward1 = await wooRouter.querySwap(usdtToken.address, wooToken.address, vaultReward1);
    expect((await wooToken.balanceOf(vault1.address)).div(BASE)).to.eq(wooReward1.div(BASE));

    const wooReward2 = await wooRouter.querySwap(usdtToken.address, wooToken.address, vaultReward2);
    expect((await wooToken.balanceOf(vault2.address)).div(BASE)).to.eq(wooReward2.div(BASE));

    // Claim the rebate
    expect((await usdtToken.balanceOf(rebateManager.address)).div(BASE)).to.eq(rebate1.add(rebate2).div(BASE));
    expect((await rebateManager.pendingRebate(broker1.address)).div(BASE)).to.eq(rebate1.div(BASE));
    expect((await rebateManager.pendingRebate(broker2.address)).div(BASE)).to.eq(rebate2.div(BASE));
    expect((await usdtToken.balanceOf(broker1.address)).div(BASE)).to.eq(0);
    expect((await usdtToken.balanceOf(broker2.address)).div(BASE)).to.eq(0);
    expect((await wooToken.balanceOf(broker1.address)).div(BASE)).to.eq(0);
    expect((await wooToken.balanceOf(broker2.address)).div(BASE)).to.eq(0);

    await rebateManager.connect(broker1).claimRebate();
    expect((await usdtToken.balanceOf(rebateManager.address)).div(BASE)).to.eq(rebate2.div(BASE));
    expect((await rebateManager.pendingRebate(broker1.address)).div(BASE)).to.eq(0);
    expect((await rebateManager.pendingRebate(broker2.address)).div(BASE)).to.eq(rebate2.div(BASE));
    expect((await usdtToken.balanceOf(broker1.address)).div(BASE)).to.eq(0);
    expect((await usdtToken.balanceOf(broker2.address)).div(BASE)).to.eq(0);
    const wooRebate1 = await wooPP.query(usdtToken.address, wooToken.address, rebate1);
    expect((await wooToken.balanceOf(broker1.address)).div(BASE)).to.eq(wooRebate1.div(BASE));
    expect((await wooToken.balanceOf(broker2.address)).div(BASE)).to.eq(0);

    await rebateManager.connect(broker2).claimRebate();
    expect((await usdtToken.balanceOf(rebateManager.address)).div(BASE)).to.eq(0);
    expect((await rebateManager.pendingRebate(broker1.address)).div(BASE)).to.eq(0);
    expect((await rebateManager.pendingRebate(broker2.address)).div(BASE)).to.eq(0);
    expect((await usdtToken.balanceOf(broker1.address)).div(BASE)).to.eq(0);
    expect((await usdtToken.balanceOf(broker2.address)).div(BASE)).to.eq(0);
    const wooRebate2 = await wooPP.query(usdtToken.address, wooToken.address, rebate2);
    expect((await wooToken.balanceOf(broker1.address)).div(BASE)).to.eq(wooRebate1.div(BASE));
    expect((await wooToken.balanceOf(broker2.address)).div(BASE)).to.eq(wooRebate2.div(BASE));
  });

  async function _allPendingRebate() {
    console.log(
      "Broker1 usdt pending reward: ",
      utils.formatEther(await rebateManager.pendingRebateInQuote(broker1.address))
    );
    console.log(
      "Broker1 woo pending reward: ",
      utils.formatEther(await rebateManager.pendingRebateInReward(broker1.address))
    );
    console.log(
      "Broker2 usdt pending reward: ",
      utils.formatEther(await rebateManager.pendingRebateInQuote(broker2.address))
    );
    console.log(
      "Broker2 woo pending reward: ",
      utils.formatEther(await rebateManager.pendingRebateInReward(broker2.address))
    );
  }

  async function _allManagerBal() {
    _bal("feeManager usdt balance: ", usdtToken, feeManager.address);
    _bal("feeManager woo balance: ", wooToken, feeManager.address);
    _bal("rebateManager usdt balance: ", usdtToken, rebateManager.address);
    _bal("rebateManager woo balance: ", wooToken, rebateManager.address);
    _bal("vaultManager usdt balance: ", usdtToken, vaultManager.address);
    _bal("vaultManager woo balance: ", wooToken, vaultManager.address);
  }

  async function _bal(desc: string, token: Contract, addr: string) {
    console.log(desc, utils.formatEther(await token.balanceOf(addr)));
  }
});
