// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./CarbonCredit.sol";
import "./CreditSplitter.sol";

/// @title AttestationModule — Handles MRV data attestation, dispute window, and auto-minting
contract AttestationModule is Ownable {
    CarbonCredit public creditToken;
    CreditSplitter public splitter;

    uint256 public constant MCF_TO_TONS = 36; // 1 MCF = 0.036 tons CO2 (scaled by 1000)
    uint256 public disputeWindow = 2 days;

    struct Attestation {
        string siteId;
        uint256 gasVolumeMCF;
        uint256 co2Tons;
        uint256 timestamp;
        address attester;
        bool disputed;
        bool finalized;
    }

    uint256 public nextAttestationId;
    mapping(uint256 => Attestation) public attestations;
    mapping(uint256 => mapping(address => bool)) public disputes;

    event AttestationCreated(uint256 indexed id, string siteId, uint256 gasVolume, uint256 co2Tons);
    event AttestationFinalized(uint256 indexed id, uint256 creditsMinted);
    event AttestationDisputed(uint256 indexed id, address disputer);
    event DisputeWindowUpdated(uint256 newWindow);

    constructor(address _creditToken, address _splitter) Ownable(msg.sender) {
        creditToken = CarbonCredit(_creditToken);
        splitter = CreditSplitter(_splitter);
    }

    function attest(string calldata siteId, uint256 gasVolumeMCF) external onlyOwner returns (uint256) {
        uint256 co2Tons = (gasVolumeMCF * MCF_TO_TONS) / 1000;
        require(co2Tons > 0, "Volume too small");

        uint256 id = nextAttestationId++;
        attestations[id] = Attestation({
            siteId: siteId,
            gasVolumeMCF: gasVolumeMCF,
            co2Tons: co2Tons,
            timestamp: block.timestamp,
            attester: msg.sender,
            disputed: false,
            finalized: false
        });

        emit AttestationCreated(id, siteId, gasVolumeMCF, co2Tons);
        return id;
    }

    function dispute(uint256 attestationId) external {
        Attestation storage a = attestations[attestationId];
        require(a.timestamp > 0, "Not found");
        require(!a.finalized, "Already finalized");
        require(block.timestamp <= a.timestamp + disputeWindow, "Dispute window closed");
        require(!disputes[attestationId][msg.sender], "Already disputed");

        disputes[attestationId][msg.sender] = true;
        a.disputed = true;
        emit AttestationDisputed(attestationId, msg.sender);
    }

    function finalize(uint256 attestationId) external onlyOwner {
        Attestation storage a = attestations[attestationId];
        require(a.timestamp > 0, "Not found");
        require(!a.finalized, "Already finalized");
        require(!a.disputed, "Under dispute");
        require(block.timestamp > a.timestamp + disputeWindow, "Dispute window open");

        a.finalized = true;
        creditToken.mint(address(splitter), a.co2Tons, a.siteId);
        splitter.distribute(a.siteId, a.co2Tons);

        emit AttestationFinalized(attestationId, a.co2Tons);
    }

    function resolveDispute(uint256 attestationId, bool approve) external onlyOwner {
        Attestation storage a = attestations[attestationId];
        require(a.disputed, "Not disputed");
        require(!a.finalized, "Already finalized");

        if (approve) {
            a.disputed = false;
        } else {
            a.finalized = true;
        }
    }

    function setDisputeWindow(uint256 newWindow) external onlyOwner {
        disputeWindow = newWindow;
        emit DisputeWindowUpdated(newWindow);
    }

    function getAttestationCount() external view returns (uint256) {
        return nextAttestationId;
    }
}
