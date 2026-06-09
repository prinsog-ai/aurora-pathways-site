// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AuroraPayments} from "../src/AuroraPayments.sol";

/// @notice Deploy AuroraPayments to a target chain
/// @dev Run: forge script script/Deploy.s.sol:DeployAuroraPayments --rpc-url $RPC_URL --broadcast
contract DeployAuroraPayments is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        AuroraPayments payments = new AuroraPayments(initialOwner);

        console.log("AuroraPayments deployed at:", address(payments));

        // Add stablecoins for the target chain
        // Polygon: USDC=0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359, USDT=0xc2132D05D31c914a87C6611C10748AEb04B58e8F
        // Base:     USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
        // Arbitrum: USDC=0xaf88d065e77c8cC2239327C5EDb3A432268e5831, USDT=0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9

        vm.stopBroadcast();
    }
}