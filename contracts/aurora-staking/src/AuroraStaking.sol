// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AuroraStaking
/// @notice Stake AURA tokens and earn rewards over time
/// @dev Features:
///      - Deposit/withdraw AURA tokens
///      - Per-second reward accrual based on share of total staked
///      - Configurable reward rate (tokens per second)
///      - Claim rewards separately or compound (restake rewards)
///      - Minimum stake amount
///      - Owner-funded reward pool with top-up
///      - ReentrancyGuard on all payable/token functions
contract AuroraStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Types ───

    error ZeroAmount();
    error InsufficientStake(uint256 requested, uint256 available);
    error InsufficientRewardPool(uint256 requested, uint256 available);
    error BelowMinimumStake(uint256 amount, uint256 minimum);
    error NoRewardsToClaim();
    error TransferFailed();

    // ─── Events ───

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardCompounded(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    event MinimumStakeUpdated(uint256 oldMinimum, uint256 newMinimum);
    event RewardPoolToppedUp(address indexed caller, uint256 amount);

    // ─── State ───

    /// @notice The AURA staking token
    IERC20 public immutable stakingToken;

    /// @notice Reward tokens per second distributed to all stakers
    uint256 public rewardRatePerSecond;

    /// @notice Minimum amount to stake
    uint256 public minimumStake;

    /// @notice Accumulated reward per token (scaled by 1e18)
    uint256 public rewardPerTokenStored;

    /// @notice Last time rewards were updated
    uint256 public lastUpdateTime;

    /// @notice Total tokens currently staked
    uint256 public totalStaked;

    /// @notice Total reward tokens available in the contract for distribution
    uint256 public rewardPool;

    /// @notice Per-user staking data
    struct UserInfo {
        uint256 staked; // tokens currently staked
        uint256 rewardDebt; // reward already accounted for
        uint256 rewardsAccrued; // unclaimed rewards
    }

    mapping(address => UserInfo) public users;

    // ─── Constructor ───

    /// @param _stakingToken AURA token address
    /// @param _rewardRatePerSecond Reward tokens per second for all stakers
    /// @param _minimumStake Minimum stake amount (0 to disable)
    /// @param owner_ Initial contract owner
    constructor(
        address _stakingToken,
        uint256 _rewardRatePerSecond,
        uint256 _minimumStake,
        address owner_
    ) Ownable(owner_) {
        stakingToken = IERC20(_stakingToken);
        rewardRatePerSecond = _rewardRatePerSecond;
        minimumStake = _minimumStake;
        lastUpdateTime = block.timestamp;
    }

    // ─── Staking ───

    /// @notice Stake AURA tokens to earn rewards
    /// @param amount Number of tokens to stake
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        _updateRewards(msg.sender);

        // If user has no existing stake, enforce minimum
        if (users[msg.sender].staked == 0 && amount < minimumStake) {
            revert BelowMinimumStake(amount, minimumStake);
        }

        users[msg.sender].staked += amount;
        totalStaked += amount;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /// @notice Withdraw staked tokens (full or partial)
    /// @param amount Number of tokens to withdraw
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        _updateRewards(msg.sender);

        if (users[msg.sender].staked < amount) {
            revert InsufficientStake(amount, users[msg.sender].staked);
        }

        users[msg.sender].staked -= amount;
        totalStaked -= amount;

        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Withdraw all staked tokens
    function withdrawAll() external nonReentrant {
        uint256 amount = users[msg.sender].staked;
        if (amount == 0) revert ZeroAmount();

        _updateRewards(msg.sender);

        users[msg.sender].staked = 0;
        totalStaked -= amount;

        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    // ─── Rewards ───

    /// @notice Claim accrued rewards without withdrawing stake
    function claimReward() external nonReentrant {
        _updateRewards(msg.sender);

        uint256 reward = users[msg.sender].rewardsAccrued;
        if (reward == 0) revert NoRewardsToClaim();

        users[msg.sender].rewardsAccrued = 0;

        if (reward > rewardPool) {
            reward = rewardPool; // pay what's available
        }
        rewardPool -= reward;

        stakingToken.safeTransfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    /// @notice Claim rewards and restake them (compound)
    function compoundReward() external nonReentrant {
        _updateRewards(msg.sender);

        uint256 reward = users[msg.sender].rewardsAccrued;
        if (reward == 0) revert NoRewardsToClaim();

        users[msg.sender].rewardsAccrued = 0;

        if (reward > rewardPool) {
            reward = rewardPool;
        }
        rewardPool -= reward;

        // Restake the reward
        users[msg.sender].staked += reward;
        totalStaked += reward;

        // Update rewardDebt to account for the increased stake
        users[msg.sender].rewardDebt = users[msg.sender].staked * rewardPerTokenStored;

        // Tokens are already in contract, no transfer needed

        emit RewardCompounded(msg.sender, reward);
    }

    /// @notice View pending rewards for a user (does not modify state)
    /// @param account Address to check
    /// @return pending Unclaimed rewards
    function pendingReward(address account) public view returns (uint256 pending) {
        UserInfo storage u = users[account];
        uint256 currentRewardPerToken = rewardPerTokenStored;

        if (totalStaked > 0) {
            currentRewardPerToken += _earnedPerTokenSinceLastUpdate();
        }

        if (u.staked == 0) {
            return u.rewardsAccrued;
        }

        uint256 cumulativeReward = u.staked * currentRewardPerToken;
        if (cumulativeReward > u.rewardDebt) {
            pending = u.rewardsAccrued + (cumulativeReward - u.rewardDebt) / 1e18;
        } else {
            pending = u.rewardsAccrued;
        }
    }

    // ─── Owner Functions ───

    /// @notice Top up the reward pool from the caller's balance
    /// @param amount Number of reward tokens to add
    function topUpRewardPool(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert ZeroAmount();

        _updateGlobalRewards();

        rewardPool += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit RewardPoolToppedUp(msg.sender, amount);
    }

    /// @notice Update the reward rate (tokens per second)
    /// @param newRate New reward rate per second
    function setRewardRate(uint256 newRate) external onlyOwner {
        _updateGlobalRewards();

        uint256 oldRate = rewardRatePerSecond;
        rewardRatePerSecond = newRate;

        emit RewardRateUpdated(oldRate, newRate);
    }

    /// @notice Update the minimum stake amount
    /// @param newMinimum New minimum stake
    function setMinimumStake(uint256 newMinimum) external onlyOwner {
        uint256 oldMinimum = minimumStake;
        minimumStake = newMinimum;

        emit MinimumStakeUpdated(oldMinimum, newMinimum);
    }

    /// @notice Recover ERC-20 tokens accidentally sent to this contract (not staking token)
    /// @param token Address of the token to recover
    /// @param amount Amount to recover
    function recoverToken(address token, uint256 amount) external onlyOwner {
        require(token != address(stakingToken), "Cannot recover staking token");
        IERC20(token).safeTransfer(owner(), amount);
    }

    // ─── Internal ───

    /// @dev Update global reward accounting
    function _updateGlobalRewards() internal {
        rewardPerTokenStored += _earnedPerTokenSinceLastUpdate();
        lastUpdateTime = block.timestamp;
    }

    /// @dev Calculate reward per token accrued since last update
    function _earnedPerTokenSinceLastUpdate() internal view returns (uint256) {
        if (totalStaked == 0) return 0;

        uint256 timeDelta = block.timestamp - lastUpdateTime;
        uint256 totalReward = timeDelta * rewardRatePerSecond;

        // Cap to available reward pool
        if (totalReward > rewardPool) {
            totalReward = rewardPool;
        }

        return (totalReward * 1e18) / totalStaked;
    }

    /// @dev Update a user's reward accounting
    function _updateRewards(address account) internal {
        _updateGlobalRewards();

        UserInfo storage u = users[account];

        if (u.staked > 0) {
            uint256 earned = (u.staked * rewardPerTokenStored - u.rewardDebt) / 1e18;
            u.rewardsAccrued += earned;
        }

        u.rewardDebt = u.staked * rewardPerTokenStored;
    }
}
