// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {SupplyChain} from "../src/SupplyChain.sol";

contract SupplyChainTest is Test {
    SupplyChain public sc;

    address admin = address(0xA);
    address warehouse = address(0xC);
    address supplier = address(0xD);
    address nobody = address(0xF);

    function setUp() public {
        sc = new SupplyChain(admin);
        vm.prank(admin);
        sc.addWarehouseManager(warehouse);
        vm.prank(admin);
        sc.registerSupplier(supplier, "Test Supplier");
    }

    // --- Create Item ---

    function test_CreateItem() public {
        vm.prank(warehouse);
        uint256 itemId = sc.createItem("Widget A", "A high-quality widget", "WDG-001", supplier);

        assertEq(itemId, 1);
        assertEq(sc.itemCount(), 1);

        SupplyChain.Item memory item = sc.getItem(itemId);
        assertEq(item.id, 1);
        assertEq(item.name, "Widget A");
        assertEq(uint8(item.stage), uint8(SupplyChain.ItemStage.Created));
    }

    function test_CreateItem_OnlyWarehouse() public {
        vm.prank(nobody);
        vm.expectRevert();
        sc.createItem("Widget", "desc", "SKU", supplier);
    }

    function test_CreateItem_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit SupplyChain.ItemCreated(1, "Widget A", "WDG-001", supplier);
        vm.prank(warehouse);
        sc.createItem("Widget A", "desc", "WDG-001", supplier);
    }

    // --- Stage Transitions ---

    function test_AdvanceStage_ManufacturedToInTransit() public {
        vm.prank(warehouse);
        uint256 itemId = sc.createItem("Widget", "desc", "SKU", supplier);

        vm.startPrank(warehouse);
        sc.updateStage(itemId, SupplyChain.ItemStage.Manufactured, "Factory A", "Manufacturing done");
        sc.updateStage(itemId, SupplyChain.ItemStage.InTransit, "Truck #42", "Shipped");
        vm.stopPrank();

        SupplyChain.Item memory item = sc.getItem(itemId);
        assertEq(uint8(item.stage), uint8(SupplyChain.ItemStage.InTransit));
    }

    function test_AdvanceStage_FullLifecycle() public {
        vm.prank(warehouse);
        uint256 itemId = sc.createItem("Widget", "desc", "SKU", supplier);

        vm.startPrank(warehouse);
        sc.updateStage(itemId, SupplyChain.ItemStage.Manufactured, "Factory", "Done");
        sc.updateStage(itemId, SupplyChain.ItemStage.InTransit, "Truck", "Shipped");
        sc.updateStage(itemId, SupplyChain.ItemStage.Received, "Warehouse B", "Received");
        sc.updateStage(itemId, SupplyChain.ItemStage.QualityChecked, "QC Lab", "Passed");
        sc.updateStage(itemId, SupplyChain.ItemStage.Delivered, "Customer Site", "Delivered");
        vm.stopPrank();

        SupplyChain.Item memory item = sc.getItem(itemId);
        assertEq(uint8(item.stage), uint8(SupplyChain.ItemStage.Delivered));
    }

    function test_CanDisputeFromAnyStage() public {
        vm.prank(warehouse);
        uint256 itemId = sc.createItem("Widget", "desc", "SKU", supplier);

        vm.prank(warehouse);
        sc.updateStage(itemId, SupplyChain.ItemStage.Disputed, "Unknown", "Damaged in transit");

        SupplyChain.Item memory item = sc.getItem(itemId);
        assertEq(uint8(item.stage), uint8(SupplyChain.ItemStage.Disputed));
    }

    function test_InvalidStageTransition_Revert() public {
        vm.prank(warehouse);
        uint256 itemId = sc.createItem("Widget", "desc", "SKU", supplier);

        vm.prank(warehouse);
        vm.expectRevert();
        sc.updateStage(itemId, SupplyChain.ItemStage.Delivered, "Location", "Skip");
    }

    function test_ItemDoesNotExist_Revert() public {
        vm.prank(warehouse);
        vm.expectRevert();
        sc.updateStage(999, SupplyChain.ItemStage.Manufactured, "Loc", "Notes");
    }

    // --- History ---

    function test_StageHistory() public {
        vm.prank(warehouse);
        uint256 itemId = sc.createItem("Widget", "desc", "SKU", supplier);

        vm.startPrank(warehouse);
        sc.updateStage(itemId, SupplyChain.ItemStage.Manufactured, "Factory", "Done");
        sc.updateStage(itemId, SupplyChain.ItemStage.InTransit, "Truck", "Shipped");
        vm.stopPrank();

        SupplyChain.StageHistory[] memory history = sc.getStageHistory(itemId);
        assertEq(history.length, 3); // Created + 2 updates
        assertEq(uint8(history[1].stage), uint8(SupplyChain.ItemStage.Manufactured));
        assertEq(uint8(history[2].stage), uint8(SupplyChain.ItemStage.InTransit));
    }

    // --- Supplier Items ---

    function test_SupplierItems() public {
        vm.prank(warehouse);
        uint256 id1 = sc.createItem("Item 1", "desc", "SKU1", supplier);
        vm.prank(warehouse);
        uint256 id2 = sc.createItem("Item 2", "desc", "SKU2", supplier);

        uint256[] memory items = sc.getSupplierItems(supplier);
        assertEq(items.length, 2);
        assertEq(items[0], id1);
        assertEq(items[1], id2);
    }

    // --- Supplier Can Update ---

    function test_SupplierCanUpdateOwnItem() public {
        vm.prank(warehouse);
        uint256 itemId = sc.createItem("Widget", "desc", "SKU", supplier);

        vm.prank(warehouse);
        sc.updateStage(itemId, SupplyChain.ItemStage.Manufactured, "Factory", "Done");

        vm.prank(supplier);
        sc.updateStage(itemId, SupplyChain.ItemStage.InTransit, "Truck", "Shipped by supplier");
    }

    function test_SupplierCannotUpdateOtherSupplierItem() public {
        address otherSupplier = address(0xDD);
        vm.prank(admin);
        sc.registerSupplier(otherSupplier, "Other Supplier");

        vm.prank(warehouse);
        uint256 itemId = sc.createItem("Widget", "desc", "SKU", otherSupplier);

        vm.prank(supplier);
        vm.expectRevert();
        sc.updateStage(itemId, SupplyChain.ItemStage.Manufactured, "Factory", "Fail");
    }
}
