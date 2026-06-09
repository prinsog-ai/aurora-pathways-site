// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/Forekast.sol";

contract DeployForekast is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        // Polygon mainnet USDC
        address usdc = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

        vm.startBroadcast(privateKey);
        Forekast forekast = new Forekast(usdc, deployer);
        vm.stopBroadcast();

        console.log("Forekast deployed at:", address(forekast));
    }
}
