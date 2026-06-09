// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TaskEscrow
/// @notice On-chain freelance marketplace with USDC escrow on Base
/// @dev 3% platform fee. Client posts job → freelancer accepted → funds released on completion.
contract TaskEscrow is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Status { Open, InProgress, Completed, Cancelled, Disputed }

    struct Job {
        address client;
        address freelancer;
        address[] applicants;
        IERC20 token;         // payment token (USDC)
        uint256 amount;        // total payment in token units
        string description;    // job description
        Status status;
        uint256 createdAt;
    }

    Job[] public jobs;

    uint256 public platformFee = 300; // 3% = 300 bps
    uint256 public constant MAX_FEE = 1000; // 10% max
    address public platformTreasury;

    event JobCreated(uint256 indexed jobId, address indexed client, uint256 amount, string description);
    event JobApplied(uint256 indexed jobId, address indexed freelancer);
    event FreelancerAccepted(uint256 indexed jobId, address indexed freelancer);
    event JobCompleted(uint256 indexed jobId, address indexed freelancer, uint256 amount, uint256 fee);
    event JobCancelled(uint256 indexed jobId, address indexed client);
    event JobDisputed(uint256 indexed jobId, address indexed disputer);
    event PlatformFeeUpdated(uint256 newFee);

    error NotClient();
    error NotFreelancer();
    error NotClientOrFreelancer();
    error InvalidStatus(Status current);
    error AlreadyApplied();
    error NoFreelancerAccepted();
    error TransferFailed();

    constructor(address _treasury) Ownable(msg.sender) {
        platformTreasury = _treasury;
    }

    /// @notice Set platform fee in basis points (e.g. 300 = 3%)
    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_FEE, "Fee too high");
        platformFee = _fee;
        emit PlatformFeeUpdated(_fee);
    }

    /// @notice Set platform treasury address
    function setPlatformTreasury(address _treasury) external onlyOwner {
        platformTreasury = _treasury;
    }

    /// @notice Client creates a job and deposits USDC into escrow
    function createJob(IERC20 _token, uint256 _amount, string calldata _description) external nonReentrant returns (uint256) {
        require(_amount > 0, "Amount must be > 0");
        require(bytes(_description).length > 0, "Description required");

        uint256 jobId = jobs.length;
        jobs.push(Job({
            client: msg.sender,
            freelancer: address(0),
            applicants: new address[](0),
            token: _token,
            amount: _amount,
            description: _description,
            status: Status.Open,
            createdAt: block.timestamp
        }));

        // Transfer USDC from client to contract
        _token.safeTransferFrom(msg.sender, address(this), _amount);

        emit JobCreated(jobId, msg.sender, _amount, _description);
        return jobId;
    }

    /// @notice Freelancer applies to an open job
    function applyToJob(uint256 _jobId) external {
        Job storage job = jobs[_jobId];
        if (job.status != Status.Open) revert InvalidStatus(job.status);
        if (msg.sender == job.client) revert AlreadyApplied();

        // Check not already applied
        for (uint256 i = 0; i < job.applicants.length; i++) {
            if (job.applicants[i] == msg.sender) revert AlreadyApplied();
        }

        job.applicants.push(msg.sender);
        emit JobApplied(_jobId, msg.sender);
    }

    /// @notice Client accepts a freelancer from the applicants
    function acceptFreelancer(uint256 _jobId, address _freelancer) external {
        Job storage job = jobs[_jobId];
        if (msg.sender != job.client) revert NotClient();
        if (job.status != Status.Open) revert InvalidStatus(job.status);

        bool found = false;
        for (uint256 i = 0; i < job.applicants.length; i++) {
            if (job.applicants[i] == _freelancer) {
                found = true;
                break;
            }
        }
        require(found, "Freelancer not in applicants");

        job.freelancer = _freelancer;
        job.status = Status.InProgress;
        emit FreelancerAccepted(_jobId, _freelancer);
    }

    /// @notice Client marks job complete → releases funds to freelancer (minus fee)
    function completeJob(uint256 _jobId) external nonReentrant {
        Job storage job = jobs[_jobId];
        if (msg.sender != job.client) revert NotClient();
        if (job.status != Status.InProgress) revert InvalidStatus(job.status);

        job.status = Status.Completed;

        uint256 fee = (job.amount * platformFee) / 10000;
        uint256 payout = job.amount - fee;

        // Pay freelancer
        job.token.safeTransfer(job.freelancer, payout);
        // Pay platform fee
        if (fee > 0) {
            job.token.safeTransfer(platformTreasury, fee);
        }

        emit JobCompleted(_jobId, job.freelancer, payout, fee);
    }

    /// @notice Client cancels job (only if no freelancer accepted)
    function cancelJob(uint256 _jobId) external nonReentrant {
        Job storage job = jobs[_jobId];
        if (msg.sender != job.client) revert NotClient();
        if (job.status != Status.Open) revert InvalidStatus(job.status);

        job.status = Status.Cancelled;
        job.token.safeTransfer(job.client, job.amount);

        emit JobCancelled(_jobId, job.client);
    }

    /// @notice Either party can open a dispute
    function disputeJob(uint256 _jobId) external {
        Job storage job = jobs[_jobId];
        if (msg.sender != job.client && msg.sender != job.freelancer) revert NotClientOrFreelancer();
        if (job.status != Status.InProgress) revert InvalidStatus(job.status);

        job.status = Status.Disputed;
        emit JobDisputed(_jobId, msg.sender);
    }

    /// @notice Owner resolves dispute → releases funds to freelancer or refunds client
    function resolveDispute(uint256 _jobId, bool payFreelancer) external onlyOwner nonReentrant {
        Job storage job = jobs[_jobId];
        require(job.status == Status.Disputed, "Not disputed");

        job.status = payFreelancer ? Status.Completed : Status.Cancelled;

        uint256 fee = (job.amount * platformFee) / 10000;
        uint256 payout = job.amount - fee;

        if (payFreelancer) {
            job.token.safeTransfer(job.freelancer, payout);
            if (fee > 0) {
                job.token.safeTransfer(platformTreasury, fee);
            }
        } else {
            job.token.safeTransfer(job.client, job.amount);
        }
    }

    /// @notice Get all job IDs
    function jobCount() external view returns (uint256) {
        return jobs.length;
    }

    /// @notice Get applicants for a job
    function getApplicants(uint256 _jobId) external view returns (address[] memory) {
        return jobs[_jobId].applicants;
    }
}
