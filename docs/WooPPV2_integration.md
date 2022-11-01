# Integrate WooPP V2 as liquidity source

## Contracts

(Same content, but replace: WooPP.sol -> WooPPV2.sol , WooRouter.sol -> WooRouterV3.sol)

(Note same here)

## Supported assets

<tab> Arbitrum

USDC 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8
WBTC 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f
WETH 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
WOO 0xcAFcD85D8ca7Ad1e1C6F82F651fA15E33AEfD07b

### Integrating WOOFi's liquidity

When integrating WOOFi as a liquidity source, the easiest way to interact with WooRouterV3.sol.

Contract addresses:

- Arbitrum
  - [WooRouterV3](https://arbiscan.io/address/0xb130a49065178465931d4f887056328CeA5D723f#code)
  - [WooPPV2](https://arbiscan.io/address/0xc04362CF21E6285E295240E30c056511DF224Cf4#code)

### Interface

```

/// @title Woo router interface (version 2)
/// @notice functions to interface with WooFi swap
interface IWooRouterV2 {
    /* ----- Type declarations ----- */

    enum SwapType {
        WooSwap,
        DodoSwap
    }

    /* ----- Events ----- */

    event WooRouterSwap(
        SwapType swapType,
        address indexed fromToken,
        address indexed toToken,
        uint256 fromAmount,
        uint256 toAmount,
        address from,
        address indexed to,
        address rebateTo
    );

    event WooPoolChanged(address newPool);

    /* ----- Router properties ----- */

    function WETH() external view returns (address);

    function wooPool() external view returns (IWooPPV2);

    /* ----- Main query & swap APIs ----- */

    /// @dev query the amount to swap fromToken -> toToken
    /// @param fromToken the from token
    /// @param toToken the to token
    /// @param fromAmount the amount of fromToken to swap
    /// @return toAmount the predicted amount to receive
    function querySwap(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) external view returns (uint256 toAmount);

    /// @dev swap fromToken -> toToken
    /// @param fromToken the from token
    /// @param toToken the to token
    /// @param fromAmount the amount of fromToken to swap
    /// @param minToAmount the amount of fromToken to swap
    /// @param to the destination address
    /// @param rebateTo the rebate address (optional, can be 0)
    /// @return realToAmount the amount of toToken to receive
    function swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount,
        address payable to,
        address rebateTo
    ) external payable returns (uint256 realToAmount);

    /* ----- 3rd party DEX swap ----- */

    /// @dev swap fromToken -> toToken via an external 3rd swap
    /// @param approveTarget the contract address for token transfer approval
    /// @param swapTarget the contract address for swap
    /// @param fromToken the from token
    /// @param toToken the to token
    /// @param fromAmount the amount of fromToken to swap
    /// @param minToAmount the min amount of swapped toToken
    /// @param to the destination address
    /// @param data call data for external call
    function externalSwap(
        address approveTarget,
        address swapTarget,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount,
        address payable to,
        bytes calldata data
    ) external payable returns (uint256 realToAmount);
}

```

### Sample Integration Code

For query the token price and amount:

```
    /// @dev query the amount to swap fromToken -> toToken
    /// @param fromToken the from token
    /// @param toToken the to token
    /// @param fromAmount the amount of fromToken to swap
    /// @return toAmount the swapped amount to receive
    function querySwap(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) external view returns (uint256 toAmount);
```

Sample code to retrieve quote on selling 1 BTC:

```
wooRouter.querySwap(
  0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c, // btcb token address
  0x55d398326f99059fF775485246999027B3197955, // usdt token address
  1000000000000000000);                       // btcb amount to swap in decimal 18
```

For token swap:

```
    /// @dev swap fromToken -> toToken
    /// @param fromToken the from token
    /// @param toToken the to token
    /// @param fromAmount the amount of fromToken to swap
    /// @param minToAmount the minimum amount of toToken required or the tx reverts
    /// @param to the destination address
    /// @param rebateTo the address to receive rebate (rebate rate is set to 0 now)
    /// @return realToAmount the amount of toToken to receive
    function swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount,
        address payable to,
        address rebateTo
    ) external payable returns (uint256 realToAmount);
```

Sample code to swap 1 BTC to USDT:

```
wooRouter.swap(
  0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c, // btcb token address
  0x55d398326f99059fF775485246999027B3197955, // usdt token address
  1000000000000000000,                        // btcb amount to swap in decimal 18
   990000000000000000,                        // min amount for 1% slippage
  0xd51062A4aF7B76ee0b2893Ef8b52aCC155393E3D, // the address to receive the swap fund
  0);                                         // the rebate address
```

### WooFi Offchain Integration

For offchain code to integrate WooFi, please contact us and we have the technical engineer help migration integration code to Golang, Typescript, Javascript, etc.
