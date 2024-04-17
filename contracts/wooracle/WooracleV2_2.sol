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

import "../interfaces/IWooracleV2_2.sol";
import "../interfaces/AggregatorV3Interface.sol";

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

// OpenZeppelin contracts
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Wooracle V2.2 contract for WooPPV2
/// subversion 1 change: no timestamp update for posting price from WooPP.
/// subversion 2 change: support legacy postState utilizing block.timestamp
contract WooracleV2_2 is Ownable, IWooracleV2_2 {
    event Price(uint256 woPrice, uint256 cloPrice, address baseToken, address quoteToken);

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

    struct PriceRange {
        uint128 min;
        uint128 max;
    }

    mapping(address => TokenInfo) public infos;
    mapping(address => CLOracle) public clOracles;
    mapping(address => PriceRange) public priceRanges;

    address public quoteToken;
    uint256 public timestamp;

    uint256 public staleDuration;
    uint64 public bound;

    address public wooPP;

    mapping(address => bool) public isAdmin;
    mapping(address => bool) public isGuardian;

    mapping(uint8 => address) public basesMap;

    constructor() {
        staleDuration = uint256(300); // default: 5 mins
        bound = uint64(1e16); // 1%
    }

    modifier onlyAdmin() {
        require(owner() == msg.sender || isAdmin[msg.sender], "WooracleV2_2: !Admin");
        _;
    }

    modifier onlyGuardian() {
        require(isGuardian[msg.sender], "WooracleV2_2: !Guardian");
        _;
    }

    /* ----- External Functions ----- */

    function setRange(
        address _base,
        uint128 _min,
        uint128 _max
    ) external onlyGuardian {
        PriceRange storage priceRange = priceRanges[_base];
        priceRange.min = _min;
        priceRange.max = _max;
    }

    function setWooPP(address _wooPP) external onlyAdmin {
        wooPP = _wooPP;
    }

    function setAdmin(address _addr, bool _flag) external onlyOwner {
        isAdmin[_addr] = _flag;
    }

    function setGuardian(address _addr, bool _flag) external onlyOwner {
        isGuardian[_addr] = _flag;
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
        address _token,
        address _oracle,
        bool _cloPreferred
    ) external onlyAdmin {
        CLOracle storage cloRef = clOracles[_token];
        cloRef.oracle = _oracle;
        cloRef.decimal = AggregatorV3Interface(_oracle).decimals();
        cloRef.cloPreferred = _cloPreferred;
    }

    function setCloPreferred(address _token, bool _cloPreferred) external onlyAdmin {
        CLOracle storage cloRef = clOracles[_token];
        cloRef.cloPreferred = _cloPreferred;
    }

    /// @dev Set the staleDuration.
    /// @param _staleDuration the new stale duration
    function setStaleDuration(uint256 _staleDuration) external onlyAdmin {
        staleDuration = _staleDuration;
    }

    /// @dev Update the base token prices.
    /// @param _base the baseToken address
    /// @param _price the new prices for the base token
    function postPrice(address _base, uint128 _price) external onlyAdmin {
        // NOTE: update spread before setting a new price
        _updateSpreadForNewPrice(_base, _price);
        infos[_base].price = _price;
        if (msg.sender != wooPP) {
            timestamp = block.timestamp;
        }
    }

    /// @dev Update the base token prices.
    /// @param _base the baseToken address
    /// @param _price the new prices for the base token
    /// @param _ts the manual updated TS
    function postPrice(
        address _base,
        uint128 _price,
        uint256 _ts
    ) external onlyAdmin {
        // NOTE: update spread before setting a new price
        _updateSpreadForNewPrice(_base, _price);
        infos[_base].price = _price;
        timestamp = _ts;
    }

    /// @dev batch update baseTokens prices
    /// @param _bases list of baseToken address
    /// @param _prices the updated prices list
    function postPriceList(
        address[] calldata _bases,
        uint128[] calldata _prices,
        uint256 _ts
    ) external onlyAdmin {
        uint256 length = _bases.length;
        require(length == _prices.length, "WooracleV2_2: length_INVALID");

        for (uint256 i = 0; i < length; i++) {
            // NOTE: update spread before setting a new price
            _updateSpreadForNewPrice(_bases[i], _prices[i]);
            infos[_bases[i]].price = _prices[i];
        }

        timestamp = _ts;
    }

    /// @dev update the state of the given base token.
    /// @param _base baseToken address
    /// @param _price the new prices
    /// @param _spread the new spreads
    /// @param _coeff the new slippage coefficent
    function postState(
        address _base,
        uint128 _price,
        uint64 _spread,
        uint64 _coeff
    ) external onlyAdmin {
        _setState(_base, _price, _spread, _coeff);
        timestamp = block.timestamp;
    }

    /// @dev update the state of the given base token with the offchain timestamp.
    /// @param _base baseToken address
    /// @param _price the new prices
    /// @param _spread the new spreads
    /// @param _coeff the new slippage coefficent
    /// @param _ts the local timestamp
    function postState(
        address _base,
        uint128 _price,
        uint64 _spread,
        uint64 _coeff,
        uint256 _ts
    ) external onlyAdmin {
        _setState(_base, _price, _spread, _coeff);
        timestamp = _ts;
    }

    /// @dev batch update the prices, spreads and slipagge coeffs info.
    /// @param _bases list of baseToken address
    /// @param _prices the prices list
    /// @param _spreads the spreads list
    /// @param _coeffs the slippage coefficent list
    function postStateList(
        address[] calldata _bases,
        uint128[] calldata _prices,
        uint64[] calldata _spreads,
        uint64[] calldata _coeffs,
        uint256 _ts
    ) external onlyAdmin {
        uint256 length = _bases.length;
        for (uint256 i = 0; i < length; i++) {
            _setState(_bases[i], _prices[i], _spreads[i], _coeffs[i]);
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
    function price(address _base) public view returns (uint256 priceOut, bool feasible) {
        uint256 woPrice_ = uint256(infos[_base].price);
        uint256 woPriceTimestamp = timestamp;

        (uint256 cloPrice_, ) = _cloPriceInQuote(_base, quoteToken);

        bool woFeasible = woPrice_ != 0 && block.timestamp <= (woPriceTimestamp + staleDuration);

        // bool woPriceInBound = cloPrice_ == 0 ||
        //     ((cloPrice_ * (1e18 - bound)) / 1e18 <= woPrice_ && woPrice_ <= (cloPrice_ * (1e18 + bound)) / 1e18);
        bool woPriceInBound = cloPrice_ != 0 &&
            ((cloPrice_ * (1e18 - bound)) / 1e18 <= woPrice_ && woPrice_ <= (cloPrice_ * (1e18 + bound)) / 1e18);

        if (woFeasible) {
            priceOut = woPrice_;
            feasible = woPriceInBound;
        } else {
            priceOut = clOracles[_base].cloPreferred ? cloPrice_ : 0;
            feasible = priceOut != 0;
        }

        // Guardian check: min-max
        if (feasible) {
            PriceRange memory range = priceRanges[_base];
            require(priceOut > range.min, "WooracleV2_2: !min");
            require(priceOut < range.max, "WooracleV2_2: !max");
        }
    }

    /// @notice the price decimal for the specified base token
    function decimals(address) external pure returns (uint8) {
        return 8;
    }

    function cloPrice(address _base) external view returns (uint256 refPrice, uint256 refTimestamp) {
        return _cloPriceInQuote(_base, quoteToken);
    }

    function isWoFeasible(address _base) external view override returns (bool) {
        return infos[_base].price != 0 && block.timestamp <= (timestamp + staleDuration);
    }

    function woState(address _base) external view returns (State memory) {
        TokenInfo memory info = infos[_base];
        return
            State({
                price: info.price,
                spread: info.spread,
                coeff: info.coeff,
                woFeasible: (info.price != 0 && block.timestamp <= (timestamp + staleDuration))
            });
    }

    function state(address _base) public view returns (State memory) {
        TokenInfo memory info = infos[_base];
        (uint256 basePrice, bool feasible) = price(_base);
        return State({price: uint128(basePrice), spread: info.spread, coeff: info.coeff, woFeasible: feasible});
    }

    function queryState(address _base) external returns (State memory) {
        State memory state_ = state(_base);
        (uint256 cloPrice_, ) = _cloPriceInQuote(_base, quoteToken);
        emit Price(state_.price, cloPrice_, _base, quoteToken);
        return state_;
    }

    /* ----- Internal Functions ----- */

    function _updateSpreadForNewPrice(address _base, uint128 _price) internal {
        uint64 preS = infos[_base].spread;
        uint128 preP = infos[_base].price;
        if (preP == 0 || _price == 0 || preS >= 1e18) {
            // previous price or current price is 0, no action is needed
            return;
        }

        uint256 maxP = _price >= preP ? _price : preP;
        uint256 minP = _price <= preP ? _price : preP;
        uint256 antiS = (uint256(1e18) * 1e18 * minP) / maxP / (uint256(1e18) - preS);
        if (antiS < 1e18) {
            uint64 newS = uint64(1e18 - antiS);
            if (newS > preS) {
                infos[_base].spread = newS;
            }
        }
    }

    function _updateSpreadForNewPrice(
        address _base,
        uint128 _price,
        uint64 _spread
    ) internal {
        require(_spread < 1e18, "!_spread");

        uint64 preS = infos[_base].spread;
        uint128 preP = infos[_base].price;
        if (preP == 0 || _price == 0 || preS >= 1e18) {
            // previous price or current price is 0, just use _spread
            infos[_base].spread = _spread;
            return;
        }

        uint256 maxP = _price >= preP ? _price : preP;
        uint256 minP = _price <= preP ? _price : preP;
        uint256 antiS = (uint256(1e18) * 1e18 * minP) / maxP / (uint256(1e18) - preS);
        if (antiS < 1e18) {
            uint64 newS = uint64(1e18 - antiS);
            infos[_base].spread = newS > _spread ? newS : _spread;
        } else {
            infos[_base].spread = _spread;
        }
    }

    function _setState(
        address _base,
        uint128 _price,
        uint64 _spread,
        uint64 _coeff
    ) internal {
        TokenInfo storage info = infos[_base];
        // NOTE: update spread before setting a new price
        _updateSpreadForNewPrice(_base, _price, _spread);
        info.price = _price;
        info.coeff = _coeff;
    }

    function _cloPriceInQuote(address _fromToken, address _toToken)
        internal
        view
        returns (uint256 refPrice, uint256 refTimestamp)
    {
        address baseOracle = clOracles[_fromToken].oracle;

        // NOTE: Only for chains where chainlink oracle is unavailable
        // if (baseOracle == address(0)) {
        //     return (0, 0);
        // }
        require(baseOracle != address(0), "WooracleV2_2: !oracle");

        address quoteOracle = clOracles[_toToken].oracle;
        uint8 quoteDecimal = clOracles[_toToken].decimal;

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
        require(getBase(_id) == address(0), "WooracleV2_2: !id_SET_ALREADY");
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
        require(x > 0, "WooracleV2_2: !calldata");

        uint8 firstByte = uint8(bytes1(_input[0]));
        uint8 op = firstByte >> 6; // 11000000
        uint8 len = firstByte & 0x3F; // 00111111

        if (op == 0 || op == 2) {
            // post prices list
            address base;
            uint128 p;

            for (uint256 i = 0; i < len; ++i) {
                base = getBase(uint8(bytes1(_input[1 + i * 5:1 + i * 5 + 1])));
                p = _decodePrice(uint32(bytes4(_input[1 + i * 5 + 1:1 + i * 5 + 5])));

                // NOTE: update spread before setting a new price
                _updateSpreadForNewPrice(base, p);
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
                p = _decodePrice(uint32(bytes4(_input[1 + i * 9 + 1:1 + i * 9 + 5])));
                s = _decodeKS(uint16(bytes2(_input[1 + i * 9 + 5:1 + i * 9 + 7])));
                k = _decodeKS(uint16(bytes2(_input[1 + i * 9 + 7:1 + i * 9 + 9])));
                _setState(base, p, s, k);
            }

            timestamp = (op == 1) ? block.timestamp : uint256(uint32(bytes4(_input[1 + len * 9:1 + len * 9 + 4])));
        } else {
            revert("WooracleV2_2: !op");
        }
    }

    function _decodePrice(uint32 b) internal pure returns (uint128) {
        return uint128((b >> 5) * (10**(b & 0x1F))); // 0x1F = 00011111
    }

    function _decodeKS(uint16 b) internal pure returns (uint64) {
        return uint64((b >> 5) * (10**(b & 0x1F)));
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyAdmin {
        if (stuckToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            TransferHelper.safeTransferETH(owner(), address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, owner(), amount);
        }
    }
}
