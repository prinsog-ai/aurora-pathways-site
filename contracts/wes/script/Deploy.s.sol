// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/WESJobTicket.sol";
import "../src/WESCompliance.sol";

contract DeployWES is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        WESJobTicket jobs = new WESJobTicket();
        console.log("WESJobTicket:", address(jobs));

        WESCompliance compliance = new WESCompliance();
        console.log("WESCompliance:", address(compliance));

        vm.stopBroadcast();
    }
}
