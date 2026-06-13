// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TechnicianRegistry} from "../src/TechnicianRegistry.sol";
import {WorkOrderManager} from "../src/WorkOrderManager.sol";
import {EquipmentManager} from "../src/EquipmentManager.sol";
import {ServiceLevelAgreement} from "../src/ServiceLevelAgreement.sol";

/// @notice Deploy all WES Field Operations contracts to Polygon mainnet
/// @dev Run: forge script script/DeployPolygon.s.sol:DeployWES --rpc-url $POLYGON_RPC_URL --broadcast --verify
contract DeployWES is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address paymentToken = vm.envAddress("USDC_ADDRESS"); // Polygon USDC

        console.log("Deploying WES Field Operations to Polygon...");
        console.log("Deployer:", vm.addr(deployerKey));
        console.log("Treasury:", treasury);
        console.log("Payment Token (USDC):", paymentToken);

        vm.startBroadcast(deployerKey);

        // 1. Deploy TechnicianRegistry
        TechnicianRegistry registry = new TechnicianRegistry();
        console.log("TechnicianRegistry deployed at:", address(registry));

        // 2. Deploy WorkOrderManager
        WorkOrderManager workOrders = new WorkOrderManager(
            address(registry),
            paymentToken,
            treasury
        );
        console.log("WorkOrderManager deployed at:", address(workOrders));

        // 3. Deploy EquipmentManager
        EquipmentManager equipment = new EquipmentManager();
        console.log("EquipmentManager deployed at:", address(equipment));

        // 4. Deploy ServiceLevelAgreement
        ServiceLevelAgreement sla = new ServiceLevelAgreement();
        console.log("ServiceLevelAgreement deployed at:", address(sla));

        // 5. Create default SLA templates
        // Emergency: 1hr response, 4hr completion, 2%/hr penalty, 5% bonus/hr
        uint256 emergencySLA = sla.createTemplate(
            "Emergency Response SLA",
            "Emergency",
            1 hours,       // 1hr max response
            4 hours,       // 4hr max completion
            200,           // 2% penalty per hour late
            500,           // 5% bonus per hour early
            5000           // 50% max penalty
        );
        console.log("Emergency SLA template:", emergencySLA);

        // Standard: 4hr response, 24hr completion
        uint256 standardSLA = sla.createTemplate(
            "Standard Response SLA",
            "Standard",
            4 hours,       // 4hr max response
            24 hours,      // 24hr max completion
            100,           // 1% penalty per hour late
            200,           // 2% bonus per hour early
            3000           // 30% max penalty
        );
        console.log("Standard SLA template:", standardSLA);

        // Scheduled: 24hr response, 72hr completion
        uint256 scheduledSLA = sla.createTemplate(
            "Scheduled Maintenance SLA",
            "Scheduled",
            24 hours,      // 24hr max response
            72 hours,      // 72hr max completion
            50,            // 0.5% penalty per hour late
            100,           // 1% bonus per hour early
            2000           // 20% max penalty
        );
        console.log("Scheduled SLA template:", scheduledSLA);

        vm.stopBroadcast();

        console.log("\n--- Deployment Summary ---");
        console.log("TechnicianRegistry:", address(registry));
        console.log("WorkOrderManager:  ", address(workOrders));
        console.log("EquipmentManager:  ", address(equipment));
        console.log("SLA:               ", address(sla));
        console.log("Platform Fee:      5% (500 bps)");
    }
}
