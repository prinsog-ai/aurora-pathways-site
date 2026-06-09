// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title DAOGovernor
/// @notice Unified DAO governance for Aurora Pathways — controls fees, treasury, jury, and revenue distribution
///         across TaskEscrow, Pledgly, and RevenueDistributor contracts.
/// @dev 1-day voting delay, 3-day voting period, 10M proposal threshold, 4% quorum fraction.
///      Proposal types: FeeChange, TreasuryChange, JuryChange, Distribution.
contract DAOGovernor is
    Governor,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorCountingSimple,
    GovernorSettings,
    GovernorTimelockControl
{
    // ───────────── Proposal Types ─────────────

    enum ProposalType {
        FeeChange,        // Change platform fee on TaskEscrow or Pledgly
        TreasuryChange,   // Change treasury/fee recipient address
        JuryChange,       // Change jury members on TaskEscrow
        Distribution,     // Trigger revenue distribution
        General           // Any other governance action
    }

    // ───────────── Storage ─────────────

    /// @notice Proposal type for each proposal ID
    mapping(uint256 => ProposalType) public proposalTypes;

    /// @notice Description string for each proposal (stored on-chain)
    mapping(uint256 => string) public proposalDescriptions;

    /// @notice Managed contract addresses
    address public taskEscrow;
    address public pledgly;
    address public revenueDistributor;

    // ───────────── Events ─────────────

    event ProposalCreatedWithType(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalType proposalType,
        string description
    );

    event ManagedContractsUpdated(
        address taskEscrow,
        address pledgly,
        address revenueDistributor
    );

    // ───────────── Errors ─────────────

    error InvalidAddress();
    error UnauthorizedCaller();

    // ───────────── Constructor ─────────────

    /// @param tokenAddress The governance token (AuroraGovernanceToken with ERC20Votes)
    /// @param timelockAddress The timelock controller
    constructor(IVotes tokenAddress, TimelockController timelockAddress)
        Governor("Aurora DAO Governor")
        GovernorVotes(tokenAddress)
        GovernorVotesQuorumFraction(4)                                       // 4% quorum
        GovernorSettings(7200, 21600, 10_000_000 * 1e18)                    // 1d delay, 3d period, 10M threshold
        GovernorTimelockControl(timelockAddress)
    {}

    // ───────────── Configuration ─────────────

    /// @notice Set the managed protocol contract addresses
    /// @dev Only callable by the governor itself (via proposal)
    function setManagedContracts(
        address _taskEscrow,
        address _pledgly,
        address _revenueDistributor
    ) external {
        if (msg.sender != address(this)) revert UnauthorizedCaller();
        taskEscrow = _taskEscrow;
        pledgly = _pledgly;
        revenueDistributor = _revenueDistributor;
        emit ManagedContractsUpdated(_taskEscrow, _pledgly, _revenueDistributor);
    }

    // ───────────── Proposal Creation Helpers ─────────────

    /// @notice Create a fee change proposal for TaskEscrow or Pledgly
    /// @param targets Target contract addresses (array for multi-call)
    /// @param values ETH values (usually 0)
    /// @param calldatas Encoded function calls
    /// @param description Human-readable description
    /// @return proposalId The new proposal ID
    function proposeFeeChange(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {
        uint256 proposalId = propose(targets, values, calldatas, description);
        proposalTypes[proposalId] = ProposalType.FeeChange;
        proposalDescriptions[proposalId] = description;
        emit ProposalCreatedWithType(proposalId, msg.sender, ProposalType.FeeChange, description);
        return proposalId;
    }

    /// @notice Create a treasury address change proposal
    function proposeTreasuryChange(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {
        uint256 proposalId = propose(targets, values, calldatas, description);
        proposalTypes[proposalId] = ProposalType.TreasuryChange;
        proposalDescriptions[proposalId] = description;
        emit ProposalCreatedWithType(proposalId, msg.sender, ProposalType.TreasuryChange, description);
        return proposalId;
    }

    /// @notice Create a jury member change proposal for TaskEscrow
    function proposeJuryChange(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {
        uint256 proposalId = propose(targets, values, calldatas, description);
        proposalTypes[proposalId] = ProposalType.JuryChange;
        proposalDescriptions[proposalId] = description;
        emit ProposalCreatedWithType(proposalId, msg.sender, ProposalType.JuryChange, description);
        return proposalId;
    }

    /// @notice Create a revenue distribution trigger proposal
    function proposeDistribution(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256) {
        uint256 proposalId = propose(targets, values, calldatas, description);
        proposalTypes[proposalId] = ProposalType.Distribution;
        proposalDescriptions[proposalId] = description;
        emit ProposalCreatedWithType(proposalId, msg.sender, ProposalType.Distribution, description);
        return proposalId;
    }

    // ───────────── Calldata Encoding Helpers ─────────────

    /// @notice Encode a setPlatformFee call for TaskEscrow
    /// @param _fee New fee in basis points (e.g. 300 = 3%)
    /// @return data Encoded calldata
    function encodeSetPlatformFee(uint256 _fee) external pure returns (bytes memory data) {
        data = abi.encodeWithSignature("setPlatformFee(uint256)", _fee);
    }

    /// @notice Encode a setPlatformFeeBps call for Pledgly
    /// @param _bps New fee in basis points
    /// @return data Encoded calldata
    function encodeSetPlatformFeeBps(uint256 _bps) external pure returns (bytes memory data) {
        data = abi.encodeWithSignature("setPlatformFeeBps(uint256)", _bps);
    }

    /// @notice Encode a setPlatformTreasury call for TaskEscrow
    /// @param _treasury New treasury address
    /// @return data Encoded calldata
    function encodeSetPlatformTreasury(address _treasury) external pure returns (bytes memory data) {
        data = abi.encodeWithSignature("setPlatformTreasury(address)", _treasury);
    }

    /// @notice Encode a setFeeRecipient call for Pledgly
    /// @param _recipient New fee recipient
    /// @return data Encoded calldata
    function encodeSetFeeRecipient(address _recipient) external pure returns (bytes memory data) {
        data = abi.encodeWithSignature("setFeeRecipient(address)", _recipient);
    }

    /// @notice Encode a setJuror call for TaskEscrow
    /// @param _slot Jury slot index (0-4)
    /// @param _juror Juror address
    /// @return data Encoded calldata
    function encodeSetJuror(uint256 _slot, address _juror) external pure returns (bytes memory data) {
        data = abi.encodeWithSignature("setJuror(uint256,address)", _slot, _juror);
    }

    /// @notice Encode a setJury call for TaskEscrow (set all 5 at once)
    /// @param _jurors Array of 5 juror addresses
    /// @return data Encoded calldata
    function encodeSetJury(address[5] memory _jurors) external pure returns (bytes memory data) {
        data = abi.encodeWithSignature("setJury(address[5])", _jurors);
    }

    /// @notice Encode a createDistribution call for RevenueDistributor
    /// @return data Encoded calldata
    function encodeCreateDistribution() external pure returns (bytes memory data) {
        data = abi.encodeWithSignature("createDistribution()");
    }

    /// @notice Encode a createDistributionAmount call for RevenueDistributor
    /// @param _amount Specific amount to distribute
    /// @return data Encoded calldata
    function encodeCreateDistributionAmount(uint256 _amount) external pure returns (bytes memory data) {
        data = abi.encodeWithSignature("createDistributionAmount(uint256)", _amount);
    }

    // ───────────── View Functions ─────────────

    /// @notice Get the proposal type for a given proposal ID
    function getProposalType(uint256 proposalId) external view returns (ProposalType) {
        return proposalTypes[proposalId];
    }

    /// @notice Get the description for a given proposal ID
    function getProposalDescription(uint256 proposalId) external view returns (string memory) {
        return proposalDescriptions[proposalId];
    }

    // ───────────── Required Overrides ─────────────

    function quorum(uint256 blockNumber) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (bool) {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(uint256 p, address[] memory t, uint256[] memory v, bytes[] memory c, bytes32 d) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(p, t, v, c, d);
    }

    function _executeOperations(uint256 p, address[] memory t, uint256[] memory v, bytes[] memory c, bytes32 d) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(p, t, v, c, d);
    }

    function _cancel(address[] memory t, uint256[] memory v, bytes[] memory c, bytes32 d) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(t, v, c, d);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }

    function _getVotes(address a, uint256 tp, bytes memory pr) internal view override(Governor, GovernorVotes) returns (uint256) {
        return super._getVotes(a, tp, pr);
    }

    function _countVote(uint256 p, address a, uint8 s, uint256 w, bytes memory pr) internal override(Governor, GovernorCountingSimple) returns (uint256) {
        return super._countVote(p, a, s, w, pr);
    }

    function _quorumReached(uint256 p) internal view override(Governor, GovernorCountingSimple) returns (bool) {
        return super._quorumReached(p);
    }

    function _voteSucceeded(uint256 p) internal view override(Governor, GovernorCountingSimple) returns (bool) {
        return super._voteSucceeded(p);
    }
}
