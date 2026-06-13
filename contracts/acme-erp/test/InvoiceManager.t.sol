// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {InvoiceManager} from "../src/InvoiceManager.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract InvoiceManagerTest is Test {
    InvoiceManager public im;
    MockERC20 public usdc;

    address admin = address(0xA);
    address accountant = address(0xB);
    address approver = address(0xE);
    address payee = address(0xCC);
    address payer = address(0xDD);
    address nobody = address(0xF);

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        im = new InvoiceManager(admin, address(usdc));

        vm.prank(admin);
        im.addAccountant(accountant);
        vm.prank(admin);
        im.addApprover(approver);

        // Fund payer with USDC
        usdc.mint(payer, 1_000_000e6);
        // Approve InvoiceManager
        vm.prank(payer);
        usdc.approve(address(im), 1_000_000e6);
    }

    function test_CreateInvoice() public {
        vm.prank(accountant);
        uint256 invId = im.createInvoice(payee, 1000e6, block.timestamp + 30 days, "Invoice for widgets", "QmHash123");

        assertEq(invId, 1);
        assertEq(im.invoiceCount(), 1);

        InvoiceManager.Invoice memory inv = im.getInvoice(invId);
        assertEq(inv.id, 1);
        assertEq(uint8(inv.status), uint8(InvoiceManager.InvoiceStatus.Draft));
        assertEq(inv.description, "Invoice for widgets");
    }

    function test_FullInvoiceLifecycle() public {
        vm.prank(accountant);
        uint256 invId = im.createInvoice(payee, 1000e6, block.timestamp + 30 days, "Invoice", "QmHash");

        // Submit
        vm.prank(accountant);
        im.submitInvoice(invId);

        // Approve
        vm.prank(approver);
        im.approveInvoice(invId);

        // Pay
        vm.prank(payer);
        im.payInvoice(invId, 1000e6);

        InvoiceManager.Invoice memory inv = im.getInvoice(invId);
        assertEq(uint8(inv.status), uint8(InvoiceManager.InvoiceStatus.Paid));
        assertEq(inv.paidAmount, 1000e6);
        assertTrue(inv.paidAt > 0);
    }

    function test_PartialPayment() public {
        vm.prank(accountant);
        uint256 invId = im.createInvoice(payee, 1000e6, block.timestamp + 30 days, "Invoice", "QmHash");

        vm.prank(accountant);
        im.submitInvoice(invId);

        vm.prank(approver);
        im.approveInvoice(invId);

        // Pay 500 of 1000
        vm.prank(payer);
        im.payInvoice(invId, 500e6);

        InvoiceManager.Invoice memory inv = im.getInvoice(invId);
        assertEq(uint8(inv.status), uint8(InvoiceManager.InvoiceStatus.Approved)); // Still approved, not fully paid
        assertEq(inv.paidAmount, 500e6);
    }

    function test_CancelInvoice() public {
        vm.prank(accountant);
        uint256 invId = im.createInvoice(payee, 1000e6, block.timestamp + 30 days, "Invoice", "QmHash");

        vm.prank(accountant);
        im.cancelInvoice(invId);

        InvoiceManager.Invoice memory inv = im.getInvoice(invId);
        assertEq(uint8(inv.status), uint8(InvoiceManager.InvoiceStatus.Cancelled));
    }

    function test_OnlyAccountantCanCreate() public {
        vm.prank(nobody);
        vm.expectRevert();
        im.createInvoice(payee, 1000e6, block.timestamp + 30 days, "Invoice", "QmHash");
    }

    function test_OnlyApproverCanApprove() public {
        vm.prank(accountant);
        uint256 invId = im.createInvoice(payee, 1000e6, block.timestamp + 30 days, "Invoice", "QmHash");

        vm.prank(accountant);
        im.submitInvoice(invId);

        vm.prank(nobody);
        vm.expectRevert();
        im.approveInvoice(invId);
    }

    function test_CannotPayDraftInvoice() public {
        vm.prank(accountant);
        uint256 invId = im.createInvoice(payee, 1000e6, block.timestamp + 30 days, "Invoice", "QmHash");

        vm.prank(payer);
        vm.expectRevert();
        im.payInvoice(invId, 1000e6);
    }

    function test_LineItems() public {
        vm.prank(accountant);
        uint256 invId = im.createInvoice(payee, 300e6, block.timestamp + 30 days, "Invoice", "QmHash");

        vm.prank(accountant);
        im.addLineItem(invId, "Widget A", 10, 20e6);
        vm.prank(accountant);
        im.addLineItem(invId, "Widget B", 5, 20e6);

        InvoiceManager.InvoiceLineItem[] memory items = im.getLineItems(invId);
        assertEq(items.length, 2);
        assertEq(items[0].description, "Widget A");
        assertEq(items[1].quantity, 5);
    }

    function test_DisputeInvoice() public {
        vm.prank(accountant);
        uint256 invId = im.createInvoice(payee, 1000e6, block.timestamp + 30 days, "Invoice", "QmHash");

        vm.prank(accountant);
        im.submitInvoice(invId);
        vm.prank(approver);
        im.approveInvoice(invId);
        vm.prank(payer);
        im.payInvoice(invId, 1000e6);

        vm.prank(approver);
        im.disputeInvoice(invId, "Wrong amount");

        InvoiceManager.Invoice memory inv = im.getInvoice(invId);
        assertEq(uint8(inv.status), uint8(InvoiceManager.InvoiceStatus.Disputed));
    }
}
