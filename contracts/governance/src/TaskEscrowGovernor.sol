// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GovernorBase} from "./GovernorBase.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title TaskEscrowGovernor
/// @notice Example: TaskEscrow protocol governance using GovernorBase.
contract TaskEscrowGovernor is GovernorBase {
    address public immutable taskEscrow;
    error TaskEscrowGovernor__InvalidTarget();

    constructor(
        string memory _name,
        IVotes _token,
        TimelockController _timelock,
        uint256 _quorumPercent,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        address _taskEscrow
    )
        GovernorBase(_name, _token, _timelock, _quorumPercent, _votingDelay, _votingPeriod)
    {
        taskEscrow = _taskEscrow;
    }
}
