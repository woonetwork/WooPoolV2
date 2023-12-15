// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

// OpenZeppelin Contracts
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// Local Contracts
import {IWETH} from "../interfaces/IWETH.sol";
import {IWooCrossRouterForWidget} from "../interfaces/CrossChain/IWooCrossRouterForWidget.sol";
import {IWooRouterV2} from "../interfaces/IWooRouterV2.sol";
import {IWooCrossChainRouterV3} from "../interfaces/CrossChain/IWooCrossChainRouterV3.sol";
import {ISgInfo} from "../interfaces/CrossChain/ISgInfo.sol";
import {INonceCounter} from "../interfaces/WOOFiDex/INonceCounter.sol";

import {TransferHelper} from "../libraries/TransferHelper.sol";

/// @title cross chain router implementation, version 3.
/// @notice Router for stateless execution of cross chain swap against WOOFi or 1inch swap.
/// @custom:stargate-contracts https://stargateprotocol.gitbook.io/stargate/developers/contract-addresses/mainnet
contract WooCrossRouterForWidget is IWooCrossRouterForWidget, Ownable, Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ----- Constants ----- */

    address public constant ETH_PLACEHOLDER_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 public constant FEE_BASE = 1e5;

    /* ----- Variables ----- */

    IWooRouterV2 public wooRouter;
    IWooCrossChainRouterV3 public crossRouter;
    ISgInfo public sgInfo;
    INonceCounter public nonceCounter;

    receive() external payable {}

    constructor(
        address _nonceCounter,
        address _wooRouter,
        address _crossRouter,
        address _sgInfo
    ) {
        nonceCounter = INonceCounter(_nonceCounter);
        wooRouter = IWooRouterV2(_wooRouter);
        crossRouter = IWooCrossChainRouterV3(_crossRouter);
        sgInfo = ISgInfo(_sgInfo);
    }

    /* ----- Functions ----- */

    function swap(
        address payable to,
        LocalSwapInfos memory infoWOOFi,
        IWooCrossChainRouterV3.Src1inch calldata info1inch,
        FeeInfo calldata feeInfo
    ) external payable returns (uint256 realToAmount) {
        require(infoWOOFi.fromToken != address(0), "WooCrossRouterForWidget: !fromToken");
        require(infoWOOFi.toToken != address(0), "WooCrossRouterForWidget: !toToken");
        require(to != address(0), "WooCrossRouterForWidget: !to");

        uint256 msgValue = 0;
        if (infoWOOFi.fromToken == ETH_PLACEHOLDER_ADDR) {
            require(msg.value >= infoWOOFi.fromAmount, "WooCrossRouterForWidget: !msg.value");
            uint256 fee = (infoWOOFi.fromAmount * feeInfo.feeRate) / FEE_BASE;
            TransferHelper.safeTransferETH(feeInfo.feeAddr, fee);
            msgValue = msg.value - fee;
            infoWOOFi.fromAmount -= fee;
        } else {
            TransferHelper.safeTransferFrom(infoWOOFi.fromToken, msg.sender, address(this), infoWOOFi.fromAmount);
            uint256 fee = (infoWOOFi.fromAmount * feeInfo.feeRate) / FEE_BASE;
            TransferHelper.safeTransfer(infoWOOFi.fromToken, feeInfo.feeAddr, fee);
            infoWOOFi.fromAmount -= fee;
            TransferHelper.safeApprove(infoWOOFi.fromToken, address(wooRouter), infoWOOFi.fromAmount);
        }

        if (info1inch.swapRouter == address(0)) {
            realToAmount = wooRouter.swap{value: msgValue}(
                infoWOOFi.fromToken,
                infoWOOFi.toToken,
                infoWOOFi.fromAmount,
                infoWOOFi.minToAmount,
                to,
                infoWOOFi.rebateTo
            );
        } else {
            realToAmount = wooRouter.externalSwap{value: msgValue}(
                info1inch.swapRouter,
                info1inch.swapRouter,
                infoWOOFi.fromToken,
                infoWOOFi.toToken,
                infoWOOFi.fromAmount,
                infoWOOFi.minToAmount,
                to,
                info1inch.data
            );
        }
    }

    function crossSwap(
        address payable to,
        IWooCrossChainRouterV3.SrcInfos memory srcInfos,
        IWooCrossChainRouterV3.DstInfos memory dstInfos,
        IWooCrossChainRouterV3.Src1inch calldata src1inch,
        IWooCrossChainRouterV3.Dst1inch calldata dst1inch,
        FeeInfo calldata feeInfo
    ) external payable whenNotPaused nonReentrant {
        require(srcInfos.fromToken != address(0), "WooCrossRouterForWidget: !srcInfos.fromToken");
        require(dstInfos.toToken != address(0), "WooCrossRouterForWidget: !dstInfos.toToken");
        require(to != address(0), "WooCrossRouterForWidget: !to");

        uint256 msgValue = msg.value;
        if (srcInfos.fromToken == ETH_PLACEHOLDER_ADDR) {
            require(msg.value >= srcInfos.fromAmount, "WooCrossRouterForWidget: !msg.value");
            uint256 fee = (srcInfos.fromAmount * feeInfo.feeRate) / FEE_BASE;
            TransferHelper.safeTransferETH(feeInfo.feeAddr, fee);
            msgValue -= fee;
            srcInfos.fromAmount -= fee;
        } else {
            TransferHelper.safeTransferFrom(srcInfos.fromToken, msg.sender, address(this), srcInfos.fromAmount);
            uint256 fee = (srcInfos.fromAmount * feeInfo.feeRate) / FEE_BASE;
            TransferHelper.safeTransfer(srcInfos.fromToken, feeInfo.feeAddr, fee);
            srcInfos.fromAmount -= fee;
            TransferHelper.safeApprove(srcInfos.fromToken, address(crossRouter), srcInfos.fromAmount);
        }

        uint256 refId = nonceCounter.increment(dstInfos.chainId);

        crossRouter.crossSwap{value: msgValue}(refId, to, srcInfos, dstInfos, src1inch, dst1inch);
    }

    function quoteLayerZeroFee(
        address to,
        IWooCrossChainRouterV3.DstInfos calldata dstInfos,
        IWooCrossChainRouterV3.Dst1inch calldata dst1inch
    ) external view returns (uint256, uint256) {
        uint256 refId = nonceCounter.outboundNonce(dstInfos.chainId) + 1;
        return
            crossRouter.quoteLayerZeroFee(
                refId,
                to,
                IWooCrossChainRouterV3.DstInfos(
                    dstInfos.chainId,
                    dstInfos.toToken,
                    dstInfos.bridgeToken,
                    dstInfos.minToAmount,
                    dstInfos.airdropNativeAmount,
                    dstInfos.dstGasForCall
                ),
                IWooCrossChainRouterV3.Dst1inch(dst1inch.swapRouter, dst1inch.data)
            );
    }

    function _generalBalanceOf(address token, address who) internal view returns (uint256) {
        return token == ETH_PLACEHOLDER_ADDR ? who.balance : IERC20(token).balanceOf(who);
    }

    /* ----- Owner & Admin Functions ----- */

    function setWooRouter(address _wooRouter) external onlyOwner {
        wooRouter = IWooRouterV2(_wooRouter);
    }

    function setWooCrossRouter(address _crossRouter) external onlyOwner {
        crossRouter = IWooCrossChainRouterV3(_crossRouter);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
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
