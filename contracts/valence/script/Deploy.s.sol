// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/CarbonCredit.sol";
import "../src/CreditSplitter.sol";
import "../src/AttestationModule.sol";

contract DeployValence is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        CarbonCredit credit = new CarbonCredit(vm.addr(deployerKey));
        console.log("CarbonCredit:", address(credit));

        CreditSplitter splitter = new CreditSplitter(address(credit));
        console.log("CreditSplitter:", address(splitter));

        AttestationModule attestation = new AttestationModule(address(credit), address(splitter));
        console.log("AttestationModule:", address(attestation));

        credit.setMinter(address(attestation));
        console.log("Minter set to AttestationModule");

        vm.stopBroadcast();
    }
}
