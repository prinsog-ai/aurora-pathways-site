// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AuroraStaking} from "../src/AuroraStaking.sol";

/// @title DeployAuroraStaking
/// @notice Deploy the AuroraStaking contract for AURA token staking
///
/// Required env vars:
///   PRIVATE_KEY            — deployer's private key
///   OWNER_ADDRESS          — initial contract owner
///   STAKING_TOKEN_ADDRESS  — AURA token address
///
/// Optional (configurable in .env):
///   REWARD_RATE_PER_SECOND — reward tokens per second (default: 1e18 = 1 AURA/sec)
///   MINIMUM_STAKE          — minimum stake amount (default: 100e18 = 100 AURA)
///   INITIAL_REWARD_POOL    — tokens to deposit as initial reward pool (default: 0)
contract DeployAuroraStaking is Script {
    function run() external {
        // Load required vars
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address stakingToken = vm.envAddress("STAKING_TOKEN_ADDRESS");

        // Load optional vars with defaults
        uint256 rewardRate = vm.envOr("REWARD_RATE_PER_SECOND", uint256(1e18));
        uint256 minimumStake = vm.envOr("MINIMUM_STAKE", uint256(100e18));
        uint256 initialRewardPool = vm.envOr("INITIAL_REWARD_POOL", uint256(0));

        vm.startBroadcast(deployerKey);

        AuroraStaking staking = new AuroraStaking(
            stakingToken,
            rewardRate,
            minimumStake,
            owner
        );

        // Fund reward pool if specified
        if (initialRewardPool > 0) {
            // Approve and top up
            // Note: caller must have approved staking contract for stakingToken
            staking.topUpRewardPool(initialRewardPool);
        }

        console.log("AuroraStaking deployed at:", address(staking));

        vm.stopBroadcast();

        console.log("\n=== Aurora Staking Deployed ===");
        console.log("Staking Token:   ", stakingToken);
        console.log("Reward Rate/sec: ", rewardRate);
        console.log("Minimum Stake:   ", minimumStake);
        console.log("Initial Pool:    ", initialRewardPool);
        console.log("Owner:           ", owner);
        console.log("Contract:        ", address(staking));
        console.log("================================");
    }
}
