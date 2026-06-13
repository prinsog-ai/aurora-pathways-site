// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title WESJobTicket — On-chain job tickets with proof of work for Williams Engineering Services
contract WESJobTicket is Ownable {
    enum JobStatus { Created, Assigned, InProgress, Completed, Disputed, Resolved }
    enum ServiceType { Roustabout, HydroExcavation, Welding, CorrosionProtection, Other }

    struct Job {
        uint256 id;
        address client;
        string siteLocation;
        ServiceType service;
        string description;
        uint256 estimatedAmount; // in USDC (6 decimals)
        uint256 createdAt;
        uint256 completedAt;
        JobStatus status;
        address assignedCrew;
        string evidenceHash; // IPFS hash of photos/docs
        bool paid;
    }

    struct Crew {
        string name;
        string role;
        bool active;
        uint256 totalJobs;
        uint256 safetyScore; // basis points (10000 = 100%)
    }

    uint256 public nextJobId;
    mapping(uint256 => Job) public jobs;
    mapping(address => Crew) public crews;
    mapping(address => bool) public verifiedCrew;

    event JobCreated(uint256 indexed id, address client, string site, ServiceType service);
    event JobAssigned(uint256 indexed id, address crew);
    event JobStarted(uint256 indexed id);
    event JobCompleted(uint256 indexed id, string evidenceHash);
    event JobDisputed(uint256 indexed id, string reason);
    event JobResolved(uint256 indexed id, bool approved);
    event CrewRegistered(address crew, string name);
    event CrewVerified(address crew, bool status);

    constructor() Ownable(msg.sender) {}

    // ═══ JOB LIFECYCLE ═══

    function createJob(
        address client,
        string calldata siteLocation,
        ServiceType service,
        string calldata description,
        uint256 estimatedAmount
    ) external onlyOwner returns (uint256) {
        uint256 id = nextJobId++;
        jobs[id] = Job({
            id: id,
            client: client,
            siteLocation: siteLocation,
            service: service,
            description: description,
            estimatedAmount: estimatedAmount,
            createdAt: block.timestamp,
            completedAt: 0,
            status: JobStatus.Created,
            assignedCrew: address(0),
            evidenceHash: "",
            paid: false
        });

        emit JobCreated(id, client, siteLocation, service);
        return id;
    }

    function assignCrew(uint256 jobId, address crew) external onlyOwner {
        require(jobs[jobId].status == JobStatus.Created, "Invalid status");
        require(verifiedCrew[crew], "Crew not verified");

        jobs[jobId].assignedCrew = crew;
        jobs[jobId].status = JobStatus.Assigned;
        emit JobAssigned(jobId, crew);
    }

    function startJob(uint256 jobId) external {
        require(msg.sender == jobs[jobId].assignedCrew, "Not assigned crew");
        require(jobs[jobId].status == JobStatus.Assigned, "Invalid status");
        jobs[jobId].status = JobStatus.InProgress;
        emit JobStarted(jobId);
    }

    function completeJob(uint256 jobId, string calldata evidenceHash) external {
        require(msg.sender == jobs[jobId].assignedCrew, "Not assigned crew");
        require(jobs[jobId].status == JobStatus.InProgress, "Invalid status");

        jobs[jobId].status = JobStatus.Completed;
        jobs[jobId].completedAt = block.timestamp;
        jobs[jobId].evidenceHash = evidenceHash;

        // Update crew stats
        crews[msg.sender].totalJobs++;

        emit JobCompleted(jobId, evidenceHash);
    }

    function disputeJob(uint256 jobId, string calldata reason) external {
        require(
            msg.sender == jobs[jobId].client || msg.sender == owner(),
            "Not authorized"
        );
        jobs[jobId].status = JobStatus.Disputed;
        emit JobDisputed(jobId, reason);
    }

    function resolveDispute(uint256 jobId, bool approve) external onlyOwner {
        require(jobs[jobId].status == JobStatus.Disputed, "Not disputed");
        jobs[jobId].status = approve ? JobStatus.Completed : JobStatus.Created;
        emit JobResolved(jobId, approve);
    }

    function markPaid(uint256 jobId) external onlyOwner {
        require(jobs[jobId].status == JobStatus.Completed, "Not completed");
        jobs[jobId].paid = true;
    }

    // ═══ CREW MANAGEMENT ═══

    function registerCrew(address crew, string calldata name, string calldata role) external onlyOwner {
        crews[crew] = Crew({
            name: name,
            role: role,
            active: true,
            totalJobs: 0,
            safetyScore: 10000 // 100% default
        });
        emit CrewRegistered(crew, name);
    }

    function verifyCrew(address crew, bool status) external onlyOwner {
        verifiedCrew[crew] = status;
        emit CrewVerified(crew, status);
    }

    function updateSafetyScore(address crew, uint256 newScore) external onlyOwner {
        require(newScore <= 10000, "Invalid score");
        crews[crew].safetyScore = newScore;
    }

    // ═══ VIEWS ═══

    function getJobCount() external view returns (uint256) {
        return nextJobId;
    }

    function getJobStatus(uint256 jobId) external view returns (JobStatus) {
        return jobs[jobId].status;
    }
}
