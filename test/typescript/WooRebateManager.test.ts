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

import { expect, use } from 'chai'
import { Contract, utils } from 'ethers'
import { ethers } from 'hardhat'
import { deployContract, deployMockContract, MockProvider, solidity } from 'ethereum-waffle'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

import { WooRebateManager, WooAccessManager } from '../../typechain'
import WooAccessManagerArtifact from '../../artifacts/contracts/WooAccessManager.sol/WooAccessManager.json'
import WooRebateManagerArtifact from '../../artifacts/contracts/WooRebateManager.sol/WooRebateManager.json'
import WooRouterV2Artifact from '../../artifacts/contracts/WooRouterV2.sol/WooRouterV2.json'
import WooPPV2Artifact from '../../artifacts/contracts/WooPPV2.sol/WooPPV2.json'
import TestERC20TokenArtifact from '../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json'

use(solidity)

const {
  BigNumber,
  constants: { MaxUint256 },
} = ethers

const ZERO_ADDR = '0x0000000000000000000000000000000000000000'

const ONE = BigNumber.from(10).pow(18)

const REBATE_RATE1 = utils.parseEther('0.1')
const REBATE_RATE2 = utils.parseEther('0.12')

const MOCK_QUERY_SWAP_300U_RETURN = 600  // Assume 300 USDT = 600 WOO
const MOCK_QUERY_SWAP_500U_RETURN = 1000 // Assume 500 USDT = 1000 WOO

