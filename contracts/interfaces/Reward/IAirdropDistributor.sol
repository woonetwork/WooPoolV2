// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IAirdropDistributor {
    // -------- Structs -------- //

    struct DistributionData {
        address account;
        uint8 campaignId;
        uint256 amount;
    }

    struct ClaimedData {
        address account;
        uint256 amount;
    }

    // -------- Events -------- //

    /// @dev Emits when a user claims tokens
    event Claimed(address indexed account, uint256 amount, bool indexed historic);

    /// @dev Emits when the owner replaces the merkle root
    event RootUpdated(bytes32 oldRoot, bytes32 indexed newRoot);

    /// @dev Emitted from a special function after updating the root to index allocations
    event TokenAllocated(address indexed account, uint8 indexed campaignId, uint256 amount);

    event AdminUpdated(address indexed addr, bool flag);

    // -------- Methods -------- //

    /// @dev Returns the reward token distributed by this contract.
    function rewardToken() external view returns (address);

    /// @dev Returns the current merkle root containing total claimable balances
    function merkleRoot() external view returns (bytes32);

    /// @dev Returns the total amount of token claimed by the user
    function claimed(address user) external view returns (uint256);

    // Claim the given amount of the token to the given address. Reverts if the inputs are invalid.
    /// @dev Claims the given amount of the token for the account. Reverts if the inputs are not a leaf in the tree
    ///      or the total claimed amount for the account is more than the leaf amount.
    function claim(
        uint256 index,
        address account,
        uint256 totalAmount,
        bytes32[] calldata merkleProof
    ) external;
}
