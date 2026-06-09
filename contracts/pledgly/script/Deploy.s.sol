// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Pledgly} from "../src/Pledgly.sol";

/// @notice Deploy Pledgly to Polygon Amoy testnet
/// @dev Run: forge script script/Deploy.s.sol:DeployPledgly --rpc-url $RPC_URL --broadcast
contract DeployPledgly is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address usdc         = vm.envAddress("USDC_ADDRESS");
        address govToken     = vm.envAddress("GOVERNANCE_TOKEN");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        vm.startBroadcast(deployerKey);

        Pledgly pledgly = new Pledgly(usdc, govToken, feeRecipient);

        console.log("Pledgly deployed at:", address(pledgly));
        console.log("USDC:", usdc);
        console.log("Governance Token:", govToken);
        console.log("Fee Recipient:", feeRecipient);
        console.log("Platform Fee:", pledgly.platformFeeBps(), "bps (2%)");

        vm.stopBroadcast();
    }
}
