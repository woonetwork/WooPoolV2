// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

// OpenZeppelin Contracts
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ICommonOFT, IOFTV2} from "@layerzerolabs/solidity-examples/contracts/token/oft/v2/IOFTV2.sol";

// Local Contracts
import {IWETH} from "../interfaces/IWETH.sol";
import {IWooCrossChainRouterV3} from "../interfaces/IWooCrossChainRouterV3.sol";
import {IWooRouterV3} from "../interfaces/IWooRouterV3.sol";
import {IWooPPV3Cross} from "../interfaces/IWooPPV3Cross.sol";
import {ILzApp} from "../interfaces/LayerZero/ILzApp.sol";

import {TransferHelper} from "../libraries/TransferHelper.sol";

/// @title WOOFi cross chain router via WooUSD OFT.
/// @notice Router for stateless execution of cross chain swap.
contract WooUsdOFTCrossRouter is IWooCrossChainRouterV3, Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ----- Constants ----- */

    address public constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ----- Variables ----- */

    IWooPPV3Cross public wooPPCross;

    address public immutable weth;
    uint256 public bridgeSlippage; // 1 in 10000th: default 1%
    uint256 public dstGas;
    uint16 public lzChainIdLocal; // Stargate chainId on local chain

    mapping(uint16 => address) public wooCrossChainRouters; // chainId => WooCrossChainRouter address

    receive() external payable {}

    constructor(
        address _weth,
        address _wooPPCross,
        uint16 _lzChainIdLocal
    ) {
        weth = _weth;
        wooPPCross = IWooPPV3Cross(_wooPPCross);
        lzChainIdLocal = _lzChainIdLocal;

        bridgeSlippage = 100;
        dstGas = 600000;

        _initLz();
    }

    /* ----- Functions ----- */

    function crossSwap(
        uint256 refId, // TODO: generate the nonce from smart contract
        address payable to,
        SrcInfos memory srcInfos,
        DstInfos memory dstInfos
    ) external payable nonReentrant {
        require(srcInfos.fromToken != address(0), "WooUsdOFTCrossRouter: !srcInfos.fromToken");
        require(dstInfos.toToken != address(0), "WooUsdOFTCrossRouter: !dstInfos.toToken");
        require(to != address(0), "WooUsdOFTCrossRouter: !to");

        uint256 msgValue = msg.value;
        uint256 bridgeAmount;

        {
            if (srcInfos.fromToken == ETH_PLACEHOLDER_ADDR) {
                require(srcInfos.fromAmount <= msgValue, "WooUsdOFTCrossRouter: !srcInfos.fromAmount");
                srcInfos.fromToken = weth;
                IWETH(weth).deposit{value: srcInfos.fromAmount}();
                msgValue -= srcInfos.fromAmount;
            } else {
                TransferHelper.safeTransferFrom(
                    srcInfos.fromToken,
                    msg.sender,
                    address(wooPPCross),
                    srcInfos.fromAmount
                );
            }

            bridgeAmount = wooPPCross.swapBaseToUsd(
                srcInfos.fromToken,
                srcInfos.fromAmount,
                srcInfos.minBridgeAmount,
                payable(address(this)),
                to
            );

            require(
                bridgeAmount <= IERC20(srcInfos.bridgeToken).balanceOf(address(this)),
                "WooUsdOFTCrossRouter: bridgeToken_BALANACE_NOT_ENOUGH"
            );
        }

        // OFT src logic: require(_removeDust(bridgeAmount) >= minAmount)
        uint256 minAmount = (bridgeAmount * (10000 - bridgeSlippage)) / 10000;

        bytes memory payload = abi.encode(refId, to, dstInfos.toToken, dstInfos.minToAmount);

        uint256 dstGasForCall = dstGas;
        address usdOFT = wooPPCross.usdOFT();
        ICommonOFT.LzCallParams memory callParams;
        {
            bytes memory adapterParams = _getAdapterParams(to, address(usdOFT), dstGasForCall, dstInfos);
            callParams = ICommonOFT.LzCallParams(
                payable(msg.sender), // refundAddress
                address(0), // zroPaymentAddress
                adapterParams //adapterParams
            );
        }

        bytes32 dstWooCrossChainRouter = bytes32(uint256(uint160(wooCrossChainRouters[dstInfos.chainId])));

        IOFTV2(usdOFT).sendAndCall{value: msgValue}(
            address(this),
            dstInfos.chainId,
            dstWooCrossChainRouter,
            bridgeAmount,
            payload,
            uint64(dstGasForCall),
            callParams
        );

        emit WooCrossSwapOnSrcChain(
            refId,
            _msgSender(),
            to,
            srcInfos.fromToken,
            srcInfos.fromAmount,
            srcInfos.minBridgeAmount,
            bridgeAmount
        );
    }

    function quoteCrossSwapFee(
        uint256 refId,
        address to,
        SrcInfos memory srcInfos,
        DstInfos memory dstInfos
    ) external view returns (uint256, uint256) {
        bytes memory payload = abi.encode(refId, to, dstInfos.toToken, dstInfos.minToAmount);

        uint256 dstGasForCall = dstGas;
        address usdOFT = wooPPCross.usdOFT();
        bytes memory adapterParams = _getAdapterParams(to, address(usdOFT), dstGasForCall, dstInfos);

        bool useZro = false;
        bytes32 dstWooCrossChainRouter = bytes32(uint256(uint160(wooCrossChainRouters[dstInfos.chainId])));

        return
            IOFTV2(usdOFT).estimateSendAndCallFee(
                dstInfos.chainId,
                dstWooCrossChainRouter,
                srcInfos.minBridgeAmount,
                payload,
                uint64(dstGasForCall),
                useZro,
                adapterParams
            );
    }

    function _initLz() internal {}

    function _getAdapterParams(
        address to,
        address oft,
        uint256 dstGasForCall,
        DstInfos memory dstInfos
    ) internal view returns (bytes memory) {
        // OFT src logic: require(providedGasLimit >= minGasLimit)
        // uint256 minGasLimit = minDstGasLookup[_dstChainId][_type] + dstGasForCall;
        // _type: 0(send), 1(send_and_call)
        uint256 providedGasLimit = ILzApp(oft).minDstGasLookup(dstInfos.chainId, 1) + dstGasForCall;

        // https://layerzero.gitbook.io/docs/evm-guides/advanced/relayer-adapter-parameters#airdrop
        return
            abi.encodePacked(
                uint16(2), // version: 2 is able to airdrop native token on destination but 1 is not
                providedGasLimit, // gasAmount: destination transaction gas for LayerZero to delivers
                dstInfos.airdropNativeAmount, // nativeForDst: airdrop native token amount
                to // addressOnDst: address to receive airdrop native token on destination
            );
    }

    /* ----- Owner & Admin Functions ----- */

    function setWooPPCross(address _wooPPCross) external onlyOwner {
        wooPPCross = IWooPPV3Cross(_wooPPCross);
    }

    function setBridgeSlippage(uint256 _bridgeSlippage) external onlyOwner {
        require(_bridgeSlippage <= 10000, "WooUsdOFTCrossRouter: !_bridgeSlippage");
        bridgeSlippage = _bridgeSlippage;
    }

    function setDstGas(uint256 _dstGas) external onlyOwner {
        dstGas = _dstGas;
    }

    function setLzChainIdLocal(uint16 _lzChainIdLocal) external onlyOwner {
        lzChainIdLocal = _lzChainIdLocal;
    }

    function setWooCrossChainRouter(uint16 chainId, address wooCrossChainRouter) external onlyOwner {
        require(wooCrossChainRouter != address(0), "WooUsdOFTCrossRouter: !wooCrossChainRouter");
        wooCrossChainRouters[chainId] = wooCrossChainRouter;
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        if (stuckToken == ETH_PLACEHOLDER_ADDR) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, msg.sender, amount);
        }
    }
}
