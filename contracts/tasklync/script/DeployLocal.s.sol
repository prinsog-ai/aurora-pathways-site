// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TaskEscrow} from "../src/TaskEscrow.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DeployLocal is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY_ADDRESS");

        vm.startBroadcast(deployerKey);

        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));

        TaskEscrow escrow = new TaskEscrow(treasury);
        console.log("TaskEscrow deployed at:", address(escrow));

        // Mint test USDC to Account #0
        usdc.mint(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 1000000 * 1e6); // 1M USDC
        console.log("Minted 1M USDC to Account #0");

        vm.stopBroadcast();
    }
}