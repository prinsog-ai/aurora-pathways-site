// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title TaskEscrowV3
/// @notice Scalable freelance marketplace: UUPS upgradeable, batch operations, dynamic jury pool
/// @dev Upgraded from V2: dynamic jury size, batch create/release, UUPS proxy pattern
contract TaskEscrowV3 is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
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
        uint256 amount;
        string description;
        string category;
        Status status;
        uint256 createdAt;
        uint256 deadline;
        Milestone[] milestones;
        bool rated;
    }

    struct Reputation {
        uint256 completedJobs;
        uint256 totalRating;
        uint256 ratingCount;
    }

    // ───────────── Storage ─────────────

    uint256 private _jobCounter;
    mapping(uint256 => Job) private _jobs;

    mapping(address => Reputation) private _reputations;

    // Dynamic jury pool — no fixed-size array
    address[] public juryPool;
    mapping(address => bool) public isJuror;

    // Dispute tracking
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(address => bool)) public voteValue;
    mapping(uint256 => uint256) public votesForFreelancer;
    mapping(uint256 => uint256) public votesForClient;
    mapping(uint256 => bool) public disputeResolved;

    // Quick lookup for applications
    mapping(uint256 => mapping(address => bool)) public hasApplied;

    uint256 public platformFee = 300; // 3%
    uint256 public constant MAX_FEE = 1000; // 10% max
    address public platformTreasury;

    // Quorum: how many jury votes needed to resolve (default 3)
    uint256 public juryQuorum = 3;

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
    event JurorAdded(address indexed juror);
    event JurorRemoved(address indexed juror);
    event JuryQuorumUpdated(uint256 newQuorum);
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
    error QuorumTooHigh();
    error BatchEmpty();
    error ArrayLengthMismatch();

    // ───────────── Initializer ─────────────

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _treasury) public initializer {
        require(_treasury != address(0), ZeroAddress());
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        platformTreasury = _treasury;
    }

    // ───────────── UUPS Authorization ─────────────

    function _authorizeUpgrade(address) internal override onlyOwner {}

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

    function setJuryQuorum(uint256 _quorum) external onlyOwner {
        require(_quorum > 0, "Quorum must be > 0");
        require(_quorum <= juryPool.length, QuorumTooHigh());
        juryQuorum = _quorum;
        emit JuryQuorumUpdated(_quorum);
    }

    // ───────────── Dynamic Jury Management ─────────────

    function addJuror(address _juror) external onlyOwner {
        require(_juror != address(0), ZeroAddress());
        require(!isJuror[_juror], "Already a juror");
        isJuror[_juror] = true;
        juryPool.push(_juror);
        emit JurorAdded(_juror);
    }

    function removeJuror(address _juror) external onlyOwner {
        require(isJuror[_juror], "Not a juror");
        isJuror[_juror] = false;
        // Remove from array (swap with last, pop)
        for (uint256 i = 0; i < juryPool.length; i++) {
            if (juryPool[i] == _juror) {
                juryPool[i] = juryPool[juryPool.length - 1];
                juryPool.pop();
                break;
            }
        }
        require(juryPool.length >= juryQuorum, "Would break quorum");
        emit JurorRemoved(_juror);
    }

    function addJurors(address[] calldata _jurors) external onlyOwner {
        for (uint256 i = 0; i < _jurors.length; i++) {
            require(_jurors[i] != address(0), ZeroAddress());
            if (!isJuror[_jurors[i]]) {
                isJuror[_jurors[i]] = true;
                juryPool.push(_jurors[i]);
                emit JurorAdded(_jurors[i]);
            }
        }
    }

    function getJurorCount() external view returns (uint256) {
        return juryPool.length;
    }

    // ───────────── Job Lifecycle ─────────────

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

        uint256 jobId = _jobCounter++;

        Job storage job = _jobs[jobId];
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

        _token.safeTransferFrom(msg.sender, address(this), totalAmount);

        emit JobCreated(jobId, msg.sender, totalAmount, _description, _category, _deadline);
        return jobId;
    }

    // ───────────── Batch Operations ─────────────

    /// @notice Create multiple jobs in a single transaction
    function batchCreateJobs(
        IERC20 _token,
        string[] calldata _descriptions,
        string[] calldata _categories,
        uint256[] calldata _deadlines,
        MilestoneDesc[][] calldata _milestones
    ) external nonReentrant returns (uint256[] memory) {
        uint256 count = _descriptions.length;
        require(count > 0, BatchEmpty());
        require(count == _categories.length && count == _deadlines.length && count == _milestones.length, ArrayLengthMismatch());
        require(count <= 20, "Batch too large");

        uint256[] memory jobIds = new uint256[](count);
        uint256 totalTransfer = 0;

        for (uint256 i = 0; i < count; i++) {
            require(_deadlines[i] > block.timestamp, DeadlineMustBeFuture());
            require(_milestones[i].length > 0, MilestonesRequired());
            require(bytes(_descriptions[i]).length > 0, DescriptionRequired());

            uint256 jobAmount = 0;
            for (uint256 j = 0; j < _milestones[i].length; j++) {
                jobAmount += _milestones[i][j].amount;
            }
            require(jobAmount > 0, AmountMustBePositive());
            totalTransfer += jobAmount;

            uint256 jobId = _jobCounter++;
            jobIds[i] = jobId;

            Job storage job = _jobs[jobId];
            job.client = msg.sender;
            job.token = _token;
            job.amount = jobAmount;
            job.description = _descriptions[i];
            job.category = _categories[i];
            job.status = Status.Open;
            job.createdAt = block.timestamp;
            job.deadline = _deadlines[i];

            for (uint256 j = 0; j < _milestones[i].length; j++) {
                job.milestones.push(Milestone({
                    description: _milestones[i][j].description,
                    amount: _milestones[i][j].amount,
                    status: MilestoneStatus.Pending
                }));
            }

            emit JobCreated(jobId, msg.sender, jobAmount, _descriptions[i], _categories[i], _deadlines[i]);
        }

        _token.safeTransferFrom(msg.sender, address(this), totalTransfer);
        return jobIds;
    }

    /// @notice Release multiple milestones in a single transaction
    function batchReleaseMilestones(
        uint256[] calldata _jobIds,
        uint256[] calldata _milestoneIndices
    ) external nonReentrant {
        require(_jobIds.length == _milestoneIndices.length, ArrayLengthMismatch());
        require(_jobIds.length > 0, BatchEmpty());
        require(_jobIds.length <= 50, "Batch too large");

        for (uint256 i = 0; i < _jobIds.length; i++) {
            _releaseMilestone(_jobIds[i], _milestoneIndices[i]);
        }
    }

    function _releaseMilestone(uint256 _jobId, uint256 _milestoneIndex) internal {
        Job storage job = _jobs[_jobId];
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

    // ───────────── Standard Job Functions ─────────────

    function applyToJob(uint256 _jobId) external {
        Job storage job = _jobs[_jobId];
        if (job.status != Status.Open) revert InvalidStatus(job.status);
        if (msg.sender == job.client) revert AlreadyApplied();
        if (hasApplied[_jobId][msg.sender]) revert AlreadyApplied();

        hasApplied[_jobId][msg.sender] = true;
        job.applicants.push(msg.sender);
        emit ApplicantAdded(_jobId, msg.sender);
    }

    function acceptFreelancer(uint256 _jobId, address _freelancer) external {
        Job storage job = _jobs[_jobId];
        if (msg.sender != job.client) revert NotClient();
        if (job.status != Status.Open) revert InvalidStatus(job.status);
        require(hasApplied[_jobId][_freelancer], "Not an applicant");

        job.freelancer = _freelancer;
        job.status = Status.InProgress;
        emit FreelancerAccepted(_jobId, _freelancer);
    }

    function releaseMilestone(uint256 _jobId, uint256 _milestoneIndex) external nonReentrant {
        _releaseMilestone(_jobId, _milestoneIndex);
    }

    function completeJob(uint256 _jobId) external {
        Job storage job = _jobs[_jobId];
        if (msg.sender != job.client) revert NotClient();
        if (job.status != Status.InProgress) revert InvalidStatus(job.status);

        for (uint256 i = 0; i < job.milestones.length; i++) {
            require(job.milestones[i].status == MilestoneStatus.Released, "Milestone not released");
        }

        job.status = Status.Completed;
        _reputations[job.freelancer].completedJobs++;
        emit JobCompleted(_jobId, job.freelancer);
    }

    function cancelJob(uint256 _jobId) external nonReentrant {
        Job storage job = _jobs[_jobId];
        if (msg.sender != job.client) revert NotClient();
        if (job.status != Status.Open) revert InvalidStatus(job.status);

        job.status = Status.Cancelled;
        job.token.safeTransfer(job.client, job.amount);
        emit JobCancelled(_jobId, job.client);
    }

    function claimRefund(uint256 _jobId) external nonReentrant {
        Job storage job = _jobs[_jobId];
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

    function disputeJob(uint256 _jobId) external {
        Job storage job = _jobs[_jobId];
        if (msg.sender != job.client && msg.sender != job.freelancer) revert NotClientOrFreelancer();
        if (job.status != Status.InProgress) revert InvalidStatus(job.status);

        job.status = Status.Disputed;
        emit JobDisputed(_jobId, msg.sender);
    }

    function voteDispute(uint256 _jobId, bool _payFreelancer) external nonReentrant {
        Job storage job = _jobs[_jobId];
        if (job.status != Status.Disputed) revert NotDisputed();
        if (disputeResolved[_jobId]) revert NotDisputed();
        if (!isJuror[msg.sender]) revert NotJuror();
        if (hasVoted[_jobId][msg.sender]) revert AlreadyVoted();

        hasVoted[_jobId][msg.sender] = true;
        voteValue[_jobId][msg.sender] = _payFreelancer;

        if (_payFreelancer) {
            votesForFreelancer[_jobId]++;
        } else {
            votesForClient[_jobId]++;
        }

        emit DisputeVoteCast(_jobId, msg.sender, _payFreelancer);

        if (votesForFreelancer[_jobId] >= juryQuorum) {
            _resolveDispute(_jobId, true);
        } else if (votesForClient[_jobId] >= juryQuorum) {
            _resolveDispute(_jobId, false);
        }
    }

    function _resolveDispute(uint256 _jobId, bool _payFreelancer) internal {
        Job storage job = _jobs[_jobId];
        disputeResolved[_jobId] = true;

        uint256 pendingAmount = 0;
        for (uint256 i = 0; i < job.milestones.length; i++) {
            if (job.milestones[i].status == MilestoneStatus.Pending) {
                pendingAmount += job.milestones[i].amount;
                job.milestones[i].status = MilestoneStatus.Released;
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
            _reputations[job.freelancer].completedJobs++;
        } else {
            job.status = Status.Cancelled;
            if (pendingAmount > 0) {
                job.token.safeTransfer(job.client, pendingAmount);
            }
        }

        emit DisputeResolved(_jobId, _payFreelancer);
    }

    // ───────────── Reputation ─────────────

    function rateFreelancer(uint256 _jobId, uint256 _rating) external {
        Job storage job = _jobs[_jobId];
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

    function getReputation(address _freelancer) external view returns (uint256 completedJobs_, uint256 averageRating_) {
        Reputation storage rep = _reputations[_freelancer];
        completedJobs_ = rep.completedJobs;
        if (rep.ratingCount > 0) {
            averageRating_ = (rep.totalRating * 100) / rep.ratingCount;
        }
    }

    // ───────────── View / Pagination ─────────────

    function jobCount() external view returns (uint256) {
        return _jobCounter;
    }

    function getApplicants(uint256 _jobId) external view returns (address[] memory) {
        return _jobs[_jobId].applicants;
    }

    function getMilestone(uint256 _jobId, uint256 _milestoneId) external view returns (
        string memory description,
        uint256 amount,
        MilestoneStatus milestoneStatus
    ) {
        Milestone storage ms = _jobs[_jobId].milestones[_milestoneId];
        return (ms.description, ms.amount, ms.status);
    }

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
        uint256 total = _jobCounter;
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
            Job storage job = _jobs[start + i];
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
        Job storage job = _jobs[_jobId];
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

    function getDisputeVotes(uint256 _jobId) external view returns (uint256 forFreelancer, uint256 forClient) {
        return (votesForFreelancer[_jobId], votesForClient[_jobId]);
    }
}
