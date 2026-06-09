// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title AuroraGovernor
/// @notice DAO governance for Aurora Pathways — 1-day voting delay, 3-day period, 1% threshold, 4% quorum, 2-day timelock
contract AuroraGovernor is
    Governor,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorCountingSimple,
    GovernorSettings,
    GovernorTimelockControl
{
    constructor(IVotes tokenAddress, TimelockController timelockAddress)
        Governor("Aurora Governor")
        GovernorVotes(tokenAddress)
        GovernorVotesQuorumFraction(4)          // 4% quorum
        GovernorSettings(7200, 21600, 10_000_000 * 1e18) // 1d delay, 3d period, 10M threshold
        GovernorTimelockControl(timelockAddress)
    {}

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
