// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { BitMaps } from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

interface ISenseTokenMintable {
    function mint(address to, uint256 amount) external;
}

/// @title RewardDistributor — hourly epoch-based reward claims
/// @notice The backend computes rewards off-chain, publishes a merkle root
///         per epoch, and users claim by submitting a proof. This avoids
///         paying gas per-reading which would make the whole thing infeasible.
contract RewardDistributor is AccessControl, ReentrancyGuard {
    using BitMaps for BitMaps.BitMap;

    bytes32 public constant PUBLISHER_ROLE = keccak256("PUBLISHER_ROLE");

    ISenseTokenMintable public immutable token;

    struct Epoch {
        bytes32 root;
        uint256 totalAmount;       // sum of all `amount` leaves for bookkeeping
        uint256 claimedAmount;     // running total of claims in this epoch
        uint64  publishedAt;
    }

    mapping(uint256 epochId => Epoch) public epochs;
    mapping(uint256 epochId => BitMaps.BitMap) private _claimed;

    event EpochPublished(uint256 indexed epochId, bytes32 root, uint256 totalAmount);
    event Claimed(uint256 indexed epochId, uint256 indexed index, address indexed account, uint256 amount);

    error EpochAlreadyPublished(uint256 epochId);
    error UnknownEpoch(uint256 epochId);
    error AlreadyClaimed(uint256 epochId, uint256 index);
    error InvalidProof();
    error ClaimExceedsTotal(uint256 claimed, uint256 total);

    constructor(address tokenAddress, address admin, address publisher) {
        token = ISenseTokenMintable(tokenAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PUBLISHER_ROLE, publisher);
    }

    /// @notice Publish the merkle root for an epoch. Called hourly by the backend bridge.
    function publishEpoch(uint256 epochId, bytes32 root, uint256 totalAmount)
        external
        onlyRole(PUBLISHER_ROLE)
    {
        if (epochs[epochId].publishedAt != 0) revert EpochAlreadyPublished(epochId);
        epochs[epochId] = Epoch({
            root: root,
            totalAmount: totalAmount,
            claimedAmount: 0,
            publishedAt: uint64(block.timestamp)
        });
        emit EpochPublished(epochId, root, totalAmount);
    }

    /// @notice Claim rewards for a given (epoch, index, account, amount) with a merkle proof.
    /// @dev `index` is the position of the leaf in the tree — used to prevent double-claims.
    function claim(
        uint256 epochId,
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata proof
    ) external nonReentrant {
        Epoch storage epoch = epochs[epochId];
        if (epoch.publishedAt == 0) revert UnknownEpoch(epochId);
        if (_claimed[epochId].get(index)) revert AlreadyClaimed(epochId, index);

        // Leaf schema: keccak256(bytes.concat(bytes32(index), bytes32(uint256(uint160(account))), bytes32(amount)))
        bytes32 leaf = keccak256(bytes.concat(
            bytes32(index),
            bytes32(uint256(uint160(account))),
            bytes32(amount)
        ));
        if (!MerkleProof.verifyCalldata(proof, epoch.root, leaf)) revert InvalidProof();

        uint256 newClaimed = epoch.claimedAmount + amount;
        if (newClaimed > epoch.totalAmount) revert ClaimExceedsTotal(newClaimed, epoch.totalAmount);

        _claimed[epochId].set(index);
        epoch.claimedAmount = newClaimed;

        token.mint(account, amount);
        emit Claimed(epochId, index, account, amount);
    }

    function isClaimed(uint256 epochId, uint256 index) external view returns (bool) {
        return _claimed[epochId].get(index);
    }
}
