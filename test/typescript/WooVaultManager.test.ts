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
import { Contract } from 'ethers'
import { ethers } from 'hardhat'
import { deployContract, deployMockContract, solidity } from 'ethereum-waffle'
// import IWooPP from '../build/IWooPP.json'
// import IWooVaultManager from '../build/IWooVaultManager.json'
// import TestToken from '../build/TestToken.json'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

import { WooVaultManager, WooAccessManager } from '../../typechain'
import WooAccessManagerArtifact from '../../artifacts/contracts/WooAccessManager.sol/WooAccessManager.json'
import WooVaultManagerArtifact from '../../artifacts/contracts/WooVaultManager.sol/WooVaultManager.json'
import WooRouterV2Artifact from '../../artifacts/contracts/WooRouterV2.sol/WooRouterV2.json'
import WooPPV2Artifact from '../../artifacts/contracts/WooPPV2.sol/WooPPV2.json'
import TestERC20TokenArtifact from '../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json'

use(solidity)

const {
  BigNumber,
  constants: { MaxUint256 },
} = ethers

const ZERO_ADDR = '0x0000000000000000000000000000000000000000'

const MOCK_QUERY_SWAP_100U_RETURN = 200 // Assume 100 USDT = 2000 WOO

describe('WooVaultManager', () => {
  let owner: SignerWithAddress
  let vault1: SignerWithAddress
  let vault2: SignerWithAddress

  let vaultManager: WooVaultManager
  let wooAccessManager: WooAccessManager
  
  let btcToken: Contract
  let usdtToken: Contract
  let wooToken: Contract

  let wooPP: Contract
  let wooRouter: Contract

  before('Deploy Contracts', async () => {
    [owner, vault1, vault2] = await ethers.getSigners()
    btcToken = await deployContract(owner, TestERC20TokenArtifact, [])
    usdtToken = await deployContract(owner, TestERC20TokenArtifact, [])
    wooToken = await deployContract(owner, TestERC20TokenArtifact, [])

    wooAccessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager

    wooPP = await deployMockContract(owner, WooPPV2Artifact.abi)
    await wooPP.mock.quoteToken.returns(usdtToken.address)

    wooRouter = await deployMockContract(owner, WooRouterV2Artifact.abi)
    await wooRouter.mock.wooPool.returns(wooPP.address)

    await usdtToken.mint(owner.address, 10000)
  })

  describe('ctor, init & basic func', () => {
    beforeEach('Deploy WooVaultManager', async () => {
      vaultManager = (await deployContract(owner, WooVaultManagerArtifact, [
        usdtToken.address,
        wooToken.address,
        wooAccessManager.address,
      ])) as WooVaultManager

      await vaultManager.setWooRouter(wooRouter.address)

      await wooRouter.mock.swap
      .withArgs(usdtToken.address, wooToken.address, 100, 0, vaultManager.address, ZERO_ADDR)
      .returns(MOCK_QUERY_SWAP_100U_RETURN)
    })

    it('Owner check', async () => {
      expect(await vaultManager.owner()).to.eq(owner.address)
    })

    it('Init fields', async () => {
      expect(await vaultManager.quoteToken()).to.eq(usdtToken.address)
      expect(await vaultManager.rewardToken()).to.eq(wooToken.address)
      expect(await vaultManager.accessManager()).to.eq(wooAccessManager.address)
    })

    it('Set vaultWeight', async () => {
      expect(await vaultManager.totalWeight()).to.eq(0)

      const weight1 = 100
      expect(await vaultManager.vaultWeight(vault1.address)).to.eq(0)
      await vaultManager.setVaultWeight(vault1.address, weight1)
      expect(await vaultManager.vaultWeight(vault1.address)).to.eq(weight1)
      expect(await vaultManager.totalWeight()).to.eq(weight1)

      const weight2 = 100
      expect(await vaultManager.vaultWeight(vault2.address)).to.eq(0)
      await vaultManager.setVaultWeight(vault2.address, weight2)
      expect(await vaultManager.vaultWeight(vault2.address)).to.eq(weight2)
      expect(await vaultManager.totalWeight()).to.eq(weight1 + weight2)
    })

    it('Set vaultWeight acc2', async () => {
      expect(await vaultManager.totalWeight()).to.eq(0)

      let vaults = await vaultManager.allVaults()
      expect(vaults.length).to.eq(0)

      const weight1 = 100
      expect(await vaultManager.vaultWeight(vault1.address)).to.eq(0)
      await vaultManager.setVaultWeight(vault1.address, weight1)
      expect(await vaultManager.vaultWeight(vault1.address)).to.eq(weight1)
      expect(await vaultManager.totalWeight()).to.eq(weight1)
      vaults = await vaultManager.allVaults()
      expect(vaults.length).to.eq(1)

      const weight2 = 100
      expect(await vaultManager.vaultWeight(vault2.address)).to.eq(0)
      await vaultManager.setVaultWeight(vault2.address, weight2)
      expect(await vaultManager.vaultWeight(vault2.address)).to.eq(weight2)
      expect(await vaultManager.totalWeight()).to.eq(weight1 + weight2)
      vaults = await vaultManager.allVaults()
      expect(vaults.length).to.eq(2)
      expect(vaults[0]).to.eq(vault1.address)
      expect(vaults[1]).to.eq(vault2.address)
    })

    it('Set vaultWeight acc3', async () => {
      expect(await vaultManager.totalWeight()).to.eq(0)

      let vaults = await vaultManager.allVaults()
      expect(vaults.length).to.eq(0)

      const weight1 = 100
      expect(await vaultManager.vaultWeight(vault1.address)).to.eq(0)
      await vaultManager.setVaultWeight(vault1.address, weight1)
      expect(await vaultManager.vaultWeight(vault1.address)).to.eq(weight1)
      expect(await vaultManager.totalWeight()).to.eq(weight1)
      vaults = await vaultManager.allVaults()
      expect(vaults.length).to.eq(1)

      const weight2 = 100
      expect(await vaultManager.vaultWeight(vault2.address)).to.eq(0)
      await vaultManager.setVaultWeight(vault2.address, weight2)
      expect(await vaultManager.vaultWeight(vault2.address)).to.eq(weight2)
      expect(await vaultManager.totalWeight()).to.eq(weight1 + weight2)
      vaults = await vaultManager.allVaults()
      expect(vaults.length).to.eq(2)
      expect(vaults[0]).to.eq(vault1.address)
      expect(vaults[1]).to.eq(vault2.address)

      await vaultManager.setVaultWeight(vault1.address, 0)
      expect(await vaultManager.totalWeight()).to.eq(0 + weight2)
      vaults = await vaultManager.allVaults()
      expect(vaults.length).to.eq(1)
      expect(vaults[0]).to.eq(vault2.address)

      await vaultManager.setVaultWeight(vault1.address, 100)
      expect(await vaultManager.totalWeight()).to.eq(100 + weight2)
      vaults = await vaultManager.allVaults()
      expect(vaults.length).to.eq(2)

      await vaultManager.setVaultWeight(vault1.address, 0)
      await vaultManager.setVaultWeight(vault2.address, 0)
      expect(await vaultManager.totalWeight()).to.eq(0)
      vaults = await vaultManager.allVaults()
      expect(vaults.length).to.eq(0)
    })

    it('Set rebateRate revert1', async () => {
      await expect(vaultManager.setVaultWeight(ZERO_ADDR, 100)).to.be.revertedWith(
        'WooVaultManager: !vaultAddr'
      )
    })

    it('addReward acc1', async () => {
      await vaultManager.setVaultWeight(vault1.address, 20)
      await vaultManager.setVaultWeight(vault2.address, 80)

      expect(await usdtToken.balanceOf(owner.address)).to.equal(10000)
      expect(await usdtToken.balanceOf(vaultManager.address)).to.equal(0)

      const rewardAmount = 300
      await usdtToken.connect(owner).approve(vaultManager.address, rewardAmount)
      await vaultManager.connect(owner).addReward(rewardAmount)

      expect(await usdtToken.balanceOf(owner.address)).to.equal(10000 - rewardAmount)
      expect(await usdtToken.balanceOf(vaultManager.address)).to.equal(rewardAmount)

      expect(await vaultManager.pendingReward(vault1.address)).to.equal((rewardAmount * 20) / 100)
      expect(await vaultManager.pendingReward(vault2.address)).to.equal((rewardAmount * 80) / 100)

      const vaults = await vaultManager.allVaults()
      expect(vaults.length).to.eq(2)
    })

    it('pendingAllReward acc1', async () => {
      await vaultManager.setVaultWeight(vault1.address, 20)
      await vaultManager.setVaultWeight(vault2.address, 80)

      expect(await vaultManager.pendingAllReward()).to.equal(0)

      const rewardAmount = 300
      await usdtToken.connect(owner).approve(vaultManager.address, rewardAmount)
      await vaultManager.connect(owner).addReward(rewardAmount)

      expect(await vaultManager.pendingAllReward()).to.equal(rewardAmount)
      expect(await usdtToken.balanceOf(vaultManager.address)).to.equal(rewardAmount)
    })

    it('pendingReward acc1', async () => {
      await vaultManager.setVaultWeight(vault1.address, 20)
      await vaultManager.setVaultWeight(vault2.address, 80)

      expect(await vaultManager.pendingReward(vault1.address)).to.equal(0)
      expect(await vaultManager.pendingReward(vault2.address)).to.equal(0)

      const rewardAmount = 300
      await usdtToken.connect(owner).approve(vaultManager.address, rewardAmount)
      await vaultManager.connect(owner).addReward(rewardAmount)

      expect(await vaultManager.pendingReward(vault1.address)).to.equal((rewardAmount * 20) / 100)
      expect(await vaultManager.pendingReward(vault2.address)).to.equal((rewardAmount * 80) / 100)
    })

    it('pendingReward revert1', async () => {
      await expect(vaultManager.pendingReward(ZERO_ADDR)).to.be.revertedWith('WooVaultManager: !vaultAddr')
    })

    it('distributeAllReward acc0', async () => {
      const rewardAmount = 100
      await usdtToken.connect(owner).approve(vaultManager.address, rewardAmount)
      await vaultManager.connect(owner).addReward(rewardAmount)

      await vaultManager.distributeAllReward()

      // Nothing happened since no weight (No exception should happen here)
    })

    it('distributeAllReward acc1', async () => {
      await vaultManager.setVaultWeight(vault1.address, 20)
      await vaultManager.setVaultWeight(vault2.address, 80)

      expect(await usdtToken.balanceOf(vaultManager.address)).to.equal(0)
      await vaultManager.distributeAllReward()
    })

    it('distributeAllReward acc2', async () => {
      await vaultManager.setVaultWeight(vault1.address, 20)
      await vaultManager.setVaultWeight(vault2.address, 80)

      const rewardAmount = 100
      await usdtToken.connect(owner).approve(vaultManager.address, rewardAmount)
      await vaultManager.connect(owner).addReward(rewardAmount)

      expect(await vaultManager.pendingReward(vault1.address)).to.equal((rewardAmount * 20) / 100)
      expect(await vaultManager.pendingReward(vault2.address)).to.equal((rewardAmount * 80) / 100)

      await wooToken.mint(vaultManager.address, 200) // mint 200 WOO as reward after WooRouter.swap
      await vaultManager.distributeAllReward()
      expect(await wooToken.balanceOf(vault1.address)).to.equal(40)
      expect(await wooToken.balanceOf(vault2.address)).to.equal(160)
      expect(await wooToken.balanceOf(vaultManager.address)).to.equal(0)
    })

    it('distributeAllReward event', async () => {
      // await wooPP.mock.sellQuote.returns(MOCK_REWARD_AMOUNT)
      await vaultManager.setVaultWeight(vault1.address, 20)
      await vaultManager.setVaultWeight(vault2.address, 80)

      const rewardAmount = 100
      await usdtToken.connect(owner).approve(vaultManager.address, rewardAmount)
      await vaultManager.connect(owner).addReward(rewardAmount)
      expect(await usdtToken.balanceOf(vaultManager.address)).to.equal(100)

      await wooToken.mint(vaultManager.address, 200) // mint 200 WOO as reward after WooRouter.swap
      await expect(vaultManager.distributeAllReward())
        .to.emit(vaultManager, 'RewardDistributed')
        .withArgs(vault1.address, 40)

      await wooToken.mint(vaultManager.address, 200) // mint 200 WOO as reward after WooRouter.swap
      await expect(vaultManager.distributeAllReward())
        .to.emit(vaultManager, 'RewardDistributed')
        .withArgs(vault2.address, 160)

      expect(await wooToken.balanceOf(vaultManager.address)).to.equal(0)
    })
  })
})

