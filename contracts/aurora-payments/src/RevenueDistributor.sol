// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title IVotes — minimal interface for ERC20Votes snapshot queries
interface IVotes {
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);
    function getVotes(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @title RevenueDistributor
/// @notice Distributes platform revenue (USDC) to governance token holders using snapshot-based proportional claims
/// @dev Receives USDC from TaskEscrow and Pledgly treasuries, then distributes to AURA/AURAG token holders.
///      Snapshot is taken at the block when distribution is created using ERC20Votes getPastVotes.
///      Token holders claim their share at any time after distribution is created.
contract RevenueDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ───────────── Structs ─────────────

    struct Distribution {
        uint256 amount;            // total USDC distributed in this round
        uint256 snapshotBlock;     // block number for the snapshot
        uint256 totalTokenSupply;  // total governance token supply at snapshot
        uint256 totalClaimed;      // running total of USDC claimed
        bool    finalized;         // true when all tokens have been accounted for
    }

    // ───────────── Storage ─────────────

    IERC20 public immutable usdc;
    IVotes public immutable governanceToken;

    uint256 public distributionCount;
    mapping(uint256 => Distribution) public distributions;
    mapping(uint256 => mapping(address => uint256)) public claimed;

    // Track token sources that have sent USDC
    mapping(address => bool) public authorizedSources;

    // ───────────── Events ─────────────

    event DistributionCreated(
        uint256 indexed distributionId,
        uint256 amount,
        uint256 snapshotBlock,
        uint256 totalTokenSupply
    );

    event RevenueClaimed(
        uint256 indexed distributionId,
        address indexed holder,
        uint256 amount
    );

    event SourceAuthorized(address indexed source);
    event SourceDeauthorized(address indexed source);
    event DistributionFinalized(uint256 indexed distributionId);

    // ───────────── Errors ─────────────

    error ZeroAmount();
    error ZeroTokenSupply();
    error AlreadyClaimed();
    error NothingToClaim();
    error AlreadyFinalized();
    error NotAuthorizedSource();
    error InvalidAddress();
    error ZeroBalance();

    // ───────────── Constructor ─────────────

    /// @param _usdc Address of the USDC stablecoin
    /// @param _governanceToken Address of the governance token with ERC20Votes (snapshot) support
    /// @param _owner Address of the owner (governance contract)
    constructor(
        address _usdc,
        address _governanceToken,
        address _owner
    ) Ownable(_owner) {
        require(_usdc != address(0), InvalidAddress());
        require(_governanceToken != address(0), InvalidAddress());
        usdc = IERC20(_usdc);
        governanceToken = IVotes(_governanceToken);
    }

    // ───────────── Source Management ─────────────

    /// @notice Authorize a source address (e.g. TaskEscrow or Pledgly treasury) to send USDC
    function authorizeSource(address _source) external onlyOwner {
        require(_source != address(0), InvalidAddress());
        authorizedSources[_source] = true;
        emit SourceAuthorized(_source);
    }

    /// @notice Revoke authorization for a source
    function deauthorizeSource(address _source) external onlyOwner {
        authorizedSources[_source] = false;
        emit SourceDeauthorized(_source);
    }

    // ───────────── Deposit ─────────────

    /// @notice Deposit USDC into the distributor. Can be called by anyone (token transfer).
    /// @param _amount Amount of USDC to deposit
    function deposit(uint256 _amount) external {
        require(_amount > 0, ZeroAmount());
        usdc.safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice Deposit USDC from an authorized source (treasury forwarding)
    /// @param _amount Amount of USDC to deposit
    function depositFromSource(uint256 _amount) external {
        require(authorizedSources[msg.sender], NotAuthorizedSource());
        require(_amount > 0, ZeroAmount());
        usdc.safeTransferFrom(msg.sender, address(this), _amount);
    }

    // ───────────── Distribution Creation (Owner / Governance) ─────────────

    /// @notice Create a new revenue distribution round.
    ///         Snapshots the current block for governance token balances.
    ///         The entire contract USDC balance is included in this distribution.
    /// @return distId The distribution round ID
    function createDistribution() external onlyOwner nonReentrant returns (uint256 distId) {
        uint256 balance = usdc.balanceOf(address(this));
        require(balance > 0, ZeroBalance());

        // getPastVotes/getPastTotalSupply require timepoint < block.number,
        // so we snapshot the *previous* block's state for consistency.
        uint256 snapshotBlock = block.number - 1;
        uint256 totalSupply = governanceToken.getPastTotalSupply(snapshotBlock);
        require(totalSupply > 0, ZeroTokenSupply());

        distId = distributionCount++;

        distributions[distId] = Distribution({
            amount: balance,
            snapshotBlock: snapshotBlock,
            totalTokenSupply: totalSupply,
            totalClaimed: 0,
            finalized: false
        });

        emit DistributionCreated(distId, balance, snapshotBlock, totalSupply);
    }

    /// @notice Create a distribution for a specific amount (partial)
    /// @param _amount Specific USDC amount to distribute
    /// @return distId The distribution round ID
    function createDistributionAmount(uint256 _amount) external onlyOwner nonReentrant returns (uint256 distId) {
        require(_amount > 0, ZeroAmount());
        uint256 balance = usdc.balanceOf(address(this));
        require(balance >= _amount, ZeroBalance());

        uint256 snapshotBlock = block.number - 1;
        uint256 totalSupply = governanceToken.getPastTotalSupply(snapshotBlock);
        require(totalSupply > 0, ZeroTokenSupply());

        distId = distributionCount++;

        distributions[distId] = Distribution({
            amount: _amount,
            snapshotBlock: snapshotBlock,
            totalTokenSupply: totalSupply,
            totalClaimed: 0,
            finalized: false
        });

        emit DistributionCreated(distId, _amount, snapshotBlock, totalSupply);
    }

    // ───────────── Claiming ─────────────

    /// @notice Claim USDC revenue share for a given distribution round.
    ///         Share = (holder's past votes / total token supply at snapshot) * distribution amount
    /// @param _distributionId The distribution round to claim from
    function claim(uint256 _distributionId) external nonReentrant {
        Distribution storage dist = distributions[_distributionId];
        require(dist.amount > 0, NothingToClaim());
        require(!dist.finalized, AlreadyFinalized());

        address holder = msg.sender;
        require(claimed[_distributionId][holder] == 0, AlreadyClaimed());

        uint256 votes = governanceToken.getPastVotes(holder, dist.snapshotBlock);
        require(votes > 0, NothingToClaim());

        uint256 share = (votes * dist.amount) / dist.totalTokenSupply;
        require(share > 0, NothingToClaim());

        claimed[_distributionId][holder] = share;
        dist.totalClaimed += share;

        // Check if distribution is fully claimed
        if (dist.totalClaimed >= dist.amount) {
            dist.finalized = true;
            emit DistributionFinalized(_distributionId);
        }

        // Use a separate variable to avoid storage collision issue
        uint256 payout = share;
        if (dist.totalClaimed > dist.amount) {
            // Dust correction: cap at remaining amount
            uint256 excess = dist.totalClaimed - dist.amount;
            payout = share - excess;
            dist.totalClaimed = dist.amount;
            claimed[_distributionId][holder] = payout;
            dist.finalized = true;
            emit DistributionFinalized(_distributionId);
        }

        usdc.safeTransfer(holder, payout);
        emit RevenueClaimed(_distributionId, holder, payout);
    }

    // ───────────── View Functions ─────────────

    /// @notice Get distribution details
    function getDistribution(uint256 _distributionId) external view returns (
        uint256 amount,
        uint256 snapshotBlock,
        uint256 totalTokenSupply,
        uint256 totalClaimed,
        bool finalized
    ) {
        Distribution storage dist = distributions[_distributionId];
        return (dist.amount, dist.snapshotBlock, dist.totalTokenSupply, dist.totalClaimed, dist.finalized);
    }

    /// @notice Calculate the claimable amount for a given holder and distribution
    function getClaimable(uint256 _distributionId, address _holder) external view returns (uint256) {
        Distribution storage dist = distributions[_distributionId];
        if (dist.amount == 0 || dist.finalized || claimed[_distributionId][_holder] > 0) return 0;

        uint256 votes = governanceToken.getPastVotes(_holder, dist.snapshotBlock);
        if (votes == 0) return 0;

        return (votes * dist.amount) / dist.totalTokenSupply;
    }

    /// @notice Get the current USDC balance held by the distributor
    function getBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /// @notice Check if an address has claimed for a specific distribution
    function hasClaimed(uint256 _distributionId, address _holder) external view returns (bool) {
        return claimed[_distributionId][_holder] > 0;
    }

    /// @notice Get the total claimed amount for a holder across all distributions
    function getTotalClaimedByHolder(address _holder) external view returns (uint256 total) {
        for (uint256 i = 0; i < distributionCount; i++) {
            total += claimed[i][_holder];
        }
    }

    /// @notice Get the unclaimed amount remaining in a distribution
    function getUnclaimed(uint256 _distributionId) external view returns (uint256) {
        Distribution storage dist = distributions[_distributionId];
        if (dist.amount == 0) return 0;
        return dist.amount - dist.totalClaimed;
    }
}
