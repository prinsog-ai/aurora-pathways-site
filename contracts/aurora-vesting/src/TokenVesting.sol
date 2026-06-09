// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TokenVesting
/// @notice Linear token vesting with cliff for the Aurora Pathways ecosystem
/// @dev Owner creates vesting schedules. Beneficiaries claim vested tokens over time.
contract TokenVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Schedule {
        address beneficiary;
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 startTime;
        uint256 cliffDuration;
        uint256 vestingDuration;
        bool revocable;
        bool revoked;
        uint256 revokedAt;
    }

    /// @notice The ERC-20 token being vested
    IERC20 public immutable token;

    /// @notice Total tokens allocated across all schedules
    uint256 public totalAllocated;

    /// @notice Total tokens claimed across all schedules
    uint256 public totalClaimed;

    /// @notice Schedule ID counter
    uint256 public scheduleCount;

    /// @notice Mapping from schedule ID to Schedule
    mapping(uint256 => Schedule) public schedules;

    /// @notice Mapping from beneficiary to their schedule IDs
    mapping(address => uint256[]) public beneficiarySchedules;

    event ScheduleCreated(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration,
        bool revocable
    );
    event TokensClaimed(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount);
    event ScheduleRevoked(uint256 indexed scheduleId, uint256 unvestedAmount);

    error InvalidDuration();
    error InvalidAmount();
    error ScheduleRevokedError(uint256 scheduleId);
    error NothingToClaim();
    error NotRevocable(uint256 scheduleId);
    error Unauthorized();

    /// @param _token The ERC-20 token to vest
    /// @param initialOwner Owner who can create schedules
    constructor(address _token, address initialOwner) Ownable(initialOwner) {
        require(_token != address(0), "Invalid token");
        token = IERC20(_token);
    }

    /// @notice Create a new vesting schedule — only owner
    /// @param beneficiary Who receives the vested tokens
    /// @param totalAmount Total tokens to vest over the full period
    /// @param startTime Timestamp when vesting begins
    /// @param cliffDuration Seconds before first unlock (0 = no cliff)
    /// @param vestingDuration Seconds from startTime until fully vested
    /// @param revocable Whether the owner can revoke unvested tokens
    /// @return scheduleId The new schedule ID
    function createSchedule(
        address beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration,
        bool revocable
    ) external onlyOwner returns (uint256 scheduleId) {
        if (totalAmount == 0) revert InvalidAmount();
        if (vestingDuration == 0) revert InvalidDuration();
        if (beneficiary == address(0)) revert InvalidAmount();

        // Transfer tokens from owner to this contract
        token.safeTransferFrom(msg.sender, address(this), totalAmount);

        scheduleId = scheduleCount;
        schedules[scheduleId] = Schedule({
            beneficiary: beneficiary,
            totalAmount: totalAmount,
            claimedAmount: 0,
            startTime: startTime,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            revocable: revocable,
            revoked: false,
            revokedAt: 0
        });

        beneficiarySchedules[beneficiary].push(scheduleId);
        scheduleCount++;
        totalAllocated += totalAmount;

        emit ScheduleCreated(
            scheduleId, beneficiary, totalAmount, startTime, cliffDuration, vestingDuration, revocable
        );
    }

    /// @notice Calculate how many tokens are vested for a schedule
    /// @param scheduleId The schedule ID
    /// @return vested The number of tokens currently vested
    function vestedAmount(uint256 scheduleId) public view returns (uint256 vested) {
        Schedule storage s = schedules[scheduleId];
        if (s.totalAmount == 0) return 0;

        // Before cliff: nothing vested
        if (block.timestamp < s.startTime + s.cliffDuration) {
            return 0;
        }

        // Compute the effective time bounds
        uint256 effectiveTime = block.timestamp;
        uint256 maxTime = s.startTime + s.vestingDuration;

        // If revoked, cap at the time of revocation
        if (s.revoked && s.revokedAt < maxTime) {
            maxTime = s.revokedAt;
        }

        if (effectiveTime > maxTime) {
            effectiveTime = maxTime;
        }

        // Linear vesting: proportional to time elapsed
        vested = (s.totalAmount * (effectiveTime - s.startTime)) / s.vestingDuration;
    }

    /// @notice Calculate how many tokens are claimable for a schedule
    /// @param scheduleId The schedule ID
    /// @return claimable Number of tokens available to claim
    function claimableAmount(uint256 scheduleId) public view returns (uint256 claimable) {
        Schedule storage s = schedules[scheduleId];
        uint256 vested = vestedAmount(scheduleId);
        if (vested <= s.claimedAmount) return 0;
        return vested - s.claimedAmount;
    }

    /// @notice Claim vested tokens — anyone can call for any schedule
    /// @param scheduleId The schedule to claim from
    function claim(uint256 scheduleId) external nonReentrant {
        Schedule storage s = schedules[scheduleId];
        if (s.revoked) revert ScheduleRevokedError(scheduleId);

        uint256 amount = claimableAmount(scheduleId);
        if (amount == 0) revert NothingToClaim();

        s.claimedAmount += amount;
        totalClaimed += amount;

        token.safeTransfer(s.beneficiary, amount);

        emit TokensClaimed(scheduleId, s.beneficiary, amount);
    }

    /// @notice Revoke a vesting schedule and return unvested tokens to owner
    /// @param scheduleId The schedule to revoke
    function revoke(uint256 scheduleId) external onlyOwner {
        Schedule storage s = schedules[scheduleId];
        if (!s.revocable) revert NotRevocable(scheduleId);
        if (s.revoked) revert ScheduleRevokedError(scheduleId);

        s.revoked = true;
        s.revokedAt = block.timestamp;

        uint256 vested = vestedAmount(scheduleId);
        uint256 unvested = s.totalAmount - vested;

        // Update allocated total (remove what's no longer allocated)
        totalAllocated -= unvested;

        // Return unvested tokens to owner
        if (unvested > 0) {
            token.safeTransfer(owner(), unvested);
        }

        emit ScheduleRevoked(scheduleId, unvested);
    }

    /// @notice Get all schedule IDs for a beneficiary
    /// @param beneficiary The beneficiary address
    /// @return ids Array of schedule IDs
    function getBeneficiarySchedules(address beneficiary) external view returns (uint256[] memory ids) {
        return beneficiarySchedules[beneficiary];
    }

    /// @notice Get number of schedules for a beneficiary
    /// @param beneficiary The beneficiary address
    /// @return count Number of schedules
    function beneficiaryScheduleCount(address beneficiary) external view returns (uint256 count) {
        return beneficiarySchedules[beneficiary].length;
    }
}