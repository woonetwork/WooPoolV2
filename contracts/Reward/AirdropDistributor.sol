// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TransferHelper} from "../libraries/TransferHelper.sol";

import "../interfaces/Reward/IAirdropDistributor.sol";

contract AirdropDistributor is Ownable, Pausable, IAirdropDistributor {
    /// @dev Reward token for airdrop
    address public immutable rewardToken;

    /// @dev Merkle root
    bytes32 public merkleRoot;

    /// @dev Amounts already claimed by users
    mapping(address => uint256) public claimed;

    mapping(address => bool) public isAdmin;

    modifier onlyAdmin() {
        require(_msgSender() == owner() || isAdmin[_msgSender()], "AirdropDistributor: !admin");
        _;
    }

    constructor(address rewardToken_, ClaimedData[] memory alreadyClaimed) {
        rewardToken = rewardToken_;
        _emitClaimedEvents(alreadyClaimed);
    }

    function updateMerkleRoot(bytes32 newRoot) external onlyAdmin {
        bytes32 oldRoot = merkleRoot;
        merkleRoot = newRoot;
        emit RootUpdated(oldRoot, newRoot);
    }

    function emitDistributionEvents(DistributionData[] calldata data) external onlyAdmin {
        uint256 len = data.length;
        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                emit TokenAllocated(data[i].account, data[i].campaignId, data[i].amount);
            }
        }
    }

    function emitClaimedEvents(ClaimedData[] memory alreadyClaimed) external onlyAdmin {
        _emitClaimedEvents(alreadyClaimed);
    }

    function _emitClaimedEvents(ClaimedData[] memory alreadyClaimed) internal {
        uint256 len = alreadyClaimed.length;
        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                emit Claimed(alreadyClaimed[i].account, alreadyClaimed[i].amount, true);
            }
        }
    }

    function claim(
        uint256 index,
        address account,
        uint256 totalAmount,
        bytes32[] calldata merkleProof
    ) external {
        if (claimed[account] >= totalAmount) {
            emit Claimed(account, 0, false);
            return;
        }

        bytes32 node = keccak256(abi.encodePacked(index, account, totalAmount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "AirdropDistributor: !proof.");

        uint256 claimedAmount = totalAmount - claimed[account];
        claimed[account] += claimedAmount;
        TransferHelper.safeTransfer(rewardToken, account, claimedAmount);

        emit Claimed(account, claimedAmount, false);
    }

    function setAdmin(address addr, bool flag) public onlyOwner {
        isAdmin[addr] = flag;
        emit AdminUpdated(addr, flag);
    }

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }

    function inCaseTokenGotStuck(address stuckToken) external onlyOwner {
        if (stuckToken == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            TransferHelper.safeTransferETH(_msgSender(), address(this).balance);
        } else {
            uint256 amount = IERC20(stuckToken).balanceOf(address(this));
            TransferHelper.safeTransfer(stuckToken, _msgSender(), amount);
        }
    }
}
