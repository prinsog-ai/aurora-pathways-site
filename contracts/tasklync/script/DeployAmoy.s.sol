// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TaskEscrow} from "../src/TaskEscrow.sol";

/// @notice Deploy TaskEscrow to Polygon Amoy testnet
/// @dev Uses real Circle testnet USDC. Run: forge script script/DeployAmoy.s.sol --rpc-url polygon_amoy --broadcast --verify
contract DeployAmoy is Script {
    // Circle testnet USDC on Polygon Amoy
    address constant AMOY_USDC = 0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerKey);

        TaskEscrow escrow = new TaskEscrow(treasury);

        vm.stopBroadcast();

        console.log("\n--- Polygon Amoy Deploy ---");
        console.log("Chain:", "Polygon Amoy (80002)");
        console.log("USDC:", AMOY_USDC);
        console.log("TaskEscrow:", address(escrow));
        console.log("Treasury:", treasury);
        console.log("Fee:", escrow.platformFee(), "bps (3%)");
    }
}