describe('WooRebateManager', () => {
  let owner: SignerWithAddress
  let broker: SignerWithAddress

  let rebateManager: WooRebateManager
  let wooAccessManager: WooAccessManager

  let btcToken: Contract
  let usdtToken: Contract
  let wooToken: Contract
  
  let wooPP: Contract
  let wooRouter: Contract

  let args: string[]

  before('Deploy Contracts', async () => {
    [owner, broker] = await ethers.getSigners()
    btcToken = await deployContract(owner, TestERC20TokenArtifact, [])
    usdtToken = await deployContract(owner, TestERC20TokenArtifact, [])
    wooToken = await deployContract(owner, TestERC20TokenArtifact, [])

    wooAccessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager

    wooPP = await deployMockContract(owner, WooPPV2Artifact.abi)
    await wooPP.mock.quoteToken.returns(usdtToken.address)

    wooRouter = await deployMockContract(owner, WooRouterV2Artifact.abi)
    await wooRouter.mock.wooPool.returns(wooPP.address)

    // Only for USDT to WOO
    await wooRouter.mock.querySwap
      .withArgs(usdtToken.address, wooToken.address, 300)
      .returns(MOCK_QUERY_SWAP_300U_RETURN)
    await wooRouter.mock.querySwap
      .withArgs(usdtToken.address, wooToken.address, 500)
      .returns(MOCK_QUERY_SWAP_500U_RETURN)

    await wooRouter.mock.swap
      .withArgs(usdtToken.address, wooToken.address, 300, 0, broker.address, ZERO_ADDR)
      .returns(MOCK_QUERY_SWAP_300U_RETURN)

    args = [usdtToken.address, usdtToken.address,wooAccessManager.address]
  })

  describe('ctor, init & basic func', () => {
    beforeEach('Deploy WooRebateManager', async () => {
      rebateManager = (await deployContract(owner, WooRebateManagerArtifact, args)) as WooRebateManager
    })

    it('Owner', async () => {
      expect(await rebateManager.owner()).to.eq(owner.address)
    })

    it('Init fields', async () => {
      expect(await rebateManager.quoteToken()).to.eq(usdtToken.address)
      expect(await rebateManager.rewardToken()).to.eq(usdtToken.address)
      expect(await rebateManager.accessManager()).to.eq(wooAccessManager.address)
    })

    it('Set rebateRate', async () => {
      expect(await rebateManager.rebateRate(broker.address)).to.eq(0)
      await rebateManager.setRebateRate(broker.address, REBATE_RATE1)
      expect(await rebateManager.rebateRate(broker.address)).to.eq(REBATE_RATE1)
    })

    it('Set rebateRate revert1', async () => {
      await expect(rebateManager.setRebateRate(ZERO_ADDR, REBATE_RATE1)).to.be.revertedWith(
        'WooRebateManager: brokerAddr_ZERO_ADDR'
      )
    })

    it('Set rebateRate revert2', async () => {
      await expect(rebateManager.setRebateRate(broker.address, utils.parseEther('1.000000001'))).to.be.revertedWith(
        'WooRebateManager: INVALID_USER_REWARD_RATE'
      )
    })

    it('Set rebateRate event', async () => {
      await expect(rebateManager.setRebateRate(broker.address, REBATE_RATE1))
        .to.emit(rebateManager, 'RebateRateUpdated')
        .withArgs(broker.address, REBATE_RATE1)

      await expect(rebateManager.setRebateRate(broker.address, REBATE_RATE2))
        .to.emit(rebateManager, 'RebateRateUpdated')
        .withArgs(broker.address, REBATE_RATE2)
    })
  })

  describe('rebate', () => {
    beforeEach('Deploy WooRebateManager', async () => {
      rebateManager = (await deployContract(owner, WooRebateManagerArtifact, args)) as WooRebateManager

      await rebateManager.setWooRouter(wooRouter.address)
      await usdtToken.mint(owner.address, 1000)
      await usdtToken.mint(rebateManager.address, 10000)
    })

    it('addRebate acc1', async () => {
      expect(await usdtToken.balanceOf(owner.address)).to.equal(1000)
      expect(await usdtToken.balanceOf(rebateManager.address)).to.equal(10000)
      expect(await usdtToken.balanceOf(broker.address)).to.equal(0)

      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(0)

      const rebateAmount = 300
      await rebateManager.addRebate(broker.address, rebateAmount)

      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(rebateAmount)

      expect(await usdtToken.balanceOf(owner.address)).to.equal(1000)
      expect(await usdtToken.balanceOf(rebateManager.address)).to.equal(10000)
      expect(await usdtToken.balanceOf(broker.address)).to.equal(0)
    })

    it('pendingRebateInQuote', async () => {
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(0)

      const rebateAmount = 300
      await rebateManager.addRebate(broker.address, rebateAmount)
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(rebateAmount)

      const amount2 = 200
      await rebateManager.addRebate(broker.address, amount2)
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(rebateAmount + amount2)

      const amount3 = 100
      await rebateManager.addRebate(broker.address, amount3)
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(rebateAmount + amount2 + amount3)
    })

    it('pendingRebateInQuote with claim pending', async () => {
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(0)

      const rebateAmount = 300
      await rebateManager.addRebate(broker.address, rebateAmount)
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(rebateAmount)

      const amount2 = 200
      await rebateManager.addRebate(broker.address, amount2)
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(rebateAmount + amount2)

      await rebateManager.connect(broker).claimRebate()

      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(0)
      expect(await usdtToken.balanceOf(rebateManager.address)).to.equal(9500)
    })

    it('pendingRebateInReward', async () => {
      // will auto reset to usdtToken.address after this it
      expect(await rebateManager.rewardToken()).to.equal(usdtToken.address)
      await rebateManager.setRewardToken(wooToken.address)
      expect(await rebateManager.rewardToken()).to.equal(wooToken.address)

      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(0)

      const rebateAmount = 300
      await rebateManager.addRebate(broker.address, rebateAmount)
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(rebateAmount)
      expect(await rebateManager.pendingRebateInReward(broker.address)).to.equal(MOCK_QUERY_SWAP_300U_RETURN)

      const amount2 = 200
      await rebateManager.addRebate(broker.address, amount2)
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(rebateAmount + amount2)
      expect(await rebateManager.pendingRebateInReward(broker.address)).to.equal(MOCK_QUERY_SWAP_500U_RETURN)
    })

    it('claimRebate', async () => {
      expect(await rebateManager.rewardToken()).to.equal(usdtToken.address)
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(0)

      const rebateAmount = 300
      await rebateManager.addRebate(broker.address, rebateAmount)
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(rebateAmount)

      await rebateManager.connect(broker).claimRebate()

      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(0)
      expect(await usdtToken.balanceOf(rebateManager.address)).to.equal(9700)
    })

    it('claimRebate reward as WOO', async () => {
      expect(await rebateManager.rewardToken()).to.equal(usdtToken.address)
      await rebateManager.setRewardToken(wooToken.address)
      expect(await rebateManager.rewardToken()).to.equal(wooToken.address)

      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(0)

      const rebateAmount = 300
      await rebateManager.addRebate(broker.address, rebateAmount)
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(rebateAmount)

      await expect(rebateManager.connect(broker).claimRebate())
        .to.emit(rebateManager, 'ClaimReward')
        .withArgs(broker.address, MOCK_QUERY_SWAP_300U_RETURN)

      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(0)
      expect(await usdtToken.balanceOf(rebateManager.address)).to.equal(10000) // Balance not change cause is a mock function
    })

    it('claimRebate event', async () => {
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(0)

      const rebateAmount = 300
      await rebateManager.addRebate(broker.address, rebateAmount)
      expect(await rebateManager.pendingRebateInQuote(broker.address)).to.equal(rebateAmount)

      await expect(rebateManager.connect(broker).claimRebate())
        .to.emit(rebateManager, 'ClaimReward')
        .withArgs(broker.address, rebateAmount)
    })
  })
})


