// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AuroraToken} from "../src/AuroraToken.sol";

/// @title MultiChainDeploy
/// @notice Deploy AuroraToken to Polygon, Base, Arbitrum, or local Anvil
/// @dev Choose chain with CHAIN env var: polygon, base, arbitrum, anvil
contract MultiChainDeploy is Script {
    struct ChainConfig {
        string name;
        uint256 chainId;
        string rpcEnv;    // env var name for RPC URL
        string explorer;  // explorer URL for verification
    }

    function run() external {
        string memory chain = vm.envOr("CHAIN", string("anvil"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.envAddress("OWNER_ADDRESS");

        ChainConfig memory config = getChainConfig(chain);

        console.log("=== AuroraToken Multi-Chain Deploy ===");
        console.log("Chain:", config.name);
        console.log("Chain ID:", config.chainId);
        console.log("RPC:", vm.envString(config.rpcEnv));
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Owner:", initialOwner);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        AuroraToken token = new AuroraToken(initialOwner);

        console.log("AuroraToken deployed at:", address(token));
        console.log("");

        vm.stopBroadcast();

        console.log("=== Verify ===");
        console.log("forge verify-contract \\");
        console.log(string.concat("  --chain-id ", vm.toString(config.chainId), " \\"));
        console.log(string.concat("  --etherscan-api-key $", getExplorerApiKeyEnv(chain), " \\"));
        console.log(string.concat("  --constructor-args $(cast abi-encode \"constructor(address)\" ", vm.toString(initialOwner), ") \\"));
        console.log(string.concat("  ", vm.toString(address(token)), " \\"));
        console.log("  src/AuroraToken.sol:AuroraToken");
    }

    function getChainConfig(string memory chain) internal pure returns (ChainConfig memory) {
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("polygon"))) {
            return ChainConfig("Polygon PoS", 137, "POLYGON_RPC_URL", "https://polygonscan.com");
        }
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("amoy"))) {
            return ChainConfig("Polygon Amoy (Testnet)", 80002, "AMOY_RPC_URL", "https://amoy.polygonscan.com");
        }
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("base"))) {
            return ChainConfig("Base", 8453, "BASE_RPC_URL", "https://basescan.org");
        }
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("base-sepolia"))) {
            return ChainConfig("Base Sepolia (Testnet)", 84532, "BASE_SEPOLIA_RPC_URL", "https://sepolia.basescan.org");
        }
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("arbitrum"))) {
            return ChainConfig("Arbitrum One", 42161, "ARBITRUM_RPC_URL", "https://arbiscan.io");
        }
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("arbitrum-sepolia"))) {
            return ChainConfig("Arbitrum Sepolia (Testnet)", 421614, "ARBITRUM_SEPOLIA_RPC_URL", "https://sepolia.arbiscan.io");
        }
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("anvil"))) {
            return ChainConfig("Anvil (Local)", 31337, "ANVIL_RPC_URL", "local");
        }
        revert(string.concat("Unknown chain: ", chain, ". Use: polygon, amoy, base, base-sepolia, arbitrum, arbitrum-sepolia, anvil"));
    }

    function getExplorerApiKeyEnv(string memory chain) internal pure returns (string memory) {
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("polygon")) || keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("amoy"))) {
            return "POLYGONSCAN_API_KEY";
        }
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("base")) || keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("base-sepolia"))) {
            return "BASESCAN_API_KEY";
        }
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("arbitrum")) || keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("arbitrum-sepolia"))) {
            return "ARBISCAN_API_KEY";
        }
        return "ETHERSCAN_API_KEY";
    }
}