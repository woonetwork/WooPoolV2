// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/CrossChain/ISgInfo.sol";

/// @title cross chain router implementation, version 3.
/// @notice Router for stateless execution of cross chain swap against WOOFi or 1inch swap.
/// @custom:stargate-contracts https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
contract SgInfo is ISgInfo, Ownable {
    mapping(uint16 => address) public sgETHs; // chainId => SGETH token address

    mapping(uint16 => mapping(address => uint256)) public sgPoolIds; // chainId => token address => Stargate poolId

    address public stargateRouter;
    uint16 public sgChainIdLocal; // Stargate chainId on local chain

    constructor(address _stargateRouter, uint16 _sgChainIdLocal) {
        _initSgETHs();
        _initSgPoolIds();
        stargateRouter = _stargateRouter;
        sgChainIdLocal = _sgChainIdLocal;
    }

    function _initSgETHs() internal {
        // Ethereum
        sgETHs[101] = 0x72E2F4830b9E45d52F80aC08CB2bEC0FeF72eD9c;
        // Arbitrum
        sgETHs[110] = 0x82CbeCF39bEe528B5476FE6d1550af59a9dB6Fc0;
        // Optimism
        sgETHs[111] = 0xb69c8CBCD90A39D8D3d3ccf0a3E968511C3856A0;
        // Linea
        sgETHs[183] = 0x224D8Fd7aB6AD4c6eb4611Ce56EF35Dec2277F03;
        // Base
        sgETHs[184] = 0x224D8Fd7aB6AD4c6eb4611Ce56EF35Dec2277F03;
    }

    function _initSgPoolIds() internal {
        // poolId > 0 means able to be bridge token
        // Ethereum
        sgPoolIds[101][0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = 1; // USDC
        sgPoolIds[101][0xdAC17F958D2ee523a2206206994597C13D831ec7] = 2; // USDT
        sgPoolIds[101][0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2] = 13; // WETH
        sgPoolIds[101][0x4691937a7508860F876c9c0a2a617E7d9E945D4B] = 20; // WOO
        // BNB Chain
        sgPoolIds[102][0x55d398326f99059fF775485246999027B3197955] = 2; // USDT
        sgPoolIds[102][0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56] = 5; // BUSD
        sgPoolIds[102][0x4691937a7508860F876c9c0a2a617E7d9E945D4B] = 20; // WOO
        // Avalanche
        sgPoolIds[106][0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E] = 1; // USDC
        sgPoolIds[106][0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7] = 2; // USDT
        sgPoolIds[106][0xaBC9547B534519fF73921b1FBA6E672b5f58D083] = 20; // WOO
        // Polygon
        sgPoolIds[109][0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174] = 1; // USDC
        sgPoolIds[109][0xc2132D05D31c914a87C6611C10748AEb04B58e8F] = 2; // USDT
        sgPoolIds[109][0x1B815d120B3eF02039Ee11dC2d33DE7aA4a8C603] = 20; // WOO
        // Arbitrum
        sgPoolIds[110][0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8] = 1; // USDC
        sgPoolIds[110][0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9] = 2; // USDT
        sgPoolIds[110][0x82aF49447D8a07e3bd95BD0d56f35241523fBab1] = 13; // WETH
        sgPoolIds[110][0xcAFcD85D8ca7Ad1e1C6F82F651fA15E33AEfD07b] = 20; // WOO
        // Optimism
        sgPoolIds[111][0x7F5c764cBc14f9669B88837ca1490cCa17c31607] = 1; // USDC
        sgPoolIds[111][0x4200000000000000000000000000000000000006] = 13; // WETH
        sgPoolIds[111][0x871f2F2ff935FD1eD867842FF2a7bfD051A5E527] = 20; // WOO
        // Fantom
        sgPoolIds[112][0x04068DA6C83AFCFA0e13ba15A6696662335D5B75] = 1; // USDC
        sgPoolIds[112][0x6626c47c00F1D87902fc13EECfaC3ed06D5E8D8a] = 20; // WOO
        // Linea
        sgPoolIds[183][0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f] = 13; // WETH
        // Base
        sgPoolIds[184][0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA] = 1; // USDC
        sgPoolIds[184][0x4200000000000000000000000000000000000006] = 13; // WETH
    }

    function setSgETH(uint16 chainId, address token) external onlyOwner {
        require(token != address(0), "SgInfo: token cant be zero");
        sgETHs[chainId] = token;
    }

    function setSgPoolId(
        uint16 chainId,
        address token,
        uint256 poolId
    ) external onlyOwner {
        sgPoolIds[chainId][token] = poolId;
    }

    function setStargateRouter(address _stargateRouter) external onlyOwner {
        require(_stargateRouter != address(0), "SgInfo: !_stargateRouter");
        stargateRouter = _stargateRouter;
    }

    function setSgChainIdLocal(uint16 _sgChainIdLocal) external onlyOwner {
        sgChainIdLocal = _sgChainIdLocal;
    }
}