describe('WooRebateManager Access Control', () => {
  let owner: SignerWithAddress
  let admin: SignerWithAddress
  let user: SignerWithAddress
  let broker: SignerWithAddress

  let wooRebateManager: WooRebateManager
  let wooAccessManager: WooAccessManager
  let newWooAccessManager: WooAccessManager

  let usdtToken: Contract
  let wooToken: Contract

  let wooPP: Contract
  let newWooPP: Contract
  let wooRouter: Contract
  let newWooRouter: Contract

  const mintUSDT = BigNumber.from(30000)

  let onlyOwnerRevertedMessage: string
  let onlyAdminRevertedMessage: string

  before(async () => {
    [owner, admin, user, broker] = await ethers.getSigners()
    usdtToken = await deployContract(owner, TestERC20TokenArtifact, [])
    wooToken = await deployContract(owner, TestERC20TokenArtifact, [])

    wooAccessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager
    await wooAccessManager.setRebateAdmin(admin.address, true)
    newWooAccessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager

    wooPP = await deployMockContract(owner, WooPPV2Artifact.abi)
    await wooPP.mock.quoteToken.returns(usdtToken.address)
    newWooPP = await deployMockContract(owner, WooPPV2Artifact.abi)
    await newWooPP.mock.quoteToken.returns(usdtToken.address)

    wooRouter = await deployMockContract(owner, WooRouterV2Artifact.abi)
    await wooRouter.mock.wooPool.returns(wooPP.address)
    newWooRouter = await deployMockContract(owner, WooRouterV2Artifact.abi)
    await newWooRouter.mock.wooPool.returns(newWooPP.address)

    wooRebateManager = (await deployContract(owner, WooRebateManagerArtifact, [
      usdtToken.address,
      wooToken.address,
      wooAccessManager.address,
    ])) as WooRebateManager

    await usdtToken.mint(wooRebateManager.address, mintUSDT)

    onlyOwnerRevertedMessage = 'Ownable: caller is not the owner'
    onlyAdminRevertedMessage = 'WooRebateManager: !admin'
  })

  it('Only admin able to setRebateRate', async () => {
    let newRate = ONE.div(BigNumber.from(10))
    expect(await wooRebateManager.rebateRate(broker.address)).to.eq(BigNumber.from(0))
    expect(await wooAccessManager.isRebateAdmin(user.address)).to.eq(false)
    await expect(wooRebateManager.connect(user).setRebateRate(broker.address, newRate)).to.be.revertedWith(
      onlyAdminRevertedMessage
    )
    expect(await wooRebateManager.rebateRate(broker.address)).to.eq(BigNumber.from(0))

    expect(await wooAccessManager.isRebateAdmin(admin.address)).to.eq(true)
    await wooRebateManager.connect(admin).setRebateRate(broker.address, newRate)
    expect(await wooRebateManager.rebateRate(broker.address)).to.eq(newRate)

    newRate = newRate.div(BigNumber.from(10))
    await wooRebateManager.connect(owner).setRebateRate(broker.address, newRate)
    expect(await wooRebateManager.rebateRate(broker.address)).to.eq(newRate)
  })

  it('Only admin able to setWooRouter', async () => {
    expect(await wooAccessManager.isRebateAdmin(user.address)).to.eq(false)
    await expect(wooRebateManager.connect(user).setWooRouter(newWooRouter.address)).to.be.revertedWith(onlyAdminRevertedMessage)

    expect(await wooAccessManager.isRebateAdmin(admin.address)).to.eq(true)
    await wooRebateManager.connect(admin).setWooRouter(newWooRouter.address)

    await wooRebateManager.connect(owner).setWooRouter(wooRouter.address)
  })

  it('Only owner able to setAccessManager', async () => {
    expect(await wooRebateManager.accessManager()).to.eq(wooAccessManager.address)
    await expect(wooRebateManager.connect(user).setAccessManager(newWooAccessManager.address)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    )

    await expect(wooRebateManager.connect(admin).setAccessManager(newWooAccessManager.address)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    )

    await wooRebateManager.connect(owner).setAccessManager(newWooAccessManager.address)
    expect(await wooRebateManager.accessManager()).to.eq(newWooAccessManager.address)
  })

  it('Only owner able to inCaseTokenGotStuck', async () => {
    await expect(wooRebateManager.connect(user).inCaseTokenGotStuck(usdtToken.address)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    )

    await expect(
      wooRebateManager.connect(admin).inCaseTokenGotStuck(usdtToken.address)
    ).to.be.revertedWith(onlyOwnerRevertedMessage)

    expect(await usdtToken.balanceOf(owner.address)).to.eq(BigNumber.from(0))
    await wooRebateManager.connect(owner).inCaseTokenGotStuck(usdtToken.address)
    expect(await usdtToken.balanceOf(owner.address)).to.eq(mintUSDT)
  })
})
