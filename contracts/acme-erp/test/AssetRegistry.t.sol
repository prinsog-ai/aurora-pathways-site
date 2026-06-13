// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AssetRegistry} from "../src/AssetRegistry.sol";

contract AssetRegistryTest is Test {
    AssetRegistry public ar;

    address admin = address(0xA);
    address warehouse = address(0xC);
    address employee = address(0xEE);
    address nobody = address(0xF);

    function setUp() public {
        // 20% annual depreciation
        ar = new AssetRegistry(admin, 2000);

        vm.prank(admin);
        ar.addWarehouseManager(warehouse);
    }

    // --- Register ---

    function test_RegisterAsset() public {
        vm.prank(warehouse);
        uint256 assetId = ar.registerAsset(
            "Dell Laptop",
            "Precision 5570",
            AssetRegistry.AssetCategory.IT,
            2500e6,
            block.timestamp - 365 days,
            "SN-12345",
            "Office A",
            "QmHash"
        );

        assertEq(assetId, 1);
        assertEq(ar.assetCount(), 1);

        AssetRegistry.Asset memory asset = ar.getAsset(assetId);
        assertEq(asset.id, 1);
        assertEq(asset.name, "Dell Laptop");
        assertEq(uint8(asset.status), uint8(AssetRegistry.AssetStatus.Active));
    }

    function test_RegisterAsset_OnlyWarehouse() public {
        vm.prank(nobody);
        vm.expectRevert();
        ar.registerAsset("Laptop", "desc", AssetRegistry.AssetCategory.IT, 2500e6, block.timestamp, "SN", "Loc", "Qm");
    }

    // --- Status ---

    function test_UpdateStatus() public {
        vm.prank(warehouse);
        uint256 assetId = ar.registerAsset("Laptop", "desc", AssetRegistry.AssetCategory.IT, 2500e6, block.timestamp, "SN", "Loc", "Qm");

        vm.prank(warehouse);
        ar.updateStatus(assetId, AssetRegistry.AssetStatus.Maintenance);

        AssetRegistry.Asset memory asset = ar.getAsset(assetId);
        assertEq(uint8(asset.status), uint8(AssetRegistry.AssetStatus.Maintenance));
    }

    function test_DisposeAsset() public {
        vm.prank(warehouse);
        uint256 assetId = ar.registerAsset("Laptop", "desc", AssetRegistry.AssetCategory.IT, 2500e6, block.timestamp, "SN", "Loc", "Qm");

        vm.prank(warehouse);
        ar.updateStatus(assetId, AssetRegistry.AssetStatus.Retired);

        vm.prank(warehouse);
        ar.updateStatus(assetId, AssetRegistry.AssetStatus.Disposed);

        AssetRegistry.Asset memory asset = ar.getAsset(assetId);
        assertEq(uint8(asset.status), uint8(AssetRegistry.AssetStatus.Disposed));
    }

    function test_CannotChangeDisposed() public {
        vm.prank(warehouse);
        uint256 assetId = ar.registerAsset("Laptop", "desc", AssetRegistry.AssetCategory.IT, 2500e6, block.timestamp, "SN", "Loc", "Qm");

        vm.prank(warehouse);
        ar.updateStatus(assetId, AssetRegistry.AssetStatus.Disposed);

        vm.prank(warehouse);
        vm.expectRevert();
        ar.updateStatus(assetId, AssetRegistry.AssetStatus.Active);
    }

    // --- Assign ---

    function test_AssignAsset() public {
        vm.prank(warehouse);
        uint256 assetId = ar.registerAsset("Laptop", "desc", AssetRegistry.AssetCategory.IT, 2500e6, block.timestamp, "SN", "Loc", "Qm");

        vm.prank(warehouse);
        ar.assignAsset(assetId, employee);

        AssetRegistry.Asset memory asset = ar.getAsset(assetId);
        assertEq(asset.assignedTo, employee);

        uint256[] memory assigned = ar.getAssignedAssets(employee);
        assertEq(assigned.length, 1);
        assertEq(assigned[0], assetId);
    }

    // --- Maintenance ---

    function test_RecordMaintenance() public {
        vm.prank(warehouse);
        uint256 assetId = ar.registerAsset("Laptop", "desc", AssetRegistry.AssetCategory.IT, 2500e6, block.timestamp, "SN", "Loc", "Qm");

        vm.prank(warehouse);
        ar.recordMaintenance(assetId, "Battery replacement", 150e6, block.timestamp + 180 days);

        AssetRegistry.MaintenanceRecord[] memory records = ar.getMaintenanceHistory(assetId);
        assertEq(records.length, 1);
        assertEq(records[0].cost, 150e6);
        assertEq(records[0].description, "Battery replacement");
    }

    // --- Depreciation ---

    function test_DepreciatedValue() public {
        vm.prank(warehouse);
        uint256 assetId = ar.registerAsset(
            "Server",
            "desc",
            AssetRegistry.AssetCategory.IT,
            10000e6,
            block.timestamp - 365 days, // 1 year old
            "SN",
            "Loc",
            "Qm"
        );

        uint256 currentValue = ar.getDepreciatedValue(assetId);
        // 20% of 10000 = 2000 depreciation, value = 8000
        assertEq(currentValue, 8000e6);
    }

    function test_DepreciationFullyDepreciated() public {
        vm.prank(warehouse);
        uint256 assetId = ar.registerAsset(
            "Old Server",
            "desc",
            AssetRegistry.AssetCategory.IT,
            10000e6,
            block.timestamp - 6 * 365 days, // 6 years old (120% depreciated)
            "SN",
            "Loc",
            "Qm"
        );

        uint256 currentValue = ar.getDepreciatedValue(assetId);
        assertEq(currentValue, 0);
    }

    // --- Category Count ---

    function test_CategoryCount() public {
        vm.startPrank(warehouse);
        ar.registerAsset("Laptop 1", "desc", AssetRegistry.AssetCategory.IT, 2000e6, block.timestamp, "SN1", "Loc", "Qm");
        ar.registerAsset("Laptop 2", "desc", AssetRegistry.AssetCategory.IT, 2000e6, block.timestamp, "SN2", "Loc", "Qm");
        ar.registerAsset("Desk", "desc", AssetRegistry.AssetCategory.Furniture, 500e6, block.timestamp, "SN3", "Loc", "Qm");
        vm.stopPrank();

        assertEq(ar.categoryCount(AssetRegistry.AssetCategory.IT), 2);
        assertEq(ar.categoryCount(AssetRegistry.AssetCategory.Furniture), 1);
        assertEq(ar.assetCount(), 3);
    }
}
