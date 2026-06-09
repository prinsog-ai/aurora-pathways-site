// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AuroraNFT} from "../src/AuroraNFT.sol";

/// @title DeployAuroraNFT
/// @notice Deploy an AuroraNFT collection with configurable parameters
///
/// Required env vars:
///   PRIVATE_KEY            — deployer's private key
///   OWNER_ADDRESS          — initial NFT contract owner
///   ROYALTY_RECEIVER       — address receiving secondary sale royalties
///
/// Optional (configurable in .env):
///   NFT_NAME               — collection name (default: "Aurora Pathways NFT")
///   NFT_SYMBOL             — collection symbol (default: "APNFT")
///   MAX_SUPPLY             — max tokens (default: 10000)
///   PUBLIC_PRICE           — public mint price in wei (default: 0.1 ether)
///   WHITELIST_PRICE        — whitelist mint price in wei (default: 0.05 ether)
///   MAX_PER_WALLET         — max tokens per wallet (default: 10)
///   ROYALTY_BPS            — royalty in basis points (default: 500 = 5%)
contract DeployAuroraNFT is Script {
    function run() external {
        // Load required vars
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address royaltyReceiver = vm.envAddress("ROYALTY_RECEIVER");

        // Load optional vars with defaults
        string memory name = vm.envOr("NFT_NAME", string("Aurora Pathways NFT"));
        string memory symbol = vm.envOr("NFT_SYMBOL", string("APNFT"));
        uint256 maxSupply = vm.envOr("MAX_SUPPLY", uint256(10000));
        uint256 publicPrice = vm.envOr("PUBLIC_PRICE", uint256(0.1 ether));
        uint256 whitelistPrice = vm.envOr("WHITELIST_PRICE", uint256(0.05 ether));
        uint256 maxPerWallet = vm.envOr("MAX_PER_WALLET", uint256(10));
        uint96 royaltyBps = uint96(vm.envOr("ROYALTY_BPS", uint256(500)));

        vm.startBroadcast(deployerKey);

        AuroraNFT nft = new AuroraNFT(
            name,
            symbol,
            maxSupply,
            publicPrice,
            whitelistPrice,
            maxPerWallet,
            royaltyReceiver,
            royaltyBps,
            owner
        );

        console.log("AuroraNFT deployed at:", address(nft));

        vm.stopBroadcast();

        console.log("\n=== Aurora NFT Collection Deployed ===");
        console.log("Name:           ", name);
        console.log("Symbol:         ", symbol);
        console.log("Max Supply:     ", maxSupply);
        console.log("Public Price:   ", publicPrice);
        console.log("Whitelist Price:", whitelistPrice);
        console.log("Max Per Wallet: ", maxPerWallet);
        console.log("Royalty:        ", royaltyBps, "bps");
        console.log("Owner:          ", owner);
        console.log("Royalty Recv:   ", royaltyReceiver);
        console.log("Contract:       ", address(nft));
        console.log("=======================================");
    }
}
