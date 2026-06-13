// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title WESCompliance — Safety and compliance tracking for WES crews
contract WESCompliance is Ownable {
    enum ComplianceType { OSHA, NDIC, EPA, DOT, H2S, ConfinedSpace, HotWork, CDL }

    struct ComplianceRecord {
        address crew;
        ComplianceType compType;
        uint256 issuedDate;
        uint256 expiryDate;
        string documentHash; // IPFS hash of cert document
        bool valid;
    }

    struct Incident {
        uint256 id;
        address reporter;
        address crewInvolved;
        string description;
        uint256 severity; // 1-5
        uint256 timestamp;
        string evidenceHash;
        bool resolved;
        string correctiveAction;
    }

    uint256 public nextIncidentId;
    mapping(uint256 => Incident) public incidents;
    mapping(address => mapping(uint8 => ComplianceRecord[])) public records; // crew => type => records

    event ComplianceRecorded(address crew, ComplianceType compType, uint256 expiryDate);
    event ComplianceExpired(address crew, ComplianceType compType);
    event IncidentReported(uint256 indexed id, address reporter, uint256 severity);
    event IncidentResolved(uint256 indexed id, string correctiveAction);

    constructor() Ownable(msg.sender) {}

    function recordCompliance(
        address crew,
        ComplianceType compType,
        uint256 issuedDate,
        uint256 expiryDate,
        string calldata documentHash
    ) external onlyOwner {
        records[crew][uint8(compType)].push(ComplianceRecord({
            crew: crew,
            compType: compType,
            issuedDate: issuedDate,
            expiryDate: expiryDate,
            documentHash: documentHash,
            valid: true
        }));

        emit ComplianceRecorded(crew, compType, expiryDate);
    }

    function isCompliant(address crew, ComplianceType compType) external view returns (bool) {
        ComplianceRecord[] storage recs = records[crew][uint8(compType)];
        if (recs.length == 0) return false;
        ComplianceRecord storage latest = recs[recs.length - 1];
        return latest.valid && latest.expiryDate > block.timestamp;
    }

    function reportIncident(
        address crewInvolved,
        string calldata description,
        uint256 severity,
        string calldata evidenceHash
    ) external returns (uint256) {
        require(severity >= 1 && severity <= 5, "Invalid severity");

        uint256 id = nextIncidentId++;
        incidents[id] = Incident({
            id: id,
            reporter: msg.sender,
            crewInvolved: crewInvolved,
            description: description,
            severity: severity,
            timestamp: block.timestamp,
            evidenceHash: evidenceHash,
            resolved: false,
            correctiveAction: ""
        });

        emit IncidentReported(id, msg.sender, severity);
        return id;
    }

    function resolveIncident(uint256 incidentId, string calldata correctiveAction) external onlyOwner {
        incidents[incidentId].resolved = true;
        incidents[incidentId].correctiveAction = correctiveAction;
        emit IncidentResolved(incidentId, correctiveAction);
    }

    function getIncidentCount() external view returns (uint256) {
        return nextIncidentId;
    }
}
