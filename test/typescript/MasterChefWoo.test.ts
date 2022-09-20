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
import { deployContract, deployMockContract, solidity } from 'ethereum-waffle'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

import { MasterChefWoo, WooSimpleRewarder } from '../../typechain'

use(solidity)

const {
  BigNumber
} = ethers

const ZERO_ADDR = '0x0000000000000000000000000000000000000000'
const WBNB_ADDR = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c'
const ZERO = 0

const BTC_PRICE = 20000
const WOO_PRICE = 0.15

const ONE = BigNumber.from(10).pow(18)
const PRICE_DEC = BigNumber.from(10).pow(8)

describe('WooRouterV3 Integration Tests', () => {
  let owner: SignerWithAddress
  let user: SignerWithAddress

  let masterCW: MasterChefWoo
  let wooSR: WooSimpleRewarder

  before('Deploy Contracts', async () => {
    ;[owner, user] = await ethers.getSigners()
    btcToken = await deployContract(owner, TestERC20TokenArtifact, [])
    wooToken = await deployContract(owner, TestERC20TokenArtifact, [])
    usdtToken = await deployContract(owner, TestERC20TokenArtifact, [])

    wooracle = (await deployContract(owner, WooracleV2Artifact, [])) as WooracleV2

    feeManager = await deployMockContract(owner, IWooFeeManagerArtifact.abi)
    await feeManager.mock.feeRate.returns(0)
    await feeManager.mock.collectFee.returns()
    await feeManager.mock.addRebate.returns()
    await feeManager.mock.quoteToken.returns(usdtToken.address)
  })

  describe('Query Functions', () => {
    let wooPP: WooPPV2
    let wooRouter: WooRouterV3

    beforeEach('Deploy WooRouter', async () => {
      wooPP = (await deployContract(owner, WooPPV2Artifact, [usdtToken.address])) as WooPPV2

      await wooPP.init(wooracle.address, feeManager.address)

      wooRouter = (await deployContract(owner, WooRouterV3Artifact, [WBNB_ADDR, wooPP.address])) as WooRouterV3

      // const threshold = 0
      // const R = BigNumber.from(0)
      // await wooPP.addBaseToken(btcToken.address, threshold, R)
      // await wooPP.addBaseToken(wooToken.address, threshold, R)

      await btcToken.mint(owner.address, ONE.mul(100))
      await usdtToken.mint(owner.address, ONE.mul(5000000))
      await wooToken.mint(owner.address, ONE.mul(10000000))

      await btcToken.approve(wooPP.address, ONE.mul(10))
      await wooPP.deposit(btcToken.address, ONE.mul(10))

      await usdtToken.approve(wooPP.address, ONE.mul(300000))
      await wooPP.deposit(usdtToken.address, ONE.mul(300000))

      await wooracle.postState(
        btcToken.address,
        PRICE_DEC.mul(BTC_PRICE), // price
        utils.parseEther('0.001'), // spread
        utils.parseEther('0.000000001') // coeff
      )

      // await wooracle.postState(
      //   wooToken.address,
      //   PRICE_DEC.mul(15).div(100), // price
      //   utils.parseEther('0.001'),
      //   utils.parseEther('0.000000001')
      // )

      // console.log(await wooracle.state(btcToken.address))
    })

    it('querySwap accuracy1', async () => {
      const btcNum = 1
      const amount = await wooRouter.querySwap(btcToken.address, usdtToken.address, ONE.mul(btcNum))
      const amountNum = Number(utils.formatEther(amount))
      const benchmark = BTC_PRICE * btcNum
      expect(amountNum).to.lessThan(benchmark)
      const slippage = (benchmark - amountNum) / benchmark
      expect(slippage).to.lessThan(0.002)
      console.log('Query selling 1 btc for usdt: ', amountNum, slippage)
    })

    it('querySwap accuracy1_2', async () => {
      const btcNum = 3
      const amount = await wooRouter.querySwap(btcToken.address, usdtToken.address, ONE.mul(btcNum))
      const amountNum = Number(utils.formatEther(amount))
      const benchmark = BTC_PRICE * btcNum
      expect(amountNum).to.lessThan(benchmark)
      const slippage = (benchmark - amountNum) / benchmark
      // expect(slippage).to.lessThan(0.001 * 2.5)
      console.log('Query selling 3 btc for usdt: ', amountNum, slippage)
    })

    it('querySwap accuracy1_3', async () => {
      const btcNum = 10
      const amount = await wooRouter.querySwap(btcToken.address, usdtToken.address, ONE.mul(btcNum))
      const amountNum = Number(utils.formatEther(amount))
      const benchmark = BTC_PRICE * btcNum
      expect(amountNum).to.lessThan(benchmark)
      const slippage = (benchmark - amountNum) / benchmark
      // expect(slippage).to.lessThan(0.001 * 6.5)
      console.log('Query selling 10 btc for usdt: ', amountNum, slippage)
    })

    it('querySwap accuracy2_1', async () => {
      const uAmount = 10000
      const amount = await wooRouter.querySwap(usdtToken.address, btcToken.address, ONE.mul(uAmount))
      const amountNum = Number(utils.formatEther(amount))
      const benchmark = uAmount / BTC_PRICE
      expect(amountNum).to.lessThan(benchmark)
      const slippage = (benchmark - amountNum) / benchmark
      // expect(slippage).to.lessThan(0.002)
      console.log('Query selling 10000 usdt for btc: ', amountNum, slippage)
    })

    it('querySwap accuracy2_2', async () => {
      const uAmount = 100000
      const amount = await wooRouter.querySwap(usdtToken.address, btcToken.address, ONE.mul(uAmount))
      const amountNum = Number(utils.formatEther(amount))
      const benchmark = uAmount / BTC_PRICE
      expect(amountNum).to.lessThan(benchmark)
      const slippage = (benchmark - amountNum) / benchmark
      // expect(slippage).to.lessThan(0.002)
      console.log('Query selling 100000 usdt for btc: ', amountNum, slippage)
    })

    it('querySwap revert1', async () => {
      const btcAmount = 100
      await expect(wooRouter.querySwap(btcToken.address, usdtToken.address, ONE.mul(btcAmount))).to.be.revertedWith(
        'WooPPV2: INSUFF_QUOTE'
      )
    })

    it('querySwap revert2', async () => {
      const uAmount = 300000
      await expect(wooRouter.querySwap(usdtToken.address, btcToken.address, ONE.mul(uAmount))).to.be.revertedWith(
        'WooPPV2: INSUFF_BASE'
      )
    })
  })
})
