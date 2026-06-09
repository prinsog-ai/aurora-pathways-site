// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AuroraToken} from "../src/AuroraToken.sol";

/// @notice Deploy AuroraToken to a network
/// @dev Run with: forge script script/Deploy.s.sol:DeployAuroraToken --rpc-url $RPC_URL --broadcast --verify
contract DeployAuroraToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        AuroraToken token = new AuroraToken(initialOwner);

        console.log("AuroraToken deployed at:", address(token));
        console.log("Owner:", token.owner());

        vm.stopBroadcast();
    }
}
