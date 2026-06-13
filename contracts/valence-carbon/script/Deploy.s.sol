// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ValenceCarbonCredit} from "../src/ValenceCarbonCredit.sol";
import {ValencePlatform} from "../src/ValencePlatform.sol";

/// @title DeployValence
/// @notice Deploy ValenceCarbonCredit + ValencePlatform to any chain
/// @dev CHAIN env: polygon, amoy, anvil (default)
///      Required env: PRIVATE_KEY, OWNER_ADDRESS
contract DeployValence is Script {
    struct ChainConfig {
        string name;
        uint256 chainId;
        string rpcEnv;
        string explorer;
    }

    /// @dev Default CO2 factor: 360 bps = 3.6% → 80,000 MCF ≈ 2,880 tons CO2
    uint256 constant DEFAULT_CO2_FACTOR = 360;

    function run() external {
        string memory chain = vm.envOr("CHAIN", string("anvil"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.envAddress("OWNER_ADDRESS");

        ChainConfig memory config = getChainConfig(chain);

        console.log("=== Valence Carbon Credit Deploy ===");
        console.log("Chain:", config.name);
        console.log("Chain ID:", config.chainId);
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Owner:", initialOwner);
        console.log("CO2 Factor:", DEFAULT_CO2_FACTOR);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy token
        ValenceCarbonCredit token = new ValenceCarbonCredit(initialOwner);
        console.log("ValenceCarbonCredit deployed at:", address(token));
        console.log("  Name:", token.name());
        console.log("  Symbol:", token.symbol());

        // 2. Transfer token ownership to platform after platform deploy
        // For now, we need the platform to own the token for minting
        // Strategy: deployer owns token, deploy platform, then transfer token ownership to platform

        // 3. Deploy platform — initially owned by deployer so they can configure
        //    Token ownership will be transferred to platform after deploy
        ValencePlatform platform = new ValencePlatform(
            initialOwner,
            address(token),
            DEFAULT_CO2_FACTOR
        );
        console.log("ValencePlatform deployed at:", address(platform));

        // 4. Transfer token ownership to platform so it can mint
        // Note: only do this if deployer == initialOwner
        token.transferOwnership(address(platform));
        console.log("Token ownership transferred to platform");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("VCC Token:  ", address(token));
        console.log("Platform:   ", address(platform));
        console.log("Owner:      ", initialOwner);
        console.log("");
        console.log("=== Verify Commands ===");
        console.log("forge verify-contract \\");
        console.log(string.concat("  --chain-id ", vm.toString(config.chainId), " \\"));
        console.log(string.concat("  --etherscan-api-key $", getExplorerApiKeyEnv(chain), " \\"));
        console.log(string.concat("  --constructor-args $(cast abi-encode \"constructor(address)\" ", vm.toString(initialOwner), ") \\"));
        console.log(string.concat("  ", vm.toString(address(token)), " \\"));
        console.log("  src/ValenceCarbonCredit.sol:ValenceCarbonCredit");
        console.log("");
        console.log("forge verify-contract \\");
        console.log(string.concat("  --chain-id ", vm.toString(config.chainId), " \\"));
        console.log(string.concat("  --etherscan-api-key $", getExplorerApiKeyEnv(chain), " \\"));
        console.log(string.concat("  --constructor-args $(cast abi-encode \"constructor(address,address,uint256)\" ", vm.toString(initialOwner), " ", vm.toString(address(token)), " ", vm.toString(DEFAULT_CO2_FACTOR), ") \\"));
        console.log(string.concat("  ", vm.toString(address(platform)), " \\"));
        console.log("  src/ValencePlatform.sol:ValencePlatform");
    }

    function getChainConfig(string memory chain) internal pure returns (ChainConfig memory) {
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("polygon"))) {
            return ChainConfig("Polygon PoS", 137, "POLYGON_RPC_URL", "https://polygonscan.com");
        }
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("amoy"))) {
            return ChainConfig("Polygon Amoy (Testnet)", 80002, "AMOY_RPC_URL", "https://amoy.polygonscan.com");
        }
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("anvil"))) {
            return ChainConfig("Anvil (Local)", 31337, "ANVIL_RPC_URL", "local");
        }
        revert(string.concat("Unknown chain: ", chain, ". Use: polygon, amoy, anvil"));
    }

    function getExplorerApiKeyEnv(string memory chain) internal pure returns (string memory) {
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("polygon")) ||
            keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("amoy"))) {
            return "POLYGONSCAN_API_KEY";
        }
        return "ETHERSCAN_API_KEY";
    }
}
