// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TaskEscrowV2} from "../src/TaskEscrowV2.sol";

/// @notice Deploy TaskEscrowV2 to any EVM chain
/// @dev Run: forge script script/DeployV2.s.sol:DeployTaskEscrowV2 --rpc-url $RPC_URL --broadcast
contract DeployTaskEscrowV2 is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        // Optional: load 5 jury addresses from env (comma-separated not ideal in Forge,
        // so we read them individually). Falls back to deployer as placeholder.
        address juror1 = vm.envOr("JUROR_1", deployerKey == 0 ? address(0) : vm.addr(deployerKey));
        address juror2 = vm.envOr("JUROR_2", juror1);
        address juror3 = vm.envOr("JUROR_3", juror1);
        address juror4 = vm.envOr("JUROR_4", juror1);
        address juror5 = vm.envOr("JUROR_5", juror1);

        vm.startBroadcast(deployerKey);

        TaskEscrowV2 escrow = new TaskEscrowV2(treasury);

        // Set jury only if unique addresses provided via env vars
        // For testnet, skip jury setup if no unique jurors configured
        address[5] memory jurors;
        jurors[0] = juror1;
        jurors[1] = juror2;
        jurors[2] = juror3;
        jurors[3] = juror4;
        jurors[4] = juror5;

        bool hasUniqueJury = juror1 != juror2 && juror2 != juror3 && juror3 != juror4 && juror4 != juror5;
        if (hasUniqueJury && juror1 != address(0)) {
            escrow.setJury(jurors);
            console.log("Jury set");
        } else {
            console.log("Jury skipped (no unique addresses)");
        }

        console.log("TaskEscrowV2 deployed at:", address(escrow));
        console.log("Treasury:", treasury);
        console.log("Fee:", escrow.platformFee(), "(3% = 300 bps)");

        vm.stopBroadcast();
    }
}
