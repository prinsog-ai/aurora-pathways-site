// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AcmeAuditTrail — Immutable audit trail for ERP transactions
contract AcmeAuditTrail is Ownable {
    struct AuditEntry {
        uint256 id;
        string entityType; // "invoice", "purchase_order", "patient_record", etc.
        string entityId;
        string action; // "created", "updated", "approved", "deleted"
        string dataHash; // SHA-256 hash of the data
        address actor;
        uint256 timestamp;
        string previousHash; // links to previous entry for chain integrity
    }

    uint256 public nextEntryId;
    mapping(uint256 => AuditEntry) public entries;
    mapping(string => uint256[]) public entityEntries; // entityId => entry IDs
    string public lastHash;

    event AuditRecorded(uint256 indexed id, string entityType, string entityId, string action, address actor);

    constructor() Ownable(msg.sender) {}

    function record(
        string calldata entityType,
        string calldata entityId,
        string calldata action,
        string calldata dataHash
    ) external returns (uint256) {
        uint256 id = nextEntryId++;
        entries[id] = AuditEntry({
            id: id,
            entityType: entityType,
            entityId: entityId,
            action: action,
            dataHash: dataHash,
            actor: msg.sender,
            timestamp: block.timestamp,
            previousHash: lastHash
        });

        entityEntries[entityId].push(id);
        lastHash = dataHash;

        emit AuditRecorded(id, entityType, entityId, action, msg.sender);
        return id;
    }

    function verifyIntegrity(uint256 entryId, string calldata dataHash) external view returns (bool) {
        return keccak256(abi.encodePacked(entries[entryId].dataHash)) == keccak256(abi.encodePacked(dataHash));
    }

    function getEntityHistory(string calldata entityId) external view returns (uint256[] memory) {
        return entityEntries[entityId];
    }

    function getEntryCount() external view returns (uint256) {
        return nextEntryId;
    }
}
