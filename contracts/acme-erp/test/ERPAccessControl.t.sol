// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERPAccessControl} from "../src/ERPAccessControl.sol";

contract ERPAccessControlTest is Test {
    ERPAccessControl public acl;

    address admin = address(0xA);
    address accountant = address(0xB);
    address warehouse = address(0xC);
    address supplier = address(0xD);
    address approver = address(0xE);
    address nobody = address(0xF);

    function setUp() public {
        acl = new ERPAccessControl(admin);
    }

    // --- Role Setup ---

    function test_AdminHasRoles() public view {
        assertTrue(acl.hasRole(acl.ADMIN_ROLE(), admin));
        assertTrue(acl.hasRole(acl.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_AddAccountant() public {
        vm.prank(admin);
        acl.addAccountant(accountant);
        assertTrue(acl.hasRole(acl.ACCOUNTANT_ROLE(), accountant));
    }

    function test_AddWarehouseManager() public {
        vm.prank(admin);
        acl.addWarehouseManager(warehouse);
        assertTrue(acl.hasRole(acl.WAREHOUSE_ROLE(), warehouse));
    }

    function test_AddApprover() public {
        vm.prank(admin);
        acl.addApprover(approver);
        assertTrue(acl.hasRole(acl.APPROVER_ROLE(), approver));
    }

    // --- Supplier Registration ---

    function test_RegisterSupplier() public {
        vm.prank(admin);
        acl.registerSupplier(supplier, "Acme Supplies Inc");
        assertTrue(acl.isSupplier(supplier));
        assertEq(acl.supplierName(supplier), "Acme Supplies Inc");
        assertTrue(acl.hasRole(acl.SUPPLIER_ROLE(), supplier));
    }

    function test_DeregisterSupplier() public {
        vm.prank(admin);
        acl.registerSupplier(supplier, "Acme Supplies Inc");

        vm.prank(admin);
        acl.deregisterSupplier(supplier);
        assertFalse(acl.isSupplier(supplier));
        assertFalse(acl.hasRole(acl.SUPPLIER_ROLE(), supplier));
    }

    // --- Access Control ---

    function test_NonAdminCannotAddRoles() public {
        vm.prank(nobody);
        vm.expectRevert();
        acl.addAccountant(accountant);
    }

    function test_NonAdminCannotRegisterSupplier() public {
        vm.prank(nobody);
        vm.expectRevert();
        acl.registerSupplier(supplier, "Bad Actor");
    }

    function test_SupplierRegisteredEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ERPAccessControl.SupplierRegistered(supplier, "Test Supplier");
        vm.prank(admin);
        acl.registerSupplier(supplier, "Test Supplier");
    }
}
