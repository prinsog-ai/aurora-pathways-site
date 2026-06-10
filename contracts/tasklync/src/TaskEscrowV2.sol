// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TaskEscrowV2
/// @notice Upgraded freelance marketplace: milestones, deadlines, on-chain reputation, multi-sig jury disputes
/// @dev 3% platform fee. Milestone-based payments. 3-of-5 jury dispute resolution.
contract TaskEscrowV2 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ───────────── Enums ─────────────

    enum Status { Open, InProgress, Completed, Cancelled, Disputed }

    enum MilestoneStatus { Pending, Released, Refunded }

    // ───────────── Structs ─────────────

    struct MilestoneDesc {
        string description;
        uint256 amount;
    }

    struct Milestone {
        string description;
        uint256 amount;
        MilestoneStatus status;
    }

    struct Job {
        address client;
        address freelancer;
        address[] applicants;
        IERC20 token;
        uint256 amount;          // total across all milestones
        string description;
        string category;         // free-form tag for filtering
        Status status;
        uint256 createdAt;
        uint256 deadline;        // unix timestamp
        Milestone[] milestones;
        bool rated;              // prevent double-rating
    }

    struct Reputation {
        uint256 completedJobs;
        uint256 totalRating;     // sum of all ratings (1-5)
        uint256 ratingCount;
    }

    // ───────────── Storage ─────────────

    Job[] public jobs;

    mapping(address => Reputation) private _reputations;

    // Jury — fixed-size array of 5, set by owner
    address[5] public jury;
    bool[5] public jurySlotUsed;

    // Dispute vote tracking: jobId => juror => hasVoted
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    // jobId => juror => vote (true = payFreelancer, false = refundClient)
    mapping(uint256 => mapping(address => bool)) public voteValue;
    // jobId => vote counts
    mapping(uint256 => uint256) public votesForFreelancer;
    mapping(uint256 => uint256) public votesForClient;
    // jobId => dispute resolved flag
    mapping(uint256 => bool) public disputeResolved;

    // Quick lookup: has address applied to a given job (avoids O(n) loop)
    mapping(uint256 => mapping(address => bool)) public hasApplied;

    uint256 public platformFee = 300; // 3% = 300 bps
    uint256 public constant MAX_FEE = 1000; // 10% max
    address public platformTreasury;

    // ───────────── Events ─────────────

    event JobCreated(uint256 indexed jobId, address indexed client, uint256 amount, string description, string category, uint256 deadline);
    event ApplicantAdded(uint256 indexed jobId, address indexed applicant);
    event FreelancerAccepted(uint256 indexed jobId, address indexed freelancer);
    event MilestoneReleased(uint256 indexed jobId, uint256 indexed milestoneIndex, address indexed freelancer, uint256 payout, uint256 fee);
    event JobCompleted(uint256 indexed jobId, address indexed freelancer);
    event JobCancelled(uint256 indexed jobId, address indexed client);
    event JobDisputed(uint256 indexed jobId, address indexed disputer);
    event DeadlineRefund(uint256 indexed jobId, address indexed client, uint256 amount);
    event PlatformFeeUpdated(uint256 newFee);
    event JuryUpdated(uint256 indexed slot, address indexed juror);
    event FreelancerRated(uint256 indexed jobId, address indexed freelancer, uint256 rating);
    event DisputeVoteCast(uint256 indexed jobId, address indexed juror, bool payFreelancer);
    event DisputeResolved(uint256 indexed jobId, bool payFreelancer);
    event PlatformTreasuryUpdated(address newTreasury);

    // ───────────── Errors ─────────────

    error NotClient();
    error NotClientOrFreelancer();
    error InvalidStatus(Status current);
    error AlreadyApplied();
    error DeadlineNotPassed();
    error InvalidMilestoneIndex();
    error MilestoneAlreadyProcessed();
    error InvalidRating();
    error AlreadyRated();
    error NotJuror();
    error AlreadyVoted();
    error DeadlineMustBeFuture();
    error MilestonesRequired();
    error AmountMustBePositive();
    error DescriptionRequired();
    error NotDisputed();
    error ZeroAddress();

    // ───────────── Constructor ─────────────

    constructor(address _treasury) Ownable(msg.sender) {
        require(_treasury != address(0), ZeroAddress());
        platformTreasury = _treasury;
    }

    // ───────────── Admin ─────────────

    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_FEE, "Fee too high");
        platformFee = _fee;
        emit PlatformFeeUpdated(_fee);
    }

    function setPlatformTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), ZeroAddress());
        platformTreasury = _treasury;
        emit PlatformTreasuryUpdated(_treasury);
    }

    /// @notice Set a jury member at a specific slot (0-4)
    /// @dev WARNING: This is a known centralization risk. Replacing a juror while
    ///      disputes are active could affect dispute outcomes. Owner should avoid
    ///      changing jurors during active disputes.
    function setJuror(uint256 _slot, address _juror) external onlyOwner {
        require(_slot < 5, "Slot out of range");
        require(_juror != address(0), ZeroAddress());
        // Check no duplicates
        for (uint256 i = 0; i < 5; i++) {
            if (i != _slot && jurySlotUsed[i]) {
                require(jury[i] != _juror, "Duplicate juror");
            }
        }
        jury[_slot] = _juror;
        jurySlotUsed[_slot] = true;
        emit JuryUpdated(_slot, _juror);
    }

    /// @notice Convenience: set all 5 jury members at once
    function setJury(address[5] calldata _jurors) external onlyOwner {
        for (uint256 i = 0; i < 5; i++) {
            require(_jurors[i] != address(0), ZeroAddress());
            for (uint256 j = i + 1; j < 5; j++) {
                require(_jurors[i] != _jurors[j], "Duplicate juror");
            }
        }
        for (uint256 i = 0; i < 5; i++) {
            jury[i] = _jurors[i];
            jurySlotUsed[i] = true;
            emit JuryUpdated(i, _jurors[i]);
        }
    }

    // ───────────── Job Lifecycle ─────────────

    /// @notice Client creates a job with milestones, category, and deadline.
    /// @dev Total amount is sum of milestone amounts. Transferred from client upfront.
    function createJob(
        IERC20 _token,
        string calldata _description,
        string calldata _category,
        uint256 _deadline,
        MilestoneDesc[] calldata _milestones
    ) external nonReentrant returns (uint256) {
        require(_deadline > block.timestamp, DeadlineMustBeFuture());
        require(_milestones.length > 0, MilestonesRequired());
        require(_milestones.length <= 20, "Too many milestones");
        require(bytes(_description).length > 0, DescriptionRequired());

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _milestones.length; i++) {
            totalAmount += _milestones[i].amount;
        }
        require(totalAmount > 0, AmountMustBePositive());

        uint256 jobId = jobs.length;

        // Push empty job first, then populate fields to avoid memory-to-storage copy
        jobs.push();
        Job storage job = jobs[jobId];
        job.client = msg.sender;
        job.token = _token;
        job.amount = totalAmount;
        job.description = _description;
        job.category = _category;
        job.status = Status.Open;
        job.createdAt = block.timestamp;
        job.deadline = _deadline;

        for (uint256 i = 0; i < _milestones.length; i++) {
            job.milestones.push(Milestone({
                description: _milestones[i].description,
                amount: _milestones[i].amount,
                status: MilestoneStatus.Pending
            }));
        }

        // Transfer total from client to contract
        _token.safeTransferFrom(msg.sender, address(this), totalAmount);

        emit JobCreated(jobId, msg.sender, totalAmount, _description, _category, _deadline);
        return jobId;
    }

    /// @notice Freelancer applies to an open job. Emits ApplicantAdded event.
    function applyToJob(uint256 _jobId) external {
        Job storage job = jobs[_jobId];
        if (job.status != Status.Open) revert InvalidStatus(job.status);
        if (msg.sender == job.client) revert AlreadyApplied();

        if (hasApplied[_jobId][msg.sender]) revert AlreadyApplied();

        hasApplied[_jobId][msg.sender] = true;
        job.applicants.push(msg.sender);
        emit ApplicantAdded(_jobId, msg.sender);
    }

    /// @notice Client accepts a freelancer from the applicants
    function acceptFreelancer(uint256 _jobId, address _freelancer) external {
        Job storage job = jobs[_jobId];
        if (msg.sender != job.client) revert NotClient();
        if (job.status != Status.Open) revert InvalidStatus(job.status);

        require(hasApplied[_jobId][_freelancer], "Not an applicant");

        job.freelancer = _freelancer;
        job.status = Status.InProgress;
        emit FreelancerAccepted(_jobId, _freelancer);
    }

    /// @notice Client releases a specific milestone payment (minus 3% platform fee)
    function releaseMilestone(uint256 _jobId, uint256 _milestoneIndex) external nonReentrant {
        Job storage job = jobs[_jobId];
        if (msg.sender != job.client) revert NotClient();
        if (job.status != Status.InProgress) revert InvalidStatus(job.status);
        if (_milestoneIndex >= job.milestones.length) revert InvalidMilestoneIndex();

        Milestone storage ms = job.milestones[_milestoneIndex];
        if (ms.status != MilestoneStatus.Pending) revert MilestoneAlreadyProcessed();

        ms.status = MilestoneStatus.Released;

        uint256 fee = (ms.amount * platformFee) / 10000;
        uint256 payout = ms.amount - fee;

        job.token.safeTransfer(job.freelancer, payout);
        if (fee > 0) {
            job.token.safeTransfer(platformTreasury, fee);
        }

        emit MilestoneReleased(_jobId, _milestoneIndex, job.freelancer, payout, fee);
    }

    /// @notice Client marks job as completed. All milestones must be released first.
    function completeJob(uint256 _jobId) external {
        Job storage job = jobs[_jobId];
        if (msg.sender != job.client) revert NotClient();
        if (job.status != Status.InProgress) revert InvalidStatus(job.status);

        // Verify all milestones released
        for (uint256 i = 0; i < job.milestones.length; i++) {
            require(job.milestones[i].status == MilestoneStatus.Released, "Milestone not released");
        }

        job.status = Status.Completed;

        Reputation storage rep = _reputations[job.freelancer];
        rep.completedJobs++;

        emit JobCompleted(_jobId, job.freelancer);
    }

    /// @notice Client cancels an open job → full refund
    function cancelJob(uint256 _jobId) external nonReentrant {
        Job storage job = jobs[_jobId];
        if (msg.sender != job.client) revert NotClient();
        if (job.status != Status.Open) revert InvalidStatus(job.status);

        job.status = Status.Cancelled;
        job.token.safeTransfer(job.client, job.amount);

        emit JobCancelled(_jobId, job.client);
    }

    /// @notice Anyone can claim a refund if the deadline has passed and job is InProgress.
    /// @dev Refunds only un-released milestones back to the client.
    function claimRefund(uint256 _jobId) external nonReentrant {
        Job storage job = jobs[_jobId];
        require(msg.sender == job.client || msg.sender == job.freelancer, "Not authorized");
        if (job.status != Status.InProgress) revert InvalidStatus(job.status);
        if (block.timestamp <= job.deadline) revert DeadlineNotPassed();

        job.status = Status.Cancelled;

        uint256 refundAmount = 0;
        for (uint256 i = 0; i < job.milestones.length; i++) {
            if (job.milestones[i].status == MilestoneStatus.Pending) {
                refundAmount += job.milestones[i].amount;
                job.milestones[i].status = MilestoneStatus.Refunded;
            }
        }

        if (refundAmount > 0) {
            job.token.safeTransfer(job.client, refundAmount);
        }

        emit DeadlineRefund(_jobId, job.client, refundAmount);
    }

    // ───────────── Dispute System ─────────────

    /// @notice Either party can open a dispute
    function disputeJob(uint256 _jobId) external {
        Job storage job = jobs[_jobId];
        if (msg.sender != job.client && msg.sender != job.freelancer) revert NotClientOrFreelancer();
        if (job.status != Status.InProgress) revert InvalidStatus(job.status);

        job.status = Status.Disputed;
        emit JobDisputed(_jobId, msg.sender);
    }

    /// @notice A jury member votes on a dispute. true = payFreelancer, false = refundClient.
    /// @dev Resolves automatically when 3 votes are reached for one side.
    function voteDispute(uint256 _jobId, bool _payFreelancer) external nonReentrant {
        Job storage job = jobs[_jobId];
        if (job.status != Status.Disputed) revert NotDisputed();
        if (disputeResolved[_jobId]) revert NotDisputed();

        // Verify caller is a juror
        bool _isJuror = false;
        for (uint256 i = 0; i < 5; i++) {
            if (jurySlotUsed[i] && jury[i] == msg.sender) {
                _isJuror = true;
                break;
            }
        }
        if (!_isJuror) revert NotJuror();
        if (hasVoted[_jobId][msg.sender]) revert AlreadyVoted();

        hasVoted[_jobId][msg.sender] = true;
        voteValue[_jobId][msg.sender] = _payFreelancer;

        if (_payFreelancer) {
            votesForFreelancer[_jobId]++;
        } else {
            votesForClient[_jobId]++;
        }

        emit DisputeVoteCast(_jobId, msg.sender, _payFreelancer);

        // Auto-resolve at 3 votes
        if (votesForFreelancer[_jobId] >= 3) {
            _resolveDispute(_jobId, true);
        } else if (votesForClient[_jobId] >= 3) {
            _resolveDispute(_jobId, false);
        }
    }

    /// @dev Internal: execute dispute resolution. Pays freelancer (minus fee) or refunds client.
    function _resolveDispute(uint256 _jobId, bool _payFreelancer) internal {
        Job storage job = jobs[_jobId];
        disputeResolved[_jobId] = true;

        // Calculate un-released milestone amounts
        uint256 pendingAmount = 0;
        for (uint256 i = 0; i < job.milestones.length; i++) {
            if (job.milestones[i].status == MilestoneStatus.Pending) {
                pendingAmount += job.milestones[i].amount;
                job.milestones[i].status = MilestoneStatus.Released; // mark as processed
            }
        }

        if (_payFreelancer) {
            job.status = Status.Completed;
            if (pendingAmount > 0) {
                uint256 fee = (pendingAmount * platformFee) / 10000;
                uint256 payout = pendingAmount - fee;
                job.token.safeTransfer(job.freelancer, payout);
                if (fee > 0) {
                    job.token.safeTransfer(platformTreasury, fee);
                }
            }
            Reputation storage rep = _reputations[job.freelancer];
            rep.completedJobs++;
        } else {
            job.status = Status.Cancelled;
            if (pendingAmount > 0) {
                job.token.safeTransfer(job.client, pendingAmount);
            }
        }

        emit DisputeResolved(_jobId, _payFreelancer);
    }

    // ───────────── Reputation ─────────────

    /// @notice Client rates freelancer 1-5 after job completion (one rating per job)
    function rateFreelancer(uint256 _jobId, uint256 _rating) external {
        Job storage job = jobs[_jobId];
        if (msg.sender != job.client) revert NotClient();
        if (job.status != Status.Completed) revert InvalidStatus(job.status);
        if (_rating < 1 || _rating > 5) revert InvalidRating();
        if (job.rated) revert AlreadyRated();

        job.rated = true;

        Reputation storage rep = _reputations[job.freelancer];
        rep.totalRating += _rating;
        rep.ratingCount++;

        emit FreelancerRated(_jobId, job.freelancer, _rating);
    }

    /// @notice Get reputation data for an address
    /// @return completedJobs_ Number of completed jobs
    /// @return averageRating_ Average rating * 100 for precision (e.g. 450 = 4.5, 0 if no ratings)
    function getReputation(address _freelancer) external view returns (uint256 completedJobs_, uint256 averageRating_) {
        Reputation storage rep = _reputations[_freelancer];
        completedJobs_ = rep.completedJobs;
        if (rep.ratingCount > 0) {
            averageRating_ = (rep.totalRating * 100) / rep.ratingCount;
        }
    }

    // ───────────── View / Pagination ─────────────

    /// @notice Total number of jobs
    function jobCount() external view returns (uint256) {
        return jobs.length;
    }

    /// @notice Get applicants for a job
    function getApplicants(uint256 _jobId) external view returns (address[] memory) {
        return jobs[_jobId].applicants;
    }

    /// @notice Get milestones for a job
    /// @notice Get milestone data for a job (avoids struct array copy issue)
    function getMilestone(uint256 _jobId, uint256 _milestoneId) external view returns (
        string memory description,
        uint256 amount,
        MilestoneStatus milestoneStatus
    ) {
        Milestone storage ms = jobs[_jobId].milestones[_milestoneId];
        return (ms.description, ms.amount, ms.status);
    }

    /// @notice Paginated job listing returning parallel arrays of job data
    function getJobs(uint256 _offset, uint256 _limit) external view returns (
        uint256[] memory ids,
        address[] memory clients,
        address[] memory freelancers,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        string[] memory descriptions,
        string[] memory categories,
        Status[] memory statuses,
        uint256[] memory createdAts,
        uint256[] memory deadlines
    ) {
        uint256 total = jobs.length;
        uint256 start = _offset > total ? total : _offset;
        uint256 end = _offset + _limit;
        if (end > total) end = total;
        uint256 len = end > start ? end - start : 0;

        ids = new uint256[](len);
        clients = new address[](len);
        freelancers = new address[](len);
        tokens = new IERC20[](len);
        amounts = new uint256[](len);
        descriptions = new string[](len);
        categories = new string[](len);
        statuses = new Status[](len);
        createdAts = new uint256[](len);
        deadlines = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            Job storage job = jobs[start + i];
            ids[i] = start + i;
            clients[i] = job.client;
            freelancers[i] = job.freelancer;
            tokens[i] = job.token;
            amounts[i] = job.amount;
            descriptions[i] = job.description;
            categories[i] = job.category;
            statuses[i] = job.status;
            createdAts[i] = job.createdAt;
            deadlines[i] = job.deadline;
        }
    }

    /// @notice Get a single job's full details
    function getJob(uint256 _jobId) external view returns (
        address client,
        address freelancer,
        IERC20 token,
        uint256 amount,
        string memory description,
        string memory category,
        Status status,
        uint256 createdAt,
        uint256 deadline,
        uint256 milestoneCount
    ) {
        Job storage job = jobs[_jobId];
        return (
            job.client,
            job.freelancer,
            job.token,
            job.amount,
            job.description,
            job.category,
            job.status,
            job.createdAt,
            job.deadline,
            job.milestones.length
        );
    }

    /// @notice Check if an address is a current juror
    function isJuror(address _addr) external view returns (bool) {
        for (uint256 i = 0; i < 5; i++) {
            if (jurySlotUsed[i] && jury[i] == _addr) return true;
        }
        return false;
    }

    /// @notice Get dispute vote tallies
    function getDisputeVotes(uint256 _jobId) external view returns (uint256 forFreelancer, uint256 forClient) {
        return (votesForFreelancer[_jobId], votesForClient[_jobId]);
    }
}
