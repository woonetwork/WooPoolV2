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
import { deployContract, solidity } from 'ethereum-waffle'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

import { WooracleV2, WooPPV2 } from '../../typechain'
import TestERC20TokenArtifact from '../../artifacts/contracts/test/TestERC20Token.sol/TestERC20Token.json'
import WooracleV2Artifact from '../../artifacts/contracts/WooracleV2.sol/WooracleV2.json'
import WooPPV2Artifact from '../../artifacts/contracts/WooPPV2.sol/WooPPV2.json'


use(solidity)

const {
  BigNumber,
} = ethers

const ZERO_ADDR = '0x0000000000000000000000000000000000000000'

const BTC_PRICE = 20000
const FEE = 0.001

const ONE = BigNumber.from(10).pow(18)
const PRICE_DEC = BigNumber.from(10).pow(8)

describe('WooPPV2 Integration tests', () => {
  let owner: SignerWithAddress
  let user1: SignerWithAddress
  let user2: SignerWithAddress
  let feeAddr: SignerWithAddress

  let wooracle: WooracleV2
  let btcToken: Contract
  let wooToken: Contract
  let usdtToken: Contract

  before('Deploy ERC20', async () => {
    ;[owner, user1, user2, feeAddr] = await ethers.getSigners()
    btcToken = await deployContract(owner, TestERC20TokenArtifact, [])
    wooToken = await deployContract(owner, TestERC20TokenArtifact, [])
    usdtToken = await deployContract(owner, TestERC20TokenArtifact, [])

    wooracle = (await deployContract(owner, WooracleV2Artifact, [])) as WooracleV2

    await btcToken.mint(owner.address, ONE.mul(10000))
    await usdtToken.mint(owner.address, ONE.mul(500000000))
    await wooToken.mint(owner.address, ONE.mul(1000000000))
  })

  describe('wooPP query', () => {
    let wooPP: WooPPV2

    beforeEach('Deploy wooPPV2', async () => {
      wooPP = (await deployContract(owner, WooPPV2Artifact, [usdtToken.address])) as WooPPV2

      await wooPP.init(wooracle.address, feeAddr.address)
      await wooPP.setFeeRate(btcToken.address, 100);

      await btcToken.approve(wooPP.address, ONE.mul(10))
      await wooPP.deposit(btcToken.address, ONE.mul(10))

      await usdtToken.approve(wooPP.address, ONE.mul(300000))
      await wooPP.deposit(usdtToken.address, ONE.mul(300000))

      await wooracle.postState(
        btcToken.address,
        PRICE_DEC.mul(BTC_PRICE),       // price
        utils.parseEther('0.001'),      // spread
        utils.parseEther('0.000000001') // coeff
      )

      await wooracle.setAdmin(wooPP.address, true)
    })

    it('querySwap accuracy1', async () => {
      const btcNum = 1
      const amount = await wooPP.querySellBase(btcToken.address, ONE.mul(btcNum))
      const amountNum = Number(utils.formatEther(amount))
      const benchmark = BTC_PRICE * btcNum * (1 - FEE)
      expect(amountNum).to.lessThan(benchmark)
      const slippage = (benchmark - amountNum) / benchmark
      expect(slippage).to.lessThan(0.0012)
      console.log('Query selling 1 btc for usdt: ', amountNum, slippage)
    })

    it('querySwap accuracy1_2', async () => {
      const btcNum = 3
      const amount = await wooPP.querySellBase(btcToken.address, ONE.mul(btcNum))
      const amountNum = Number(utils.formatEther(amount))
      const benchmark = BTC_PRICE * btcNum * (1 - FEE)
      expect(amountNum).to.lessThan(benchmark)
      const slippage = (benchmark - amountNum) / benchmark
      expect(slippage).to.lessThan(0.0012)
      console.log('Query selling 3 btc for usdt: ', amountNum, slippage)
    })

    it('querySwap accuracy1_3', async () => {
      const btcNum = 10
      const amount = await wooPP.querySellBase(btcToken.address, ONE.mul(btcNum))
      const amountNum = Number(utils.formatEther(amount))
      const benchmark = BTC_PRICE * btcNum * (1 - FEE)
      expect(amountNum).to.lessThan(benchmark)
      const slippage = (benchmark - amountNum) / benchmark
      expect(slippage).to.lessThan(0.0013)
      console.log('Query selling 10 btc for usdt: ', amountNum, slippage)
    })

    it('querySwap accuracy2_1', async () => {
      const uAmount = 10000
      const amount = await wooPP.querySellQuote(btcToken.address, ONE.mul(uAmount))
      const amountNum = Number(utils.formatEther(amount))
      const benchmark = uAmount / BTC_PRICE * (1 - FEE)
      expect(amountNum).to.lessThan(benchmark)
      const slippage = (benchmark - amountNum) / benchmark
      expect(slippage).to.lessThan(0.0012)
      console.log('Query selling 10000 usdt for btc: ', amountNum, slippage)
    })

    it('querySwap accuracy2_2', async () => {
      const uAmount = 100000
      const amount = await wooPP.querySellQuote(btcToken.address, ONE.mul(uAmount))
      const amountNum = Number(utils.formatEther(amount))
      const benchmark = uAmount / BTC_PRICE * (1 - FEE)
      expect(amountNum).to.lessThan(benchmark)
      const slippage = (benchmark - amountNum) / benchmark
      expect(slippage).to.lessThan(0.0012)
      console.log('Query selling 100000 usdt for btc: ', amountNum, slippage)
    })

    it('querySwap revert1', async () => {
      const btcAmount = 100
      await expect(
        wooPP.querySellBase(btcToken.address, ONE.mul(btcAmount))
      ).to.be.revertedWith('WooPPV2: INSUFF_QUOTE')
    })

    it('querySwap revert2', async () => {
      const uAmount = 300000
      await expect(
        wooPP.querySellQuote(btcToken.address, ONE.mul(uAmount))
      ).to.be.revertedWith('WooPPV2: INSUFF_BASE')
    })
  })

  describe('wooPP swap', () => {
    let wooPP: WooPPV2

    beforeEach('Deploy WooPPV2', async () => {
      wooPP = (await deployContract(owner, WooPPV2Artifact, [usdtToken.address])) as WooPPV2

      await wooPP.init(wooracle.address, feeAddr.address)
      await wooPP.setFeeRate(btcToken.address, 100);

      await btcToken.mint(owner.address, ONE.mul(10))
      await usdtToken.mint(owner.address, ONE.mul(300000))
      await wooToken.mint(owner.address, ONE.mul(3000000))

      await btcToken.approve(wooPP.address, ONE.mul(10))
      await wooPP.deposit(btcToken.address, ONE.mul(10))

      await usdtToken.approve(wooPP.address, ONE.mul(300000))
      await wooPP.deposit(usdtToken.address, ONE.mul(300000))

      await wooracle.postState(
        btcToken.address,
        PRICE_DEC.mul(BTC_PRICE),       // price
        utils.parseEther('0.001'),      // spread
        utils.parseEther('0.000000001') // coeff
      )

      await wooracle.setAdmin(wooPP.address, true)
    })

    it('sellBase accuracy1', async () => {
      await btcToken.mint(user1.address, ONE.mul(3))
      const preUserUsdt = await usdtToken.balanceOf(user1.address)
      const preUserBtc = await btcToken.balanceOf(user1.address)

      const baseAmount = ONE.mul(1)
      const minQuoteAmount = ONE.mul(BTC_PRICE).mul(99).div(100)

      const preUnclaimedFee = await wooPP.unclaimedFee()
      const preWooppUsdtSize = await wooPP.poolSize(usdtToken.address)
      const preBtcSize = await wooPP.poolSize(btcToken.address)

      const quoteAmount = await wooPP.querySellBase(btcToken.address, baseAmount)

      await btcToken.connect(user1).approve(wooPP.address, baseAmount)
      await btcToken.connect(user1).transfer(wooPP.address, baseAmount)
      await wooPP.connect(user1).sellBase(btcToken.address, baseAmount, minQuoteAmount, user1.address, ZERO_ADDR)

      console.log('swap query quote:', quoteAmount.div(ONE).toString())
      console.log('unclaimed fee:', utils.formatEther(await wooPP.unclaimedFee()))

      const wppUsdtSize = await wooPP.poolSize(usdtToken.address)
      const unclaimedFee = await wooPP.unclaimedFee()
      const fee = unclaimedFee.sub(preUnclaimedFee)
      console.log('balance usdt: ', (await usdtToken.balanceOf(wooPP.address)).div(ONE).toString())
      console.log('pool usdt: ', wppUsdtSize.div(ONE).toString())
      console.log('balance delta: ', preWooppUsdtSize.sub(wppUsdtSize).div(ONE).toString())
      console.log('fee: ', preUnclaimedFee.div(ONE).toString(), unclaimedFee.div(ONE).toString())
      expect(preWooppUsdtSize.sub(wppUsdtSize).sub(fee)).to.eq(quoteAmount)

      const userUsdt = await usdtToken.balanceOf(user1.address)
      expect(preWooppUsdtSize.sub(wppUsdtSize).sub(fee)).to.eq(userUsdt.sub(preUserUsdt))

      const btcSize = await wooPP.poolSize(btcToken.address)
      expect(btcSize.sub(preBtcSize)).to.eq(baseAmount)

      const userBtc = await btcToken.balanceOf(user1.address)
      expect(btcSize.sub(preBtcSize)).to.eq(preUserBtc.sub(userBtc))

      console.log('user1 usdt: ', utils.formatEther(preUserUsdt), utils.formatEther(userUsdt))
      console.log('user1 btc: ', utils.formatEther(preUserBtc), utils.formatEther(userBtc))

      console.log('wooPP usdt: ', utils.formatEther(preWooppUsdtSize), utils.formatEther(wppUsdtSize))
      console.log('wooPP btc: ', utils.formatEther(preBtcSize), utils.formatEther(btcSize))
    })

    it('sellBase accuracy2', async () => {
      await btcToken.mint(user1.address, ONE.mul(3))
      const preUserUsdt = await usdtToken.balanceOf(user1.address)
      const preUserBtc = await btcToken.balanceOf(user1.address)

      const baseAmount = ONE.mul(3)
      const minQuoteAmount = ONE.mul(BTC_PRICE).mul(99).div(100)

      const preUnclaimedFee = await wooPP.unclaimedFee()
      const preWooppUsdtSize = await wooPP.poolSize(usdtToken.address)
      const preBtcSize = await wooPP.poolSize(btcToken.address)

      const quoteAmount = await wooPP.querySellBase(btcToken.address, baseAmount)

      await btcToken.connect(user1).approve(wooPP.address, baseAmount)
      await btcToken.connect(user1).transfer(wooPP.address, baseAmount)
      await wooPP.connect(user1).sellBase(btcToken.address, baseAmount, minQuoteAmount, user1.address, ZERO_ADDR)

      console.log('swap query quote:', quoteAmount.div(ONE).toString())
      console.log('unclaimed fee:', utils.formatEther(await wooPP.unclaimedFee()))

      const wppUsdtSize = await wooPP.poolSize(usdtToken.address)
      const unclaimedFee = await wooPP.unclaimedFee()
      const fee = unclaimedFee.sub(preUnclaimedFee)
      console.log('balance usdt: ', (await usdtToken.balanceOf(wooPP.address)).div(ONE).toString())
      console.log('pool usdt: ', wppUsdtSize.div(ONE).toString())
      console.log('balance delta: ', preWooppUsdtSize.sub(wppUsdtSize).div(ONE).toString())
      console.log('fee: ', preUnclaimedFee.div(ONE).toString(), unclaimedFee.div(ONE).toString())
      expect(preWooppUsdtSize.sub(wppUsdtSize).sub(fee)).to.eq(quoteAmount)

      const userUsdt = await usdtToken.balanceOf(user1.address)
      expect(preWooppUsdtSize.sub(wppUsdtSize).sub(fee)).to.eq(userUsdt.sub(preUserUsdt))

      const btcSize = await wooPP.poolSize(btcToken.address)
      expect(btcSize.sub(preBtcSize)).to.eq(baseAmount)

      const userBtc = await btcToken.balanceOf(user1.address)
      expect(btcSize.sub(preBtcSize)).to.eq(preUserBtc.sub(userBtc))

      console.log('user1 usdt: ', utils.formatEther(preUserUsdt), utils.formatEther(userUsdt))
      console.log('user1 btc: ', utils.formatEther(preUserBtc), utils.formatEther(userBtc))

      console.log('wooPP usdt: ', utils.formatEther(preWooppUsdtSize), utils.formatEther(wppUsdtSize))
      console.log('wooPP btc: ', utils.formatEther(preBtcSize), utils.formatEther(btcSize))
    })

    it('sellBase fail1', async () => {
      expect(wooPP.sellBase(
        btcToken.address,
        ONE,
        0,
        user2.address,
        ZERO_ADDR)
      ).to.be.revertedWith('WooPPV2: BASE_BALANCE_NOT_ENOUGH');

      expect(wooPP.sellBase(
        ZERO_ADDR,
        ONE,
        0,
        user2.address,
        ZERO_ADDR)
      ).to.be.revertedWith('WooPPV2: !baseToken');

      expect(wooPP.sellBase(
        usdtToken.address,
        ONE,
        0,
        user2.address,
        ZERO_ADDR)
      ).to.be.revertedWith('WooPPV2: baseToken==quoteToken');

      expect(wooPP.sellBase(
        btcToken.address,
        ONE,
        0,
        ZERO_ADDR,
        ZERO_ADDR)
      ).to.be.revertedWith('WooPPV2: !to');
    })

    it('sellBase fail2', async () => {
      await btcToken.approve(wooPP.address, ONE)
      await btcToken.transfer(wooPP.address, ONE)
      expect(wooPP.sellBase(
        btcToken.address,
        ONE,
        ONE.mul(BTC_PRICE),
        user2.address,
        ZERO_ADDR)
      ).to.be.revertedWith('WooPPV2: quoteAmount_LT_minQuoteAmount');
    })

    it('sellQuote accuracy1', async () => {
      await btcToken.mint(user1.address, ONE.mul(3))
      await usdtToken.mint(user1.address, ONE.mul(100000))
      const preUserUsdt = await usdtToken.balanceOf(user1.address)
      const preUserBtc = await btcToken.balanceOf(user1.address)

      const quoteAmount = ONE.mul(20000)
      const minBaseAmount = quoteAmount.div(BTC_PRICE).mul(99).div(100)

      const preUnclaimedFee = await wooPP.unclaimedFee()
      const preWooppUsdtSize = await wooPP.poolSize(usdtToken.address)
      const preBtcSize = await wooPP.poolSize(btcToken.address)

      const baseAmount = await wooPP.querySellQuote(btcToken.address, quoteAmount)

      await usdtToken.connect(user1).approve(wooPP.address, quoteAmount)
      await usdtToken.connect(user1).transfer(wooPP.address, quoteAmount)
      await wooPP.connect(user1).sellQuote(btcToken.address, quoteAmount, minBaseAmount, user1.address, ZERO_ADDR)

      console.log('swap query base:', baseAmount.div(ONE).toString())
      console.log('unclaimed fee:', utils.formatEther(await wooPP.unclaimedFee()))

      const wppUsdtSize = await wooPP.poolSize(usdtToken.address)
      const unclaimedFee = await wooPP.unclaimedFee()
      const fee = unclaimedFee.sub(preUnclaimedFee)
      console.log('balance usdt: ', (await usdtToken.balanceOf(wooPP.address)).div(ONE).toString())
      console.log('pool usdt: ', wppUsdtSize.div(ONE).toString())
      console.log('balance delta: ', preWooppUsdtSize.sub(wppUsdtSize).div(ONE).toString())
      console.log('fee: ', preUnclaimedFee.div(ONE).toString(), unclaimedFee.div(ONE).toString())
      expect(wppUsdtSize.sub(preWooppUsdtSize).add(fee)).to.eq(quoteAmount)

      const userUsdt = await usdtToken.balanceOf(user1.address)
      expect(wppUsdtSize.sub(preWooppUsdtSize).add(fee)).to.eq(preUserUsdt.sub(userUsdt))

      const btcSize = await wooPP.poolSize(btcToken.address)
      expect(preBtcSize.sub(btcSize)).to.eq(baseAmount)

      const userBtc = await btcToken.balanceOf(user1.address)
      expect(preBtcSize.sub(btcSize)).to.eq(userBtc.sub(preUserBtc))

      console.log('user1 usdt: ', utils.formatEther(preUserUsdt), utils.formatEther(userUsdt))
      console.log('user1 btc: ', utils.formatEther(preUserBtc), utils.formatEther(userBtc))

      console.log('wooPP usdt: ', utils.formatEther(preWooppUsdtSize), utils.formatEther(wppUsdtSize))
      console.log('wooPP btc: ', utils.formatEther(preBtcSize), utils.formatEther(btcSize))
    })

    it('sellQuote accuracy2', async () => {
      await btcToken.mint(user1.address, ONE.mul(3))
      await usdtToken.mint(user1.address, ONE.mul(100000))
      const preUserUsdt = await usdtToken.balanceOf(user1.address)
      const preUserBtc = await btcToken.balanceOf(user1.address)

      const quoteAmount = ONE.mul(100000)
      const minBaseAmount = quoteAmount.div(BTC_PRICE).mul(99).div(100)

      const preUnclaimedFee = await wooPP.unclaimedFee()
      const preWooppUsdtSize = await wooPP.poolSize(usdtToken.address)
      const preBtcSize = await wooPP.poolSize(btcToken.address)

      const baseAmount = await wooPP.querySellQuote(btcToken.address, quoteAmount)

      await usdtToken.connect(user1).approve(wooPP.address, quoteAmount)
      await usdtToken.connect(user1).transfer(wooPP.address, quoteAmount)
      await wooPP.connect(user1).sellQuote(btcToken.address, quoteAmount, minBaseAmount, user1.address, ZERO_ADDR)

      console.log('swap query base:', baseAmount.div(ONE).toString())
      console.log('unclaimed fee:', utils.formatEther(await wooPP.unclaimedFee()))

      const wppUsdtSize = await wooPP.poolSize(usdtToken.address)
      const unclaimedFee = await wooPP.unclaimedFee()
      const fee = unclaimedFee.sub(preUnclaimedFee)
      console.log('balance usdt: ', (await usdtToken.balanceOf(wooPP.address)).div(ONE).toString())
      console.log('pool usdt: ', wppUsdtSize.div(ONE).toString())
      console.log('balance delta: ', preWooppUsdtSize.sub(wppUsdtSize).div(ONE).toString())
      console.log('fee: ', preUnclaimedFee.div(ONE).toString(), unclaimedFee.div(ONE).toString())
      expect(wppUsdtSize.sub(preWooppUsdtSize).add(fee)).to.eq(quoteAmount)

      const userUsdt = await usdtToken.balanceOf(user1.address)
      expect(wppUsdtSize.sub(preWooppUsdtSize).add(fee)).to.eq(preUserUsdt.sub(userUsdt))

      const btcSize = await wooPP.poolSize(btcToken.address)
      expect(preBtcSize.sub(btcSize)).to.eq(baseAmount)

      const userBtc = await btcToken.balanceOf(user1.address)
      expect(preBtcSize.sub(btcSize)).to.eq(userBtc.sub(preUserBtc))

      console.log('user1 usdt: ', utils.formatEther(preUserUsdt), utils.formatEther(userUsdt))
      console.log('user1 btc: ', utils.formatEther(preUserBtc), utils.formatEther(userBtc))

      console.log('wooPP usdt: ', utils.formatEther(preWooppUsdtSize), utils.formatEther(wppUsdtSize))
      console.log('wooPP btc: ', utils.formatEther(preBtcSize), utils.formatEther(btcSize))
    })

    it('sellQuote fail1', async () => {
      const quoteAmount = ONE.mul(20000)
      expect(wooPP.sellQuote(
        btcToken.address,
        quoteAmount,
        0,
        user2.address,
        ZERO_ADDR)
      ).to.be.revertedWith('WooPPV2: QUOTE_BALANCE_NOT_ENOUGH');

      expect(wooPP.sellQuote(
        ZERO_ADDR,
        quoteAmount,
        0,
        user2.address,
        ZERO_ADDR)
      ).to.be.revertedWith('WooPPV2: !baseToken');

      expect(wooPP.sellQuote(
        usdtToken.address,
        quoteAmount,
        0,
        user2.address,
        ZERO_ADDR)
      ).to.be.revertedWith('WooPPV2: baseToken==quoteToken');

      expect(wooPP.sellQuote(
        btcToken.address,
        quoteAmount,
        0,
        ZERO_ADDR,
        ZERO_ADDR)
      ).to.be.revertedWith('WooPPV2: !to');
    })

    it('sellQuote fail2', async () => {
      const quoteAmount = ONE.mul(20000)
      await usdtToken.approve(wooPP.address, quoteAmount)
      await usdtToken.transfer(wooPP.address, quoteAmount)
      expect(wooPP.sellQuote(
        btcToken.address,
        quoteAmount,
        quoteAmount.div(BTC_PRICE),
        user2.address,
        ZERO_ADDR)
      ).to.be.revertedWith('WooPPV2: baseAmount_LT_minBaseAmount');
    })

    it('balance accuracy', async () => {
      const bal1 = await wooPP.balance(usdtToken.address)
      const bal2 = await wooPP.balance(btcToken.address)
      expect(bal1).to.be.eq(ONE.mul(300000))
      expect(bal2).to.be.eq(ONE.mul(10))

      await btcToken.transfer(wooPP.address, ONE)

      expect(await wooPP.balance(btcToken.address)).to.be.eq(bal2.add(ONE))
    })

    it('balance failure', async () => {
      await expect(wooPP.balance(ZERO_ADDR)).to.be.revertedWith('WooPPV2: !BALANCE')
      console.log(await wooPP.balance(wooToken.address))
    })

    it('poolSize accuracy', async () => {
      const bal1 = await wooPP.poolSize(usdtToken.address)
      const bal2 = await wooPP.poolSize(btcToken.address)
      expect(bal1).to.be.eq(ONE.mul(300000))
      expect(bal2).to.be.eq(ONE.mul(10))

      await btcToken.transfer(wooPP.address, ONE)

      expect(await wooPP.balance(btcToken.address)).to.be.eq(bal2.add(ONE))

      expect(await wooPP.poolSize(btcToken.address)).to.be.not.eq(bal2.add(ONE))
      expect(await wooPP.poolSize(btcToken.address)).to.be.eq(bal2)
    })

  })

  describe('wooPP admins', () => {
    let wooPP: WooPPV2

    beforeEach('Deploy WooPPV2', async () => {
      wooPP = (await deployContract(owner, WooPPV2Artifact, [usdtToken.address])) as WooPPV2

      await wooPP.init(wooracle.address, feeAddr.address)
      await wooPP.setFeeRate(btcToken.address, 100);

      await btcToken.mint(owner.address, ONE.mul(10))
      await usdtToken.mint(owner.address, ONE.mul(300000))
      await wooToken.mint(owner.address, ONE.mul(3000000))

      await btcToken.approve(wooPP.address, ONE.mul(10))
      await wooPP.deposit(btcToken.address, ONE.mul(10))

      await usdtToken.approve(wooPP.address, ONE.mul(300000))
      await wooPP.deposit(usdtToken.address, ONE.mul(300000))

      await wooracle.postState(
        btcToken.address,
        PRICE_DEC.mul(BTC_PRICE),       // price
        utils.parseEther('0.001'),      // spread
        utils.parseEther('0.000000001') // coeff
      )

      await wooracle.setAdmin(wooPP.address, true)
    })

    it('deposit accuracy', async () => {
      expect(await wooPP.balance(btcToken.address)).to.be.eq(ONE.mul(10))
      expect(await wooPP.balance(usdtToken.address)).to.be.eq(ONE.mul(300000))

      expect(await wooPP.poolSize(btcToken.address)).to.be.eq(ONE.mul(10))
      expect(await wooPP.poolSize(usdtToken.address)).to.be.eq(ONE.mul(300000))
    })

    it('after swap: poolSize & balance accuracy1', async () => {
      const btcBal = await wooPP.balance(btcToken.address)
      const btcPool = await wooPP.poolSize(btcToken.address)
      expect(btcBal).to.be.eq(btcPool)

      const usdtBal = await wooPP.balance(usdtToken.address)
      const usdtPool = await wooPP.poolSize(usdtToken.address)
      expect(usdtBal).to.be.eq(usdtPool)

      const btcTradeAmount = ONE
      const minToAmount = btcTradeAmount.mul(BTC_PRICE).mul(997).div(1000)

      const realToAmount = await wooPP.querySellBase(btcToken.address, btcTradeAmount)

      await btcToken.transfer(wooPP.address, btcTradeAmount)
      await wooPP.sellBase(btcToken.address, btcTradeAmount, minToAmount, owner.address, ZERO_ADDR)

      const newBtcBal = await wooPP.balance(btcToken.address)
      const newBtcPool = await wooPP.poolSize(btcToken.address)
      expect(btcBal).to.be.eq(btcPool)
      expect(newBtcBal).to.be.eq(btcBal.add(btcTradeAmount))
      expect(newBtcPool).to.be.eq(btcBal.add(btcTradeAmount))

      const newUsdtBal = await wooPP.balance(usdtToken.address)
      const newUsdtPool = await wooPP.poolSize(usdtToken.address)
      const fee = await wooPP.unclaimedFee()
      expect(newUsdtBal).to.be.eq(newUsdtPool)
      expect(newUsdtBal).to.be.eq(usdtBal.sub(realToAmount).sub(fee))
      expect(newUsdtPool).to.be.eq(usdtPool.sub(realToAmount).sub(fee))
    })

    it('after swap: poolSize & balance accuracy2', async () => {
      const btcBal = await wooPP.balance(btcToken.address)
      const btcPool = await wooPP.poolSize(btcToken.address)
      expect(btcBal).to.be.eq(btcPool)

      const usdtBal = await wooPP.balance(usdtToken.address)
      const usdtPool = await wooPP.poolSize(usdtToken.address)
      expect(usdtBal).to.be.eq(usdtPool)

      const btcTradeAmount = ONE
      const minToAmount = btcTradeAmount.mul(BTC_PRICE).mul(997).div(1000)

      const realToAmount = await wooPP.querySellBase(btcToken.address, btcTradeAmount)

      await btcToken.transfer(wooPP.address, btcTradeAmount)
      await wooPP.sellBase(btcToken.address, btcTradeAmount, minToAmount, wooPP.address, ZERO_ADDR)

      const newBtcBal = await wooPP.balance(btcToken.address)
      const newBtcPool = await wooPP.poolSize(btcToken.address)
      expect(btcBal).to.be.eq(btcPool)
      expect(newBtcBal).to.be.eq(btcBal.add(btcTradeAmount))
      expect(newBtcPool).to.be.eq(btcBal.add(btcTradeAmount))

      const newUsdtBal = await wooPP.balance(usdtToken.address)
      const newUsdtPool = await wooPP.poolSize(usdtToken.address)
      const fee = await wooPP.unclaimedFee()

      // NOTE: here the two amount are totally different!
      expect(newUsdtBal).to.not.be.eq(newUsdtPool)
      expect(newUsdtBal).to.be.eq(usdtBal.sub(fee))
      expect(newUsdtPool).to.be.eq(usdtPool.sub(realToAmount).sub(fee))
    })

    it('migrate accuracy', async () => {
      const newPool = (await deployContract(owner, WooPPV2Artifact, [usdtToken.address])) as WooPPV2

      expect(newPool.address).to.not.be.eq(wooPP.address)

      expect(await wooPP.balance(btcToken.address)).to.be.eq(ONE.mul(10))
      expect(await wooPP.balance(usdtToken.address)).to.be.eq(ONE.mul(300000))
      expect(await wooPP.poolSize(btcToken.address)).to.be.eq(ONE.mul(10))
      expect(await wooPP.poolSize(usdtToken.address)).to.be.eq(ONE.mul(300000))

      expect(await newPool.balance(btcToken.address)).to.be.eq(ONE.mul(0))
      expect(await newPool.balance(usdtToken.address)).to.be.eq(ONE.mul(0))
      expect(await newPool.poolSize(btcToken.address)).to.be.eq(ONE.mul(0))
      expect(await newPool.poolSize(usdtToken.address)).to.be.eq(ONE.mul(0))

      await newPool.setAdmin(wooPP.address, true)

      await wooPP.migrateToNewPool(btcToken.address, newPool.address)
      await wooPP.migrateToNewPool(usdtToken.address, newPool.address)

      expect(await wooPP.balance(btcToken.address)).to.be.eq(ONE.mul(0))
      expect(await wooPP.balance(usdtToken.address)).to.be.eq(ONE.mul(0))
      expect(await wooPP.poolSize(btcToken.address)).to.be.eq(ONE.mul(0))
      expect(await wooPP.poolSize(usdtToken.address)).to.be.eq(ONE.mul(0))

      expect(await newPool.balance(btcToken.address)).to.be.eq(ONE.mul(10))
      expect(await newPool.balance(usdtToken.address)).to.be.eq(ONE.mul(300000))
      expect(await newPool.poolSize(btcToken.address)).to.be.eq(ONE.mul(10))
      expect(await newPool.poolSize(usdtToken.address)).to.be.eq(ONE.mul(300000))
    })

  })
})
