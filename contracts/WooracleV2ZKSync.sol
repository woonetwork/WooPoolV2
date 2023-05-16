// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

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

import "./interfaces/IWooracleV2.sol";
import "./interfaces/AggregatorV3Interface.sol";
import "./libraries/TransferHelper.sol";

// OpenZeppelin contracts
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Wooracle V2 contract for ZKSync
contract WooracleV2ZKSync is Ownable, IWooracleV2 {
    /* ----- State variables ----- */

    // 128 + 64 + 64 = 256 bits (slot size)
    struct TokenInfo {
        uint128 price; // as chainlink oracle (e.g. decimal = 8)                zip: 32 bits = (27, 5)
        uint64 coeff; // k: decimal = 18.    18.4 * 1e18                        zip: 16 bits = (11, 5), 2^11 = 2048
        uint64 spread; // s: decimal = 18.   spread <= 2e18   18.4 * 1e18       zip: 16 bits = (11, 5)
    }

    struct CLOracle {
        address oracle;
        uint8 decimal;
        bool cloPreferred;
    }

    mapping(address => TokenInfo) public infos;
    mapping(address => CLOracle) public clOracles;

    address public override quoteToken;
    uint256 public override timestamp;

    uint256 public staleDuration;
    uint64 public bound;

    mapping(address => bool) public isAdmin;

    mapping(uint8 => address) public basesMap;

    constructor() {
        staleDuration = uint256(120); // default: 2 mins
        bound = uint64(1e16); // 1%
    }

    modifier onlyAdmin() {
        require(owner() == msg.sender || isAdmin[msg.sender], "Wooracle: !Admin");
        _;
    }

    /* ----- External Functions ----- */

    function setAdmin(address addr, bool flag) external onlyOwner {
        isAdmin[addr] = flag;
    }

    /// @dev Set the quote token address.
    /// @param _oracle the token address
    function setQuoteToken(address _quote, address _oracle) external onlyAdmin {
        quoteToken = _quote;
        CLOracle storage cloRef = clOracles[_quote];
        cloRef.oracle = _oracle;
        cloRef.decimal = AggregatorV3Interface(_oracle).decimals();
    }

    function setBound(uint64 _bound) external onlyOwner {
        bound = _bound;
    }

    function setCLOracle(
        address token,
        address _oracle,
        bool _cloPreferred
    ) external onlyAdmin {
        CLOracle storage cloRef = clOracles[token];
        cloRef.oracle = _oracle;
        cloRef.decimal = AggregatorV3Interface(_oracle).decimals();
        cloRef.cloPreferred = _cloPreferred;
    }

    function setCloPreferred(address token, bool _cloPreferred) external onlyAdmin {
        CLOracle storage cloRef = clOracles[token];
        cloRef.cloPreferred = _cloPreferred;
    }

    /// @dev Set the staleDuration.
    /// @param newStaleDuration the new stale duration
    function setStaleDuration(uint256 newStaleDuration) external onlyAdmin {
        staleDuration = newStaleDuration;
    }

    function postPrice(
        address, /* base */
        uint128 /* newPrice */
    ) external onlyAdmin {
        revert("NOT SUPPORTED IN ZKSYNC");
    }

    /// @dev Update the base token prices.
    /// @param base the baseToken address
    /// @param newPrice the new prices for the base token
    function postPrice(
        address base,
        uint128 newPrice,
        uint256 _ts
    ) external onlyAdmin {
        infos[base].price = newPrice;
        timestamp = _ts;
    }

    /// @dev batch update baseTokens prices
    /// @param bases list of baseToken address
    /// @param newPrices the updated prices list
    function postPriceList(
        address[] calldata bases,
        uint128[] calldata newPrices,
        uint256 _ts
    ) external onlyAdmin {
        uint256 length = bases.length;
        require(length == newPrices.length, "Wooracle: length_INVALID");

        // TODO: gas optimization:
        // https://ethereum.stackexchange.com/questions/113221/what-is-the-purpose-of-unchecked-in-solidity
        // https://forum.openzeppelin.com/t/a-collection-of-gas-optimisation-tricks/19966
        unchecked {
            for (uint256 i = 0; i < length; i++) {
                infos[bases[i]].price = newPrices[i];
            }
        }

        timestamp = _ts;
    }

    function postState(
        address, /* base */
        uint128, /* newPrice */
        uint64, /* newSpread */
        uint64 /* newCoeff */
    ) external onlyAdmin {
        revert("NOT SUPPORTED IN ZKSYNC");
    }

    /// @dev update the state of the given base token.
    /// @param base baseToken address
    /// @param newPrice the new prices
    /// @param newSpread the new spreads
    /// @param newCoeff the new slippage coefficent
    function postState(
        address base,
        uint128 newPrice,
        uint64 newSpread,
        uint64 newCoeff,
        uint256 _ts
    ) external onlyAdmin {
        _setState(base, newPrice, newSpread, newCoeff);
        timestamp = _ts;
    }

    /// @dev batch update the prices, spreads and slipagge coeffs info.
    /// @param bases list of baseToken address
    /// @param newPrices the prices list
    /// @param newSpreads the spreads list
    /// @param newCoeffs the slippage coefficent list
    function postStateList(
        address[] calldata bases,
        uint128[] calldata newPrices,
        uint64[] calldata newSpreads,
        uint64[] calldata newCoeffs,
        uint256 _ts
    ) external onlyAdmin {
        uint256 length = bases.length;
        unchecked {
            for (uint256 i = 0; i < length; i++) {
                _setState(bases[i], newPrices[i], newSpreads[i], newCoeffs[i]);
            }
        }
        timestamp = _ts;
    }

    /*
        Price logic:
        - woPrice: wooracle price
        - cloPrice: chainlink price

        woFeasible is, price > 0 and price timestamp NOT stale

        when woFeasible && priceWithinBound     -> woPrice, feasible
        when woFeasible && !priceWithinBound    -> woPrice, infeasible
        when !woFeasible && clo_preferred       -> cloPrice, feasible
        when !woFeasible && !clo_preferred      -> cloPrice, infeasible
    */
    function price(address base) public view override returns (uint256 priceOut, bool feasible) {
        uint256 woPrice_ = uint256(infos[base].price);
        uint256 woPriceTimestamp = timestamp;

        (uint256 cloPrice_, ) = _cloPriceInQuote(base, quoteToken);

        bool woFeasible = woPrice_ != 0 && block.timestamp <= (woPriceTimestamp + staleDuration);
        bool woPriceInBound = cloPrice_ == 0 ||
            ((cloPrice_ * (1e18 - bound)) / 1e18 <= woPrice_ && woPrice_ <= (cloPrice_ * (1e18 + bound)) / 1e18);

        if (woFeasible) {
            priceOut = woPrice_;
            feasible = woPriceInBound;
        } else {
            priceOut = clOracles[base].cloPreferred ? cloPrice_ : 0;
            feasible = priceOut != 0;
        }
    }

    /// @notice the price decimal for the specified base token
    function decimals(address base) external view override returns (uint8) {
        uint8 d = clOracles[base].decimal;
        return d != 0 ? d : 8; // why 8 for default?
    }

    function cloPrice(address base) external view override returns (uint256 refPrice, uint256 refTimestamp) {
        return _cloPriceInQuote(base, quoteToken);
    }

    function isWoFeasible(address base) external view override returns (bool) {
        return infos[base].price != 0 && block.timestamp <= (timestamp + staleDuration);
    }

    function syncTS() external onlyAdmin {
        timestamp = block.timestamp;
    }

    function syncTS(uint256 _ts) external onlyAdmin {
        timestamp = _ts;
    }

    function debugTS()
        external
        view
        returns (
            uint256 n,
            uint256 bs,
            uint256 ts,
            bool f
        )
    {
        n = block.number;
        bs = block.timestamp;
        ts = timestamp;
        f = block.timestamp <= (timestamp + staleDuration);
    }

    function woSpread(address base) external view override returns (uint64) {
        return infos[base].spread;
    }

    function woCoeff(address base) external view override returns (uint64) {
        return infos[base].coeff;
    }

    // Wooracle price of the base token
    function woPrice(address base) external view override returns (uint128 priceOut, uint256 priceTimestampOut) {
        priceOut = infos[base].price;
        priceTimestampOut = timestamp;
    }

    function woState(address base) external view override returns (State memory) {
        TokenInfo memory info = infos[base];
        return
            State({
                price: info.price,
                spread: info.spread,
                coeff: info.coeff,
                woFeasible: (info.price != 0 && block.timestamp <= (timestamp + staleDuration))
            });
    }

    function state(address base) external view override returns (State memory) {
        TokenInfo memory info = infos[base];
        (uint256 basePrice, bool feasible) = price(base);
        return State({price: uint128(basePrice), spread: info.spread, coeff: info.coeff, woFeasible: feasible});
    }

    function cloAddress(address base) external view override returns (address clo) {
        clo = clOracles[base].oracle;
    }

    /* ----- Private Functions ----- */
    function _setState(
        address base,
        uint128 newPrice,
        uint64 newSpread,
        uint64 newCoeff
    ) private {
        TokenInfo storage info = infos[base];
        info.price = newPrice;
        info.spread = newSpread;
        info.coeff = newCoeff;
    }

    function _cloPriceInQuote(address fromToken, address toToken)
        private
        view
        returns (uint256 refPrice, uint256 refTimestamp)
    {
        address baseOracle = clOracles[fromToken].oracle;
        if (baseOracle == address(0)) {
            return (0, 0);
        }
        address quoteOracle = clOracles[toToken].oracle;
        uint8 quoteDecimal = clOracles[toToken].decimal;

        (, int256 rawBaseRefPrice, , uint256 baseUpdatedAt, ) = AggregatorV3Interface(baseOracle).latestRoundData();
        (, int256 rawQuoteRefPrice, , uint256 quoteUpdatedAt, ) = AggregatorV3Interface(quoteOracle).latestRoundData();
        uint256 baseRefPrice = uint256(rawBaseRefPrice);
        uint256 quoteRefPrice = uint256(rawQuoteRefPrice);

        // NOTE: Assume wooracle token decimal is same as chainlink token decimal.
        uint256 ceoff = uint256(10)**quoteDecimal;
        refPrice = (baseRefPrice * ceoff) / quoteRefPrice;
        refTimestamp = baseUpdatedAt >= quoteUpdatedAt ? quoteUpdatedAt : baseUpdatedAt;
    }

    /* ----- Zip Related Functions ----- */

    function setBase(uint8 _id, address _base) external onlyAdmin {
        require(getBase(_id) == address(0), "WooracleV2ZKSync: !id_SET_ALREADY");
        basesMap[_id] = _base;
    }

    function getBase(uint8 _id) public view returns (address) {
        address[5] memory CONST_BASES = [
            // mload
            // NOTE: Update token address for different chains
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, // WETH
            0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, // WBTC
            0xcAFcD85D8ca7Ad1e1C6F82F651fA15E33AEfD07b, // WOO
            0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, // USDT
            0x912CE59144191C1204E64559FE8253a0e49E6548 // ARB
        ];

        return _id < CONST_BASES.length ? CONST_BASES[_id] : basesMap[_id];
    }

    // https://docs.soliditylang.org/en/v0.8.12/contracts.html#fallback-function
    // prettier-ignore
    fallback (bytes calldata _input) external onlyAdmin returns (bytes memory _output) {
        /*
            2 bit:  0: post prices,
                    1: post states,
                    2: post prices with local timestamp
                    3: post states with local timestamp
            6 bits: length

            post prices:
               [price] -->
                  base token: 8 bites (1 byte)
                  price data: 32 bits = (27, 5)

            post states:
               [states] -->
                  base token: 8 bites (1 byte)
                  price:      32 bits (4 bytes) = (27, 5)
                  k coeff:    16 bits (2 bytes) = (11, 5)
                  s spread:   16 bits (2 bytes) = (11, 5)

            4 bytes (32bits): timestamp
                MAX: 2^32-1 = 4,294,967,295 = Feb 7, 2106 6:28:15 AM (~83 years away)
        */

        uint256 x = _input.length;
        require(x > 0, "WooracleV2Zip: !calldata");

        uint8 firstByte = uint8(bytes1(_input[0]));
        uint8 op = firstByte >> 6; // 11000000
        uint8 len = firstByte & 0x3F; // 00111111

        if (op == 0 || op == 2) {
            // post prices list
            address base;
            uint128 p;

            for (uint256 i = 0; i < len; ++i) {
                base = getBase(uint8(bytes1(_input[1 + i * 5:1 + i * 5 + 1])));
                p = _price(uint32(bytes4(_input[1 + i * 5 + 1:1 + i * 5 + 5])));
                infos[base].price = p;
            }

            timestamp = (op == 0) ? block.timestamp : uint256(uint32(bytes4(_input[1 + len * 5:1 + len * 5 + 4])));
        } else if (op == 1 || op == 3) {
            // post states list
            address base;
            uint128 p;
            uint64 s;
            uint64 k;

            for (uint256 i = 0; i < len; ++i) {
                base = getBase(uint8(bytes1(_input[1 + i * 9:1 + i * 9 + 1])));
                p = _price(uint32(bytes4(_input[1 + i * 9 + 1:1 + i * 9 + 5])));
                s = _ks(uint16(bytes2(_input[1 + i * 9 + 5:1 + i * 9 + 7])));
                k = _ks(uint16(bytes2(_input[1 + i * 9 + 7:1 + i * 9 + 9])));
                _setState(base, p, s, k);
            }

            timestamp = (op == 0) ? block.timestamp : uint256(uint32(bytes4(_input[1 + len * 9:1 + len * 9 + 4])));
        } else {
            // not supported
        }
    }

    function _price(uint32 b) internal pure returns (uint128) {
        return uint128((b >> 5) * (10**(b & 0x1F))); // 0x1F = 00011111
    }

    function _ks(uint16 b) internal pure returns (uint64) {
        return uint64((b >> 5) * (10**(b & 0x1F)));
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyAdmin {
        if (stuckToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, msg.sender, amount);
        }
    }
}
