// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MultiSigFactory} from "../src/MultiSigFactory.sol";

/// @title DeployMultiSigFactory
/// @notice Deploy the MultiSigFactory for creating client multi-sig wallets
///
/// Required env vars:
///   PRIVATE_KEY            — deployer's private key
///   OWNER_ADDRESS          — factory owner
contract DeployMultiSigFactory is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerKey);

        MultiSigFactory factory = new MultiSigFactory(owner);

        console.log("MultiSigFactory deployed at:", address(factory));

        vm.stopBroadcast();

        console.log("\n=== MultiSig Factory Deployed ===");
        console.log("Owner:    ", owner);
        console.log("Factory:  ", address(factory));
        console.log("=================================");
    }
}
