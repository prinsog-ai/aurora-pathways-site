// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TaskEscrow} from "../src/TaskEscrow.sol";

/// @notice Deploy TaskEscrow to Base Sepolia testnet
/// @dev Run: forge script script/Deploy.s.sol:DeployTaskEscrow --rpc-url $RPC_URL --broadcast
contract DeployTaskEscrow is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerKey);

        TaskEscrow escrow = new TaskEscrow(treasury);

        console.log("TaskEscrow deployed at:", address(escrow));
        console.log("Treasury:", treasury);
        console.log("Fee:", escrow.platformFee(), "(3% = 300 bps)");

        vm.stopBroadcast();
    }
}
