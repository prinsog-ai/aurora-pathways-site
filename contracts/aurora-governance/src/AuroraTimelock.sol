// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title AuroraTimelock
/// @notice Timelock controller for Aurora Pathways DAO governance
/// @dev Configures the standard OpenZeppelin TimelockController with:
///      - 2-day minimum delay
///      - Governor as sole proposer
///      - Governor + treasury multisig as executors
///      - Treasury multisig as canceller (safety valve)
contract AuroraTimelock is TimelockController {
    /// @notice Minimum delay between proposal queuing and execution (2 days in seconds)
    uint256 public constant MIN_DELAY = 2 days;

    /// @param governor Address of the AuroraGovernor contract (sole proposer + executor)
    /// @param treasury Address of the AuroraTreasury multisig (additional executor + canceller)
    /// @param admin_ Address of the admin account (pass address(0) for self-administered)
    constructor(address governor, address treasury, address admin_)
        TimelockController(
            MIN_DELAY,                       // minDelay
            _buildProposers(governor),        // proposers array
            _buildExecutors(governor, treasury), // executors array
            admin_                            // admin
        )
    {}

    /// @dev Build proposers array — only the governor can propose
    function _buildProposers(address governor) private pure returns (address[] memory) {
        address[] memory proposers = new address[](1);
        proposers[0] = governor;
        return proposers;
    }

    /// @dev Build executors array — governor + treasury multisig can execute
    function _buildExecutors(address governor, address treasury) private pure returns (address[] memory) {
        address[] memory executors = new address[](2);
        executors[0] = governor;
        executors[1] = treasury;
        return executors;
    }

    // ─── Convenience view functions ───

    /// @notice Get the current minimum delay
    function getDelay() external view returns (uint256) {
        return getMinDelay();
    }
}
