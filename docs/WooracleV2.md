# Intro

> Keep the 1st paragraph

Wooracle V2 is currently testing on Arbitrum (mainnet) with a slightly updated set of APIs.

- Arbitrum WooracleV2 address: [0x962d37fb9d75fe1af9aab323727183e4eae1322d]: https://arbiscan.io/address/0x962d37fb9d75fe1af9aab323727183e4eae1322d#code

### APIs

```
    /**
     * @notice Returns the ChainLink price of the base token / quote token
     * @param the base token address
     * @return the Chainlink price and the price's last-update timestamp
     */
    function cloPrice(address base) external view returns (uint256 price, uint256 timestamp);

    /**
     * @notice Returns the Woo self-posted price of the base token / quote token
     * @param the base token address
     * @return the Wooracle price and the price's last-update timestamp
     */
    function woPrice(address base) external view returns (uint128 price, uint256 timestamp);

    /**
     * @notice Returns the Woo self-posted price if available, otherwise fallback to ChainLink's price.
     * @dev the price is in base token / quote token, and decimal is same as the chainlink
     *   price decimal
     * @param the base token address
     * @return the compositive price and the flag indicating the price is available or not.
     */
    function price(address base) external view returns (uint256 priceNow, bool feasible);

    /**
     * Returns the detailed state of the current base token in Wooracle.
     *
     * struct State {
     *   uint128 price;
     *   uint64 spread;
     *   uint64 coeff;
     *   bool woFeasible;
     * }
     *
     * @param the base token address
     * @return the state
     */
    function state(address base) external view returns (State memory);

```

> > > (Keep the alert note here)

### Contract ABI

ABI could be downloaded here: [WooracleV2 Code](https://arbiscan.io/address/0x962d37fb9d75fe1af9aab323727183e4eae1322d#code)
