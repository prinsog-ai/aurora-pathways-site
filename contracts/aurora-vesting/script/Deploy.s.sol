// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TokenVesting} from "../src/TokenVesting.sol";

/// @notice Deploy TokenVesting
/// @dev Run: forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
contract DeployTokenVesting is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address owner = vm.envAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        TokenVesting vesting = new TokenVesting(tokenAddress, owner);

        vm.stopBroadcast();

        console.log("TokenVesting deployed at:", address(vesting));
        console.log("Token:", tokenAddress);
        console.log("Owner:", owner);
    }
}