// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERPAccessControl} from "../src/ERPAccessControl.sol";
import {SupplyChain} from "../src/SupplyChain.sol";
import {InvoiceManager} from "../src/InvoiceManager.sol";
import {PurchaseOrder} from "../src/PurchaseOrder.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";

/// @title DeployAcmeERP
/// @notice Deploy all Acme Cloud ERP modules
/// @dev Run with: forge script script/DeployAcmeERP.s.sol:DeployAcmeERP --rpc-url $RPC_URL --broadcast --verify
contract DeployAcmeERP is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.envAddress("OWNER_ADDRESS");

        // Payment token (USDC on Polygon)
        address usdcAddress = vm.envOr("PAYMENT_TOKEN", address(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359));
        // Number of required approvals for purchase orders
        uint256 requiredApprovals = vm.envOr("REQUIRED_APPROVALS", uint256(2));
        // Annual depreciation rate in basis points (2000 = 20%)
        uint256 depreciationRateBps = vm.envOr("DEPRECIATION_RATE_BPS", uint256(2000));

        console.log("=== Acme Cloud ERP - Multi-Module Deploy ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Owner:", initialOwner);
        console.log("Payment Token:", usdcAddress);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. ERPAccessControl (shared by all modules)
        console.log("1/5 Deploying ERPAccessControl...");
        ERPAccessControl acl = new ERPAccessControl(initialOwner);
        console.log("   ERPAccessControl:", address(acl));

        // 2. SupplyChain
        console.log("2/5 Deploying SupplyChain...");
        SupplyChain sc = new SupplyChain(initialOwner);
        console.log("   SupplyChain:", address(sc));

        // 3. InvoiceManager
        console.log("3/5 Deploying InvoiceManager...");
        InvoiceManager im = new InvoiceManager(initialOwner, usdcAddress);
        console.log("   InvoiceManager:", address(im));

        // 4. PurchaseOrder
        console.log("4/5 Deploying PurchaseOrder...");
        PurchaseOrder po = new PurchaseOrder(initialOwner, requiredApprovals);
        console.log("   PurchaseOrder:", address(po));

        // 5. AssetRegistry
        console.log("5/5 Deploying AssetRegistry...");
        AssetRegistry ar = new AssetRegistry(initialOwner, depreciationRateBps);
        console.log("   AssetRegistry:", address(ar));

        vm.stopBroadcast();

        console.log("");
        console.log("=== All modules deployed! ===");
        console.log("");
        console.log("=== Contract Addresses ===");
        console.log("ERPAccessControl:", address(acl));
        console.log("SupplyChain:", address(sc));
        console.log("InvoiceManager:", address(im));
        console.log("PurchaseOrder:", address(po));
        console.log("AssetRegistry:", address(ar));
    }
}
