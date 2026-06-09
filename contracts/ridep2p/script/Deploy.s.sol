// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/RideP2P.sol";

contract DeployRideP2P is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Polygon Mainnet USDC
        address usdc = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

        vm.startBroadcast(deployerPrivateKey);

        RideP2P ridep2p = new RideP2P(usdc);

        vm.stopBroadcast();

        console.log("RideP2P deployed at:", address(ridep2p));
        console.log("Deployer:", deployer);
        console.log("USDC address:", usdc);
    }
}
