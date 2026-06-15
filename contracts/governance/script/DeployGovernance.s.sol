// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {TaskEscrowGovernor} from "../src/TaskEscrowGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title DeployGovernance
/// @notice Deploys the full governance stack for TaskEscrow.
///        Adapt this script for other protocols (RideP2P, Pledgly, Forekast).
///
/// Usage:
///   forge script script/DeployGovernance.s.sol --rpc-url polygon_amoy --broadcast --verify
contract DeployGovernance is Script {
    // ─── Config ───────────────────────────────────────────────
    string constant TOKEN_NAME = "TaskEscrow Token";
    string constant TOKEN_SYMBOL = "TET";
    uint256 constant MAX_SUPPLY = 1_000_000e18; // 1M tokens
    uint256 constant QUORUM_PERCENT = 4; // 4% of supply
    uint256 constant VOTING_DELAY = 1; // 1 block
    uint256 constant VOTING_PERIOD = 45818; // ~1 week on Polygon (2s blocks)
    uint256 constant TIMELOCK_DELAY = 3600; // 1 hour

    function run() external {
        address deployer = msg.sender;

        // ─── 1. Deploy Governance Token ───────────────────────
        GovernanceToken token = new GovernanceToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            MAX_SUPPLY,
            deployer
        );
        console.log("GovernanceToken deployed at:", address(token));

        // ─── 2. Deploy TimelockController ─────────────────────
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        TimelockController timelock = new TimelockController(
            TIMELOCK_DELAY,
            proposers,
            executors,
            deployer
        );
        console.log("TimelockController deployed at:", address(timelock));

        // ─── 3. Deploy Governor ───────────────────────────────
        // NOTE: Replace address(0) with actual TaskEscrow contract address
        address taskEscrowAddress = address(0);
        TaskEscrowGovernor governor = new TaskEscrowGovernor(
            "TaskEscrow Governor",
            token,
            timelock,
            QUORUM_PERCENT,
            VOTING_DELAY,
            VOTING_PERIOD,
            taskEscrowAddress
        );
        console.log("TaskEscrowGovernor deployed at:", address(governor));

        // ─── 4. Grant roles ──────────────────────────────────
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0)); // anyone
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        console.log("Roles granted");

        // ─── 5. Transfer timelock admin to timelock itself ────
        // This makes the governance fully decentralized
        // timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
        // console.log("Admin renounced — governance is now decentralized");
    }
}
