// Transported from WooPP.sol on Nov 23, 2021

import BigNumber from 'bignumber.js'
import { WooracleV2 } from '../../typechain'
BigNumber.config({
  EXPONENTIAL_AT: [-80, 80],
  DECIMAL_PLACES: 80,
})

import { Token } from './Token'

const BASE = new BigNumber(10 ** 18)
const FEE_BASE = new BigNumber(10 ** 5)
const ONE = BASE.multipliedBy(1)
const TWO = BASE.multipliedBy(1)

/**
 * Query state from Wooracle:
 * https://arbiscan.io/address/0x37a9dE70b6734dFCA54395D8061d9411D9910739#readContract
 *
 * function state(address base) external returns (State)
 *
 * State {
        uint128 price;
        uint64 spread;
        uint64 coeff;
        bool woFeasible;
    }
 */
export class WooracleState {
  public price!: BigNumber
  public spread!: BigNumber
  public coeff!: BigNumber
  public woFeasible!: Boolean

  public constructor(price: BigNumber, spread: BigNumber, coeff: BigNumber, woFeasible: Boolean) {
    this.price = price
    this.spread = spread
    this.coeff = coeff
    this.woFeasible = woFeasible
  }
}

/**
 * Query data from:
 * https://arbiscan.io/address/0x1f79f8a65e02f8a137ce7f79c038cc44332df448#readContract
 *
 * #tokenInfos(address baseToken)
 *
 *  struct TokenInfo {
      uint192 reserve; // balance reserve
      uint16 feeRate; // 1 in 100000; 10 = 1bp = 0.01%; max = 65535
    }
 */
export class WooppTokenInfo {
  public readonly reserve!: BigNumber
  public readonly feeRate!: BigNumber

  public constructor(
    reserve: BigNumber,
    feeRate: BigNumber,
  ) {
    this.reserve = reserve
    this.feeRate = feeRate
  }
}

/**
 * Query data from: WooPP#decimalInfo
 */
export class DecimalInfo {
  public readonly priceDec!: BigNumber
  public readonly quoteDec!: BigNumber
  public readonly baseDec!: BigNumber

  public constructor(priceDec: BigNumber, quoteDec: BigNumber, baseDec: BigNumber) {
    this.priceDec = priceDec
    this.quoteDec = quoteDec
    this.baseDec = baseDec
  }
}

export class WooPPV2 {
  public readonly quoteToken: Token
  public readonly wooPPAddr: string
  public readonly wooPPVersion: number
  public readonly baseTokens: Set<string>

  public constructor(quoteToken: Token, wooPPAddr: string, wooPPVersion: number) {
    this.quoteToken = quoteToken
    this.wooPPAddr = wooPPAddr
    this.wooPPVersion = wooPPVersion

    this.baseTokens = new Set()
    // current WooPP supported base token list: https://learn.woo.org/woofi/dev-docs/v2-integrate-woofi-as-liquidity-source

    // add base tokens on Arbitrum
    this.baseTokens.add('0x82aF49447D8a07e3bd95BD0d56f35241523fBab1') // weth
    this.baseTokens.add('0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f') // wbtc
    this.baseTokens.add('0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8') // usdc
    this.baseTokens.add('0xcAFcD85D8ca7Ad1e1C6F82F651fA15E33AEfD07b') // woo
  }

  // Query related methods

  // Query swap token1 -> token2
  public query(token1: Token, token2: Token): BigNumber {
    if (this.involvesToken(token1) || this.involvesToken(token2)) {
      // token not supported
      return new BigNumber(0)
    }

    const fromAmount = token1.amount
    let toAmount
    // Three cases:
    // 1. base -> usdt
    // 2. usdt -> base
    // 3. base1 -> usdt -> base2
    try {
      if (this.isQuoteToken(token1)) {
        toAmount = this._tryQuerySellQuote(token2, fromAmount)
      } else if (this.isQuoteToken(token2)) {
        toAmount = this._tryQuerySellBase(token1, fromAmount)
      } else {
        const ret = this._tryQueryBaseToBase(token1, token2, fromAmount)
        toAmount = ret.base2Amount
        const quoteInfo = this.QueryWooppTokenInfo(this.quoteToken)
        if (ret.swapFee > quoteInfo.reserve) {
          // pool balance NOT enough
          return new BigNumber(0)
        }
      }
      const info = this.QueryWooppTokenInfo(token2)
      if (toAmount > info.reserve) {
        // pool balance NOT enough
        return new BigNumber(0)
      }
      return toAmount
    } catch (error) {
      throw error
    }
  }

  public QueryWooppTokenInfo(baseToken: Token): WooppTokenInfo {
    // Steps to do:
    // 1. query the token info from WooPP smart contract (address: this.wooPPAddr)
    // https://arbiscan.io/address/0x1f79f8a65e02f8a137ce7f79c038cc44332df448#code
    // call method: WooPP#tokenInfo(token_address)
    //
    // 2. query the given token info
    return new WooppTokenInfo(ONE, ONE)
  }

