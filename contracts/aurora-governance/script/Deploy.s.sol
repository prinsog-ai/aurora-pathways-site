// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AuroraGovernanceToken} from "../src/AuroraGovernanceToken.sol";
import {AuroraGovernor} from "../src/AuroraGovernor.sol";
import {AuroraTimelock} from "../src/AuroraTimelock.sol";
import {AuroraTreasury} from "../src/AuroraTreasury.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title DeployAuroraGovernance
/// @notice One-shot deploy script for the entire Aurora Governance suite
/// @dev Deploys: Token → Treasury → Timelock → Governor → Wire roles
///
///      Required env vars:
///        PRIVATE_KEY         — deployer's private key
///        OWNER_ADDRESS       — initial owner of the governance token
///        SIGNER_1, SIGNER_2, SIGNER_3 — treasury multisig signers
contract DeployAuroraGovernance is Script {
    function run() external {
        // ─── Load config ───
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address signer1 = vm.envAddress("SIGNER_1");
        address signer2 = vm.envAddress("SIGNER_2");
        address signer3 = vm.envAddress("SIGNER_3");

        vm.startBroadcast(deployerKey);

        // 1. Deploy governance token
        AuroraGovernanceToken token = new AuroraGovernanceToken(owner);
        console.log("AuroraGovernanceToken deployed at:", address(token));

        // 2. Deploy treasury — governance = address(this) temporarily
        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;
        // Set governance placeholder to deployer; will update after governor deployment
        AuroraTreasury treasury = new AuroraTreasury(signers, 2, msg.sender);
        console.log("AuroraTreasury deployed at:", address(treasury));

        // 3. Deploy timelock with deployer as temporary admin
        AuroraTimelock timelock = new AuroraTimelock(msg.sender, address(0), msg.sender);
        console.log("AuroraTimelock deployed at:", address(timelock));

        // 4. Deploy governor
        AuroraGovernor governor = new AuroraGovernor(
            IVotes(address(token)),
            TimelockController(payable(address(timelock)))
        );
        console.log("AuroraGovernor deployed at:", address(governor));

        // 5. Grant roles on timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(treasury));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(treasury));
        // Renounce admin so timelock becomes self-administered
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), msg.sender);
        console.log("Timelock roles configured (admin renounced)");

        // 6. Update treasury governance to point to governor
        treasury.updateGovernance(address(governor));
        console.log("Treasury governance set to governor");

        // 7. Print summary
        vm.stopBroadcast();

        console.log("\n=== Aurora Governance Suite Deployed ===");
        console.log("Token:    ", address(token));
        console.log("Treasury: ", address(treasury));
        console.log("Timelock: ", address(timelock));
        console.log("Governor: ", address(governor));
        console.log("Owner:    ", owner);
        console.log("Signers:  ", signer1, signer2, signer3);
        console.log("=========================================");
    }
}