describe('WooVaultManager Access Control', () => {
  let owner: SignerWithAddress
  let admin: SignerWithAddress
  let user: SignerWithAddress
  let vault: SignerWithAddress

  let wooVaultManager: WooVaultManager
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
    [owner, admin, user, vault] = await ethers.getSigners()
    usdtToken = await deployContract(owner, TestERC20TokenArtifact, [])
    wooToken = await deployContract(owner, TestERC20TokenArtifact, [])

    wooAccessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager
    await wooAccessManager.setVaultAdmin(admin.address, true)
    newWooAccessManager = (await deployContract(owner, WooAccessManagerArtifact, [])) as WooAccessManager

    wooPP = await deployMockContract(owner, WooPPV2Artifact.abi)
    await wooPP.mock.quoteToken.returns(usdtToken.address)
    newWooPP = await deployMockContract(owner, WooPPV2Artifact.abi)
    await newWooPP.mock.quoteToken.returns(usdtToken.address)

    wooRouter = await deployMockContract(owner, WooRouterV2Artifact.abi)
    await wooRouter.mock.wooPool.returns(wooPP.address)
    newWooRouter = await deployMockContract(owner, WooRouterV2Artifact.abi)
    await newWooRouter.mock.wooPool.returns(newWooPP.address)

    wooVaultManager = (await deployContract(owner, WooVaultManagerArtifact, [
      usdtToken.address,
      wooToken.address,
      wooAccessManager.address,
    ])) as WooVaultManager

    await wooVaultManager.connect(owner).setWooRouter(wooRouter.address)

    await wooRouter.mock.swap
      .withArgs(usdtToken.address, wooToken.address, 100, 0, wooVaultManager.address, ZERO_ADDR)
      .returns(MOCK_QUERY_SWAP_100U_RETURN)

    // Simplify to get 200 WOO while ignore the mintUSDT amount
    await wooRouter.mock.swap
      .withArgs(usdtToken.address, wooToken.address, mintUSDT.add(100), 0, wooVaultManager.address, ZERO_ADDR)
      .returns(MOCK_QUERY_SWAP_100U_RETURN)

    await usdtToken.mint(owner.address, mintUSDT)

    onlyOwnerRevertedMessage = 'Ownable: caller is not the owner'
    onlyAdminRevertedMessage = 'WooVaultManager: !admin'
  })

  it('Only admin able to setVaultWeight', async () => {
    let weight = BigNumber.from(100)
    expect(await wooAccessManager.isVaultAdmin(user.address)).to.eq(false)
    await expect(wooVaultManager.connect(user).setVaultWeight(vault.address, weight)).to.be.revertedWith(
      onlyAdminRevertedMessage
    )

    expect(await wooAccessManager.isVaultAdmin(admin.address)).to.eq(true)
    await wooVaultManager.connect(admin).setVaultWeight(vault.address, weight)
    expect(await wooVaultManager.vaultWeight(vault.address)).to.eq(weight)

    weight = BigNumber.from(200)
    await wooVaultManager.connect(owner).setVaultWeight(vault.address, weight)
    expect(await wooVaultManager.vaultWeight(vault.address)).to.eq(weight)
  })

  it('Only admin able to distributeAllReward', async () => {
    expect(await usdtToken.balanceOf(owner.address)).to.eq(mintUSDT)
    const rewardAmount = BigNumber.from(100)
    await usdtToken.connect(owner).approve(wooVaultManager.address, rewardAmount)
    await wooVaultManager.connect(owner).addReward(rewardAmount)
    expect(await usdtToken.balanceOf(wooVaultManager.address)).to.eq(rewardAmount)

    expect(await wooAccessManager.isVaultAdmin(user.address)).to.eq(false)
    await expect(wooVaultManager.connect(user).distributeAllReward()).to.be.revertedWith(onlyAdminRevertedMessage)

    expect(await wooAccessManager.isVaultAdmin(admin.address)).to.eq(true)
    await wooToken.mint(wooVaultManager.address, 200)
    await wooVaultManager.connect(admin).distributeAllReward()

    await usdtToken.mint(wooVaultManager.address, mintUSDT)
    await wooToken.mint(wooVaultManager.address, 200)
    expect(await usdtToken.balanceOf(wooVaultManager.address)).to.eq(mintUSDT.add(rewardAmount))
    await wooVaultManager.connect(owner).distributeAllReward()
  })

  it('Only admin able to setWooRouter', async () => {
    expect(await wooAccessManager.isVaultAdmin(user.address)).to.eq(false)
    await expect(wooVaultManager.connect(user).setWooRouter(newWooRouter.address)).to.be.revertedWith(onlyAdminRevertedMessage)

    expect(await wooAccessManager.isVaultAdmin(admin.address)).to.eq(true)
    await wooVaultManager.connect(admin).setWooRouter(newWooRouter.address)

    await wooVaultManager.connect(owner).setWooRouter(wooRouter.address)
  })

  it('Only owner able to setAccessManager', async () => {
    expect(await wooVaultManager.accessManager()).to.eq(wooAccessManager.address)
    await expect(wooVaultManager.connect(user).setAccessManager(newWooAccessManager.address)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    )

    await expect(wooVaultManager.connect(admin).setAccessManager(newWooAccessManager.address)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    )

    await wooVaultManager.connect(owner).setAccessManager(newWooAccessManager.address)
    expect(await wooVaultManager.accessManager()).to.eq(newWooAccessManager.address)
  })

  it('Only owner able to inCaseTokenGotStuck', async () => {
    await expect(wooVaultManager.connect(user).inCaseTokenGotStuck(usdtToken.address)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    )

    await expect(wooVaultManager.connect(admin).inCaseTokenGotStuck(usdtToken.address)).to.be.revertedWith(
      onlyOwnerRevertedMessage
    )

    await wooVaultManager.connect(owner).inCaseTokenGotStuck(usdtToken.address)
  })
})
