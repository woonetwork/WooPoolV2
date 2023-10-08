// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

// OpenZeppelin Contracts
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Uniswap Periphery
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

// Local Contracts
import {IWOOFiDexRouter} from "../interfaces/WOOFiDex/IWOOFiDexRouter.sol";
import {IWOOFiDexVault} from "../interfaces/WOOFiDex/IWOOFiDexVault.sol";
import {IWooRouterV2} from "../interfaces/IWooRouterV2.sol";

/// @title WOOFi Dex Router for Local Chain Swap to Deposit
contract WOOFiDexRouter is IWOOFiDexRouter, Ownable, Pausable, ReentrancyGuard {
    /* ----- Constants ----- */

    address public constant NATIVE_PLACEHOLDER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /* ----- Variables ----- */

    IWooRouterV2 public wooRouter;

    address public immutable weth;

    mapping(address => address) public woofiDexVaults; // token address => WOOFiDexVault address

    receive() external payable {}

    constructor(address _weth, address _wooRouter) {
        wooRouter = IWooRouterV2(_wooRouter);

        weth = _weth;
    }

    /* ----- Functions ----- */

    function swap(
        address payable to,
        Infos calldata infos,
        VaultDeposit calldata vaultDeposit
    ) external payable whenNotPaused nonReentrant {
        require(to != address(0), "WOOFiDexRouter: to not allow");
        require(infos.fromToken != address(0) && infos.toToken != address(0), "WOOFiDexRouter: infos.token not allow");
        require(woofiDexVaults[infos.toToken] != address(0), "WOOFiDexRouter: woofiDexVault not allow");

        address sender = _msgSender();
        uint256 toAmount;

        if (infos.fromToken == NATIVE_PLACEHOLDER) {
            uint256 nativeAmount = msg.value;
            require(infos.fromAmount == nativeAmount, "WOOFiDexRouter: infos.fromAmount not equal to value");
            toAmount = wooRouter.swap{value: nativeAmount}(
                infos.fromToken,
                infos.toToken,
                infos.fromAmount,
                infos.minToAmount,
                payable(address(this)),
                to
            );
        } else {
            TransferHelper.safeTransferFrom(infos.fromToken, sender, address(this), infos.fromAmount);
            TransferHelper.safeApprove(infos.fromToken, address(wooRouter), infos.fromAmount);
            toAmount = wooRouter.swap(
                infos.fromToken,
                infos.toToken,
                infos.fromAmount,
                infos.minToAmount,
                payable(address(this)),
                to
            );
        }

        IWOOFiDexVault.VaultDepositFE memory vaultDepositFE = _depositTo(to, infos.toToken, vaultDeposit, toAmount);

        emit WOOFiDexSwap(
            sender,
            to,
            infos.fromToken,
            infos.fromAmount,
            infos.toToken,
            infos.minToAmount,
            toAmount,
            vaultDepositFE.accountId,
            vaultDepositFE.brokerHash,
            vaultDepositFE.tokenHash,
            vaultDepositFE.tokenAmount
        );
    }

    function _depositTo(
        address to,
        address toToken,
        VaultDeposit memory vaultDeposit,
        uint256 tokenAmount
    ) internal returns (IWOOFiDexVault.VaultDepositFE memory) {
        IWOOFiDexVault.VaultDepositFE memory vaultDepositFE = IWOOFiDexVault.VaultDepositFE(
            vaultDeposit.accountId,
            vaultDeposit.brokerHash,
            vaultDeposit.tokenHash,
            uint128(tokenAmount)
        );
        address woofiDexVault = woofiDexVaults[toToken];
        if (toToken == NATIVE_PLACEHOLDER) {
            IWOOFiDexVault(woofiDexVault).depositTo{value: tokenAmount}(to, vaultDepositFE);
        } else {
            TransferHelper.safeApprove(toToken, woofiDexVault, tokenAmount);
            IWOOFiDexVault(woofiDexVault).depositTo(to, vaultDepositFE);
        }

        return vaultDepositFE;
    }

    /* ----- Owner & Admin Functions ----- */

    function setWooRouter(address _wooRouter) external onlyOwner {
        require(_wooRouter != address(0), "WOOFiDexRouter: _wooRouter cant be zero");
        wooRouter = IWooRouterV2(_wooRouter);
    }

    function setWOOFiDexVault(address token, address woofiDexVault) external onlyOwner {
        require(woofiDexVault != address(0), "WOOFiDexRouter: woofiDexVault cant be zero");
        woofiDexVaults[token] = woofiDexVault;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        address sender = _msgSender();
        if (stuckToken == NATIVE_PLACEHOLDER) {
            TransferHelper.safeTransferETH(sender, address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, sender, amount);
        }
    }
}
