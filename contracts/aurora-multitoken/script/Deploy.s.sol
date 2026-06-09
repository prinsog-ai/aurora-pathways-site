// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AuroraMultiToken} from "../src/AuroraMultiToken.sol";

/// @title DeployAuroraMultiToken
/// @notice Deploy an AuroraMultiToken contract for membership tiers, gaming items, etc.
///
/// Required env vars:
///   PRIVATE_KEY            — deployer's private key
///   OWNER_ADDRESS          — initial contract owner
///
/// Optional (configurable in .env):
///   BASE_URI               — base metadata URI (default: "https://aurora.base.uri/")
contract DeployAuroraMultiToken is Script {
    function run() external {
        // Load required vars
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");

        // Load optional vars with defaults
        string memory baseUri = vm.envOr("BASE_URI", string("https://aurora.base.uri/"));

        vm.startBroadcast(deployerKey);

        AuroraMultiToken mt = new AuroraMultiToken(baseUri, owner);

        console.log("AuroraMultiToken deployed at:", address(mt));

        vm.stopBroadcast();

        console.log("\n=== Aurora Multi-Token Deployed ===");
        console.log("Base URI:   ", baseUri);
        console.log("Owner:      ", owner);
        console.log("Contract:   ", address(mt));
        console.log("===================================");
    }
}
