// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AcmeAuditTrail.sol";
import "../src/AcmeSupplyChain.sol";
import "../src/AcmeSettlement.sol";

contract DeployAcme is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        AcmeAuditTrail audit = new AcmeAuditTrail();
        console.log("AcmeAuditTrail:", address(audit));

        AcmeSupplyChain supply = new AcmeSupplyChain();
        console.log("AcmeSupplyChain:", address(supply));

        AcmeSettlement sett = new AcmeSettlement();
        console.log("AcmeSettlement:", address(sett));

        vm.stopBroadcast();
    }
}
