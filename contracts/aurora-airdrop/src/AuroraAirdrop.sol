// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title AuroraAirdrop
/// @notice Gas-efficient ERC-20 airdrop via Merkle proofs
/// @dev Features:
///      - Merkle tree verification for eligibility
///      - Each leaf = keccak256(abi.encodePacked(address, uint256 amount))
///      - Claim tracking (each address claims once)
///      - Owner can update Merkle root (new airdrop round)
///      - Owner can set a deadline for claiming
///      - Owner recovers unclaimed tokens after deadline
///      - ReentrancyGuard on claim
contract AuroraAirdrop is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using MerkleProof for bytes32[];

    // ─── Types ───

    error AlreadyClaimed(address account);
    error InvalidProof();
    error ClaimPeriodEnded(uint256 deadline);
    error ClaimPeriodNotEnded(uint256 deadline);
    error NothingToRecover();
    error InvalidMerkleRoot(bytes32 root);
    error ZeroAmount();

    // ─── Events ───

    event Claimed(address indexed account, uint256 amount);
    event MerkleRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    event DeadlineUpdated(uint256 oldDeadline, uint256 newDeadline);
    event UnclaimedRecovered(address indexed to, uint256 amount);

    // ─── State ───

    /// @notice The ERC-20 token being airdropped
    IERC20 public immutable token;

    /// @notice Merkle root of the airdrop tree
    bytes32 public merkleRoot;

    /// @notice Deadline timestamp for claiming (0 = no deadline)
    uint256 public claimDeadline;

    /// @notice Total amount allocated in the Merkle tree
    uint256 public totalAllocated;

    /// @notice Total amount claimed so far
    uint256 public totalClaimed;

    /// @notice Whether an address has already claimed
    mapping(address => bool) public hasClaimed;

    // ─── Constructor ───

    /// @param _token ERC-20 token address
    /// @param _merkleRoot Merkle root of the airdrop
    /// @param _claimDeadline Unix timestamp deadline (0 for no deadline)
    /// @param _totalAllocated Total tokens allocated in the tree
    /// @param owner_ Initial contract owner
    constructor(
        address _token,
        bytes32 _merkleRoot,
        uint256 _claimDeadline,
        uint256 _totalAllocated,
        address owner_
    ) Ownable(owner_) {
        if (_merkleRoot == bytes32(0)) revert InvalidMerkleRoot(_merkleRoot);

        token = IERC20(_token);
        merkleRoot = _merkleRoot;
        claimDeadline = _claimDeadline;
        totalAllocated = _totalAllocated;
    }

    // ─── Claim ───

    /// @notice Claim airdrop tokens using a Merkle proof
    /// @param amount Amount of tokens allocated to the caller
    /// @param proof Merkle proof array
    function claim(uint256 amount, bytes32[] calldata proof) external nonReentrant {
        if (hasClaimed[msg.sender]) revert AlreadyClaimed(msg.sender);
        if (claimDeadline > 0 && block.timestamp > claimDeadline) {
            revert ClaimPeriodEnded(claimDeadline);
        }

        // Verify Merkle proof: leaf = keccak256(abi.encodePacked(address, amount))
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        if (!proof.verifyCalldata(merkleRoot, leaf)) revert InvalidProof();

        hasClaimed[msg.sender] = true;
        totalClaimed += amount;

        token.safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    // ─── Owner Functions ───

    /// @notice Update the Merkle root for a new airdrop round. Only owner.
    /// @param newRoot New Merkle root
    function setMerkleRoot(bytes32 newRoot) external onlyOwner {
        if (newRoot == bytes32(0)) revert InvalidMerkleRoot(newRoot);

        bytes32 oldRoot = merkleRoot;
        merkleRoot = newRoot;

        emit MerkleRootUpdated(oldRoot, newRoot);
    }

    /// @notice Update the claim deadline. Only owner.
    /// @param newDeadline New deadline timestamp (0 to remove deadline)
    function setClaimDeadline(uint256 newDeadline) external onlyOwner {
        uint256 oldDeadline = claimDeadline;
        claimDeadline = newDeadline;

        emit DeadlineUpdated(oldDeadline, newDeadline);
    }

    /// @notice Update total allocated amount. Only owner.
    /// @param newTotal New total allocated
    function setTotalAllocated(uint256 newTotal) external onlyOwner {
        totalAllocated = newTotal;
    }

    /// @notice Recover unclaimed tokens after deadline. Only owner.
    /// @param to Recipient of recovered tokens
    function recoverUnclaimed(address to) external onlyOwner {
        if (claimDeadline == 0 || block.timestamp <= claimDeadline) {
            revert ClaimPeriodNotEnded(claimDeadline);
        }

        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) revert NothingToRecover();

        token.safeTransfer(to, balance);

        emit UnclaimedRecovered(to, balance);
    }

    // ─── View Functions ───

    /// @notice Check if the claim period is still active
    function isClaimActive() external view returns (bool) {
        return claimDeadline == 0 || block.timestamp <= claimDeadline;
    }

    /// @notice Get the contract's token balance
    function remainingTokens() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
}
