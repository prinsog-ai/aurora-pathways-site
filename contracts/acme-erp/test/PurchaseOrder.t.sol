// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PurchaseOrder} from "../src/PurchaseOrder.sol";

contract PurchaseOrderTest is Test {
    PurchaseOrder public po;

    address admin = address(0xA);
    address warehouse = address(0xC);
    address supplier = address(0xD);
    address approver1 = address(0xE1);
    address approver2 = address(0xE2);
    address accountant = address(0xB);
    address nobody = address(0xF);

    function setUp() public {
        // Require 2 approvals
        po = new PurchaseOrder(admin, 2);

        vm.startPrank(admin);
        po.addWarehouseManager(warehouse);
        po.addApprover(approver1);
        po.addApprover(approver2);
        po.addAccountant(accountant);
        vm.stopPrank();
    }

    function _createAndSubmitPO() internal returns (uint256 poId) {
        vm.startPrank(warehouse);
        poId = po.createPO(supplier, 5000e6, address(0x1), block.timestamp + 14 days, "Order widgets", "QmHash");
        po.addLineItem(poId, "Widget A", 100, 30e6);
        po.addLineItem(poId, "Widget B", 50, 40e6);
        po.submitPO(poId);
        vm.stopPrank();
    }

    // --- Create ---

    function test_CreatePO() public {
        vm.prank(warehouse);
        uint256 poId = po.createPO(supplier, 5000e6, address(0x1), block.timestamp + 14 days, "Order", "QmHash");
        assertEq(poId, 1);
        assertEq(po.poCount(), 1);
    }

    function test_CreatePO_OnlyWarehouse() public {
        vm.prank(nobody);
        vm.expectRevert();
        po.createPO(supplier, 5000e6, address(0x1), block.timestamp + 14 days, "Order", "QmHash");
    }

    // --- Line Items ---

    function test_AddLineItems() public {
        vm.startPrank(warehouse);
        uint256 poId = po.createPO(supplier, 5000e6, address(0x1), block.timestamp + 14 days, "Order", "QmHash");
        po.addLineItem(poId, "Widget A", 100, 30e6);
        po.addLineItem(poId, "Widget B", 50, 40e6);
        vm.stopPrank();

        PurchaseOrder.POLineItem[] memory items = po.getLineItems(poId);
        assertEq(items.length, 2);
        assertEq(items[0].totalPrice, 3000e6);
        assertEq(items[1].totalPrice, 2000e6);
    }

    // --- Submit ---

    function test_SubmitPO() public {
        uint256 poId = _createAndSubmitPO();

        PurchaseOrder.PurchaseOrderData memory poData = po.getPO(poId);
        assertEq(uint8(poData.status), uint8(PurchaseOrder.POStatus.Submitted));
    }

    function test_CannotSubmitWithoutLineItems() public {
        vm.prank(warehouse);
        uint256 poId = po.createPO(supplier, 5000e6, address(0x1), block.timestamp + 14 days, "Order", "QmHash");

        vm.prank(warehouse);
        vm.expectRevert();
        po.submitPO(poId);
    }

    // --- Approval ---

    function test_MultiApproval() public {
        uint256 poId = _createAndSubmitPO();

        vm.prank(approver1);
        po.approvePO(poId, true, "Approved by manager 1");

        // Not yet fully approved (need 2)
        PurchaseOrder.PurchaseOrderData memory poData1 = po.getPO(poId);
        assertEq(uint8(poData1.status), uint8(PurchaseOrder.POStatus.Submitted));

        vm.prank(approver2);
        po.approvePO(poId, true, "Approved by manager 2");

        PurchaseOrder.PurchaseOrderData memory poData2 = po.getPO(poId);
        assertEq(uint8(poData2.status), uint8(PurchaseOrder.POStatus.Approved));
    }

    function test_Rejection() public {
        uint256 poId = _createAndSubmitPO();

        vm.prank(approver1);
        po.approvePO(poId, false, "Too expensive");

        PurchaseOrder.PurchaseOrderData memory poData = po.getPO(poId);
        assertEq(uint8(poData.status), uint8(PurchaseOrder.POStatus.Rejected));
    }

    function test_CannotApproveTwice() public {
        uint256 poId = _createAndSubmitPO();

        vm.prank(approver1);
        po.approvePO(poId, true, "OK");

        vm.prank(approver1);
        vm.expectRevert();
        po.approvePO(poId, true, "Again");
    }

    // --- Full Lifecycle ---

    function test_FullPOLifecycle() public {
        uint256 poId = _createAndSubmitPO();

        // Approve
        vm.prank(approver1);
        po.approvePO(poId, true, "OK1");
        vm.prank(approver2);
        po.approvePO(poId, true, "OK2");

        // Fulfill
        vm.prank(warehouse);
        po.fulfillPO(poId);

        // Complete
        vm.prank(accountant);
        po.completePO(poId);

        PurchaseOrder.PurchaseOrderData memory poData = po.getPO(poId);
        assertEq(uint8(poData.status), uint8(PurchaseOrder.POStatus.Completed));
    }

    // --- Cancel ---

    function test_CancelDraftPO() public {
        vm.prank(warehouse);
        uint256 poId = po.createPO(supplier, 5000e6, address(0x1), block.timestamp + 14 days, "Order", "QmHash");

        vm.prank(warehouse);
        po.cancelPO(poId);

        PurchaseOrder.PurchaseOrderData memory poData = po.getPO(poId);
        assertEq(uint8(poData.status), uint8(PurchaseOrder.POStatus.Cancelled));
    }

    function test_CannotCancelApprovedPO() public {
        uint256 poId = _createAndSubmitPO();

        vm.prank(approver1);
        po.approvePO(poId, true, "OK");
        vm.prank(approver2);
        po.approvePO(poId, true, "OK");

        vm.prank(warehouse);
        vm.expectRevert();
        po.cancelPO(poId);
    }
}
