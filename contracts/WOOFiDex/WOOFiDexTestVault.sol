// SPDX-License-Identifier: MIT
pragma solidity =0.8.14;

// OpenZeppelin Contracts
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

// Uniswap Periphery
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

// Local Contracts
import {IWOOFiDexVault} from "../interfaces/WOOFiDex/IWOOFiDexVault.sol";

contract WOOFiDexTestVault is IWOOFiDexVault, Ownable, Pausable {
    address public constant NATIVE_PLACEHOLDER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public token;
    uint64 public depositId;

    constructor(address _token) {
        token = _token;
    }

    function depositTo(address receiver, VaultDepositFE calldata data) external whenNotPaused {
        TransferHelper.safeTransferFrom(token, _msgSender(), receiver, data.tokenAmount);
        _newDepositId();
        emit AccountDepositTo(data.accountId, receiver, depositId, data.tokenHash, data.tokenAmount);
    }

    function inCaseTokenGotStuck(address _token) external onlyOwner {
        address msgSender = _msgSender();
        if (_token == NATIVE_PLACEHOLDER) {
            TransferHelper.safeTransferETH(msgSender, address(this).balance);
        } else {
            uint256 bal = IERC20(_token).balanceOf(address(this));
            TransferHelper.safeTransfer(_token, msgSender, bal);
        }
    }

    function _newDepositId() internal returns (uint64) {
        return ++depositId;
    }
}
