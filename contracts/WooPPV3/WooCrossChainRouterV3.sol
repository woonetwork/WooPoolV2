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
import {ILzApp} from "../interfaces/LayerZero/ILzApp.sol";
import {IWooCrossFee} from "../interfaces/IWooCrossFee.sol";

import {TransferHelper} from "../libraries/TransferHelper.sol";

/// @title WOOFi cross chain router via WooUSD OFT.
/// @notice Router for stateless execution of cross chain swap.
contract WooUsdOFTCrossRouter is IWooCrossChainRouterV3, Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ----- Constants ----- */

    address public constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ----- Variables ----- */

    IWooRouterV3 public wooRouter;
    IWooCrossFee public crossFee;
    uint256 public unclaimedFee;

    address public immutable weth;
    uint256 public dstGas;
    uint16 public lzChainIdLocal; // Stargate chainId on local chain

    mapping(uint16 => address) public wooCrossChainRouters; // chainId => WooCrossChainRouter address

    address public feeAddr;

    receive() external payable {}

    constructor(
        address _weth,
        address _wooRouter,
        address _crossFee,
        address _feeAddr,
        uint16 _lzChainIdLocal
    ) {
        weth = _weth;
        wooRouter = IWooRouterV3(_wooRouter);
        crossFee = IWooCrossFee(_crossFee);
        feeAddr = _feeAddr;
        lzChainIdLocal = _lzChainIdLocal;

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
        address usdOFT = wooRouter.usdOFT();
        uint256 bridgeAmount;
        uint256 fee;

        {
            if (srcInfos.fromToken == ETH_PLACEHOLDER_ADDR) {
                require(srcInfos.fromAmount <= msgValue, "WooUsdOFTCrossRouter: !srcInfos.fromAmount");
                msgValue -= srcInfos.fromAmount;
            } else {
                TransferHelper.safeTransferFrom(srcInfos.fromToken, msg.sender, address(this), srcInfos.fromAmount);
                TransferHelper.safeApprove(srcInfos.fromToken, address(wooRouter), srcInfos.fromAmount);
            }

            bridgeAmount = wooRouter.swap(
                srcInfos.fromToken,
                usdOFT,
                srcInfos.fromAmount,
                srcInfos.minBridgeAmount,
                payable(address(this)),
                to
            );
            require(
                bridgeAmount <= IERC20(usdOFT).balanceOf(address(this)) - unclaimedFee,
                "WooUsdOFTCrossRouter: usdOFT_BALANACE_NOT_ENOUGH"
            );

            fee = (bridgeAmount * crossFee.outgressFee(bridgeAmount)) / crossFee.feeBase();
            unclaimedFee += fee;
            bridgeAmount -= fee;
        }

        bytes memory payload = abi.encode(refId, to, dstInfos.toToken, dstInfos.minToAmount);

        uint256 dstGasForCall = dstGas;
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
            bridgeAmount,
            fee
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
        address usdOFT = wooRouter.usdOFT();
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

    function onOFTReceived(
        uint16 srcChainId,
        bytes memory, // srcAddress
        uint64, // nonce
        bytes32 from,
        uint256 amountLD,
        bytes memory payload
    ) external {
        address usdOFT = wooRouter.usdOFT();
        address msgSender = _msgSender();
        require(msgSender == usdOFT, "WooUsdOFTCrossRouter: INVALID_CALLER");

        require(
            wooCrossChainRouters[srcChainId] == address(uint160(uint256(from))),
            "WooUsdOFTCrossRouter: INVALID_FROM"
        );

        // make sure the same order to abi.encode when decode payload
        (uint256 refId, address to, address toToken, uint256 minToAmount) = abi.decode(
            payload,
            (uint256, address, address, uint256)
        );

        address bridgedToken = usdOFT;
        uint256 bridgedAmount = amountLD;

        uint256 fee = bridgedAmount * crossFee.ingressFee(bridgedAmount) * crossFee.feeBase();
        unclaimedFee += fee;
        bridgedAmount -= fee;

        TransferHelper.safeApprove(bridgedToken, address(wooRouter), bridgedAmount);
        try wooRouter.swap(usdOFT, toToken, bridgedAmount, minToAmount, payable(to), to) returns (
            uint256 realToAmount
        ) {
            emit WooCrossSwapOnDstChain(
                refId,
                msgSender,
                to,
                bridgedToken,
                bridgedAmount,
                toToken,
                toToken,
                minToAmount,
                realToAmount,
                fee
            );
        } catch {
            TransferHelper.safeTransfer(bridgedToken, to, bridgedAmount);
            emit WooCrossSwapOnDstChain(
                refId,
                msgSender,
                to,
                bridgedToken,
                bridgedAmount,
                toToken,
                bridgedToken,
                minToAmount,
                bridgedAmount,
                fee
            );
        }
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

    function claimFee() external onlyOwner {
        require(feeAddr != address(0), "WooUsdOFTCrossRouter: !feeAddr");
        uint256 _fee = unclaimedFee;
        unclaimedFee = 0;
        address usdOFT = wooRouter.usdOFT();
        TransferHelper.safeTransfer(usdOFT, feeAddr, _fee);
    }

    function claimFee(address _withdrawToken) external onlyOwner {
        require(feeAddr != address(0), "WooUsdOFTCrossRouter: !feeAddr");
        require(_withdrawToken != address(0), "WooUsdOFTCrossRouter: !_withdrawToken");
        uint256 _fee = unclaimedFee;
        unclaimedFee = 0;
        address usdOFT = wooRouter.usdOFT();
        TransferHelper.safeApprove(usdOFT, address(wooRouter), _fee);
        wooRouter.swap(usdOFT, _withdrawToken, _fee, 0, payable(feeAddr), feeAddr);
    }

    function setWooRouter(address _wooRouter) external onlyOwner {
        wooRouter = IWooRouterV3(_wooRouter);
    }

    function setCrossFee(address _crossFee) external onlyOwner {
        crossFee = IWooCrossFee(_crossFee);
    }

    function setDstGas(uint256 _dstGas) external onlyOwner {
        dstGas = _dstGas;
    }

    function setLzChainIdLocal(uint16 _lzChainIdLocal) external onlyOwner {
        lzChainIdLocal = _lzChainIdLocal;
    }

    function setFeeAddr(address _feeAddr) external onlyOwner {
        feeAddr = _feeAddr;
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
