// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PledglyV2.sol";

contract DeployPledglyV2 is Script {
    function run() external {
        // Real USDC on Polygon Mainnet
        address usdc = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

        vm.startBroadcast();
        PledglyV2 pledgly = new PledglyV2(usdc);
        vm.stopBroadcast();

        console.log("PledglyV2 deployed at:", address(pledgly));
    }
}
