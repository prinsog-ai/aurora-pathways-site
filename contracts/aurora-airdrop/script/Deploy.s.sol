// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AuroraAirdrop} from "../src/AuroraAirdrop.sol";

/// @title DeployAuroraAirdrop
/// @notice Deploy the AuroraAirdrop Merkle distributor
///
/// Required env vars:
///   PRIVATE_KEY            — deployer's private key
///   OWNER_ADDRESS          — contract owner
///   AIRDROP_TOKEN_ADDRESS  — ERC-20 token to distribute
///   MERKLE_ROOT            — bytes32 Merkle root
///   TOTAL_ALLOCATED        — total tokens in the tree
///
/// Optional:
///   CLAIM_DEADLINE         — Unix timestamp (default: 30 days from now)
contract DeployAuroraAirdrop is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address tokenAddr = vm.envAddress("AIRDROP_TOKEN_ADDRESS");
        bytes32 merkleRoot = vm.envBytes32("MERKLE_ROOT");
        uint256 totalAllocated = vm.envUint("TOTAL_ALLOCATED");
        uint256 deadline = vm.envOr("CLAIM_DEADLINE", uint256(block.timestamp + 30 days));

        vm.startBroadcast(deployerKey);

        AuroraAirdrop airdrop = new AuroraAirdrop(
            tokenAddr,
            merkleRoot,
            deadline,
            totalAllocated,
            owner
        );

        console.log("AuroraAirdrop deployed at:", address(airdrop));

        vm.stopBroadcast();

        console.log("\n=== Aurora Airdrop Deployed ===");
        console.log("Token:     ", tokenAddr);
        console.log("Merkle Root:", vm.toString(merkleRoot));
        console.log("Total:     ", totalAllocated);
        console.log("Deadline:  ", deadline);
        console.log("Owner:     ", owner);
        console.log("Contract:  ", address(airdrop));
        console.log("===============================");
    }
}
