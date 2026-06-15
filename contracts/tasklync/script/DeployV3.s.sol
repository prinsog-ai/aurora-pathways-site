// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TaskEscrowV3} from "../src/TaskEscrowV3.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title Deploy TaskEscrowV3 (UUPS Proxy)
/// @notice Deploy script for TaskEscrowV3 behind a transparent proxy
/// @dev Run: forge script script/DeployV3.s.sol --rpc-url polygon --broadcast --verify
contract DeployV3 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy implementation
        TaskEscrowV3 impl = new TaskEscrowV3();
        console.log("Implementation deployed at:", address(impl));

        // 2. Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(TaskEscrowV3.initialize, (treasury));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            msg.sender, // proxy admin (deployer)
            initData
        );
        console.log("Proxy deployed at:", address(proxy));

        // 3. Setup initial jury (5 members)
        TaskEscrowV3 escrow = TaskEscrowV3(address(proxy));
        address[] memory jurors = new address[](5);
        jurors[0] = vm.envAddress("JUROR_1");
        jurors[1] = vm.envAddress("JUROR_2");
        jurors[2] = vm.envAddress("JUROR_3");
        jurors[3] = vm.envAddress("JUROR_4");
        jurors[4] = vm.envAddress("JUROR_5");
        escrow.addJurors(jurors);
        console.log("Jury pool initialized with 5 members");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Implementation:", address(impl));
        console.log("Proxy:", address(proxy));
        console.log("Treasury:", treasury);
        console.log("Juror pool:", escrow.getJurorCount());
    }
}