  public QueryWooracleState(baseToken: Token) {
    // Steps to do:
    // 1. Wooracle address:
    // https://arbiscan.io/address/0x37a9dE70b6734dFCA54395D8061d9411D9910739#readContract
    //
    // 2.
    // Call wooracle#state(baseToken) to get the token state
    //
    // 3. return the specified token state
    return new WooracleState(ONE, ONE, ONE, true)
  }

  // Query the decimal info from WooPP smart contract
  // https://arbiscan.io/address/0x1f79f8a65e02f8a137ce7f79c038cc44332df448#code
  // call method: WooPP#decimalInfo(address baseToken)
  public QueryDecimalInfo(baseToken: Token) {
    return new DecimalInfo(ONE, ONE, ONE)
  }

  public isBaseToken(token: Token): boolean {
    return token.address in this.baseTokens
  }

  public isQuoteToken(token: Token): boolean {
    return token.address === this.quoteToken.address
  }

  public involvesToken(token: Token): boolean {
    return this.isBaseToken(token) || this.isQuoteToken(token)
  }

  // --------- private method --------- //

  // Query: base token -> quote token
  public _tryQuerySellBase(
    baseToken: Token,
    baseAmount: BigNumber
  ): BigNumber {
    const baseState = this.QueryWooracleState(baseToken);
    const baseTokenInfo = this.QueryWooppTokenInfo(baseToken);
    let quoteAmount = this._calcQuoteAmountSellBase(baseToken, baseAmount, baseState);
    const lpFee = quoteAmount.multipliedBy(baseTokenInfo.feeRate).div(FEE_BASE)
    return quoteAmount.minus(lpFee)
  }

  // Query: quote token -> base token with the given quoteAmount
  public _tryQuerySellQuote(
    baseToken: Token,
    quoteAmount: BigNumber
  ): BigNumber {
    const baseState = this.QueryWooracleState(baseToken);
    const baseTokenInfo = this.QueryWooppTokenInfo(baseToken);
    const lpFee = quoteAmount.times(baseTokenInfo.feeRate).div(BASE)
    const quoteAmountAfterFee = quoteAmount.minus(lpFee)
    return this._calcBaseAmountSellQuote(baseToken, quoteAmountAfterFee, baseState)
  }

  // Query: quote token -> base token with the given quoteAmount
  public _tryQueryBaseToBase(
    baseToken1: Token,
    baseToken2: Token,
    base1Amount: BigNumber
  ): {base2Amount: BigNumber, swapFee: BigNumber} {

    let state1 = this.QueryWooracleState(baseToken1);
    let state2 = this.QueryWooracleState(baseToken2);

    const info1 = this.QueryWooppTokenInfo(baseToken1);
    const info2 = this.QueryWooppTokenInfo(baseToken2);

    const spread = this.max(state1.spread, state2.spread).div(2)
    const feeRate = this.max(info1.feeRate, info2.feeRate);

    state1.spread = spread;
    state2.spread = spread;

    const quoteAmount = this._calcQuoteAmountSellBase(baseToken1, base1Amount, state1)
    const swapFee = quoteAmount.times(feeRate).div(FEE_BASE)
    const base2Amount = this._calcBaseAmountSellQuote(baseToken2, quoteAmount.minus(swapFee), state2)

    return {base2Amount, swapFee};
  }

  private _calcQuoteAmountSellBase(
    baseToken: BigNumber,
    baseAmount: BigNumber,
    state: WooracleState
  ): BigNumber {
    if (!state.woFeasible) {
      return new BigNumber(0);
    }

    const decs = this.QueryDecimalInfo(baseToken)
    const coef = BASE.minus(state.coeff.times(baseAmount).times(state.price).div(decs.baseDec).div(decs.priceDec)).minus(state.spread)
    const quoteAmount = baseAmount.times(decs.quoteDec).times(state.price).div(decs.priceDec).times(coef).div(BASE).div(decs.baseDec)
    return quoteAmount
  }

  private _calcBaseAmountSellQuote(
    baseToken: Token,
    quoteAmount: BigNumber,
    state: WooracleState
  ): BigNumber {
    if (!state.woFeasible) {
      return new BigNumber(0);
    }

    const decs = this.QueryDecimalInfo(baseToken)
    const coef = BASE.minus(quoteAmount.times(state.coeff).div(decs.quoteDec)).minus(state.spread)
    const baseAmount = quoteAmount.times(decs.baseDec).times(decs.priceDec).div(state.price).times(coef).div(BASE).div(decs.quoteDec)
    return baseAmount
  }

  private max(a: BigNumber, b: BigNumber): BigNumber {
    return a.isGreaterThan(b) ? a : b;
  }
}
