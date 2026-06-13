// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERPAccessControl} from "./ERPAccessControl.sol";

/// @title InvoiceManager
/// @notice On-chain invoice management for Acme Cloud ERP
/// @dev Create, approve, and pay invoices using ERC-20 stablecoins
contract InvoiceManager is ERPAccessControl {
    using SafeERC20 for IERC20;

    // --- Enums ---
    enum InvoiceStatus {
        Draft,       // 0 — Created but not submitted
        Submitted,   // 1 — Submitted for approval
        Approved,    // 2 — Approved for payment
        Paid,        // 3 — Payment received
        Overdue,     // 4 — Past due date
        Cancelled,   // 5 — Cancelled
        Disputed     // 6 — Payment disputed
    }

    // --- Structs ---
    struct Invoice {
        uint256 id;
        uint256 purchaseOrderId;  // Link to purchase order (0 if standalone)
        address issuer;           // Company/team issuing
        address payee;            // Who receives payment
        uint256 amount;           // Amount in stablecoin (wei)
        address paymentToken;     // ERC-20 token address (e.g. USDC)
        InvoiceStatus status;
        uint256 issuedAt;
        uint256 dueDate;
        string description;
        string ipfsHash;          // IPFS CID for full invoice PDF/document
        uint256 paidAmount;       // Amount paid so far
        uint256 paidAt;           // Timestamp of full payment
    }

    struct InvoiceLineItem {
        string description;
        uint256 quantity;
        uint256 unitPrice;
    }

    // --- State ---
    uint256 public nextInvoiceId = 1;
    IERC20 public paymentToken;

    mapping(uint256 => Invoice) public invoices;
    mapping(uint256 => InvoiceLineItem[]) public lineItems;
    mapping(address => uint256[]) public issuerInvoices;
    mapping(address => uint256[]) public payeeInvoices;

    // --- Events ---
    event InvoiceCreated(
        uint256 indexed invoiceId,
        address indexed issuer,
        address indexed payee,
        uint256 amount,
        uint256 dueDate
    );
    event InvoiceSubmitted(uint256 indexed invoiceId);
    event InvoiceApproved(uint256 indexed invoiceId, address indexed approver);
    event InvoicePaid(uint256 indexed invoiceId, uint256 amount, uint256 timestamp);
    event InvoiceCancelled(uint256 indexed invoiceId);
    event InvoiceDisputed(uint256 indexed invoiceId, string reason);

    // --- Errors ---
    error InvoiceDoesNotExist(uint256 invoiceId);
    error InvalidStatusTransition(InvoiceStatus from, InvoiceStatus to);
    error InvoiceNotPayable(InvoiceStatus status);
    error InsufficientPayment(uint256 required, uint256 provided);
    error NotAuthorized();
    error InvoiceOverdue();

    constructor(address admin, address _paymentToken) ERPAccessControl(admin) {
        paymentToken = IERC20(_paymentToken);
    }

    /// @notice Create a new invoice
    /// @param payee Who receives the payment
    /// @param amount Amount in payment token wei
    /// @param dueDate Unix timestamp for due date
    /// @param description Invoice description
    /// @param ipfsHash IPFS CID for supporting documents
    /// @return invoiceId The new invoice ID
    function createInvoice(
        address payee,
        uint256 amount,
        uint256 dueDate,
        string calldata description,
        string calldata ipfsHash
    ) external onlyRole(ACCOUNTANT_ROLE) returns (uint256 invoiceId) {
        invoiceId = nextInvoiceId++;
        invoices[invoiceId] = Invoice({
            id: invoiceId,
            purchaseOrderId: 0,
            issuer: msg.sender,
            payee: payee,
            amount: amount,
            paymentToken: address(paymentToken),
            status: InvoiceStatus.Draft,
            issuedAt: block.timestamp,
            dueDate: dueDate,
            description: description,
            ipfsHash: ipfsHash,
            paidAmount: 0,
            paidAt: 0
        });

        issuerInvoices[msg.sender].push(invoiceId);
        payeeInvoices[payee].push(invoiceId);

        emit InvoiceCreated(invoiceId, msg.sender, payee, amount, dueDate);
    }

    /// @notice Link an invoice to a purchase order
    function linkToPurchaseOrder(uint256 invoiceId, uint256 purchaseOrderId) external {
        Invoice storage inv = invoices[invoiceId];
        if (inv.id == 0) revert InvoiceDoesNotExist(invoiceId);
        if (msg.sender != inv.issuer && !hasRole(ADMIN_ROLE, msg.sender)) revert NotAuthorized();
        inv.purchaseOrderId = purchaseOrderId;
    }

    /// @notice Add a line item to an invoice
    function addLineItem(
        uint256 invoiceId,
        string calldata description,
        uint256 quantity,
        uint256 unitPrice
    ) external {
        Invoice storage inv = invoices[invoiceId];
        if (inv.id == 0) revert InvoiceDoesNotExist(invoiceId);
        if (msg.sender != inv.issuer && !hasRole(ADMIN_ROLE, msg.sender)) revert NotAuthorized();

        lineItems[invoiceId].push(InvoiceLineItem({
            description: description,
            quantity: quantity,
            unitPrice: unitPrice
        }));
    }

    /// @notice Submit invoice for approval
    function submitInvoice(uint256 invoiceId) external {
        Invoice storage inv = invoices[invoiceId];
        if (inv.id == 0) revert InvoiceDoesNotExist(invoiceId);
        if (msg.sender != inv.issuer && !hasRole(ADMIN_ROLE, msg.sender)) revert NotAuthorized();
        if (inv.status != InvoiceStatus.Draft) revert InvalidStatusTransition(inv.status, InvoiceStatus.Submitted);

        inv.status = InvoiceStatus.Submitted;
        emit InvoiceSubmitted(invoiceId);
    }

    /// @notice Approve a submitted invoice
    function approveInvoice(uint256 invoiceId) external onlyRole(APPROVER_ROLE) {
        Invoice storage inv = invoices[invoiceId];
        if (inv.id == 0) revert InvoiceDoesNotExist(invoiceId);
        if (inv.status != InvoiceStatus.Submitted) revert InvalidStatusTransition(inv.status, InvoiceStatus.Approved);

        inv.status = InvoiceStatus.Approved;
        emit InvoiceApproved(invoiceId, msg.sender);
    }

    /// @notice Pay an approved invoice (full or partial)
    /// @param invoiceId The invoice to pay
    /// @param amount Amount to pay (in payment token wei)
    function payInvoice(uint256 invoiceId, uint256 amount) external {
        Invoice storage inv = invoices[invoiceId];
        if (inv.id == 0) revert InvoiceDoesNotExist(invoiceId);
        if (inv.status != InvoiceStatus.Approved) revert InvoiceNotPayable(inv.status);

        uint256 remaining = inv.amount - inv.paidAmount;
        if (amount > remaining) revert InsufficientPayment(remaining, amount);

        paymentToken.safeTransferFrom(msg.sender, inv.payee, amount);
        inv.paidAmount += amount;

        if (inv.paidAmount >= inv.amount) {
            inv.status = InvoiceStatus.Paid;
            inv.paidAt = block.timestamp;
        }

        emit InvoicePaid(invoiceId, amount, block.timestamp);
    }

    /// @notice Cancel a draft or submitted invoice
    function cancelInvoice(uint256 invoiceId) external {
        Invoice storage inv = invoices[invoiceId];
        if (inv.id == 0) revert InvoiceDoesNotExist(invoiceId);
        if (msg.sender != inv.issuer && !hasRole(ADMIN_ROLE, msg.sender)) revert NotAuthorized();
        if (inv.status != InvoiceStatus.Draft && inv.status != InvoiceStatus.Submitted) {
            revert InvalidStatusTransition(inv.status, InvoiceStatus.Cancelled);
        }

        inv.status = InvoiceStatus.Cancelled;
        emit InvoiceCancelled(invoiceId);
    }

    /// @notice Dispute a paid or approved invoice
    function disputeInvoice(uint256 invoiceId, string calldata reason) external onlyRole(APPROVER_ROLE) {
        Invoice storage inv = invoices[invoiceId];
        if (inv.id == 0) revert InvoiceDoesNotExist(invoiceId);
        if (inv.status != InvoiceStatus.Approved && inv.status != InvoiceStatus.Paid) {
            revert InvalidStatusTransition(inv.status, InvoiceStatus.Disputed);
        }

        inv.status = InvoiceStatus.Disputed;
        emit InvoiceDisputed(invoiceId, reason);
    }

    /// @notice Get all invoices for an issuer
    function getIssuerInvoices(address issuer) external view returns (uint256[] memory) {
        return issuerInvoices[issuer];
    }

    /// @notice Get all invoices for a payee
    function getPayeeInvoices(address payee) external view returns (uint256[] memory) {
        return payeeInvoices[payee];
    }

    /// @notice Get line items for an invoice
    function getLineItems(uint256 invoiceId) external view returns (InvoiceLineItem[] memory) {
        return lineItems[invoiceId];
    }

    /// @notice Get total invoice count
    function invoiceCount() external view returns (uint256) {
        return nextInvoiceId - 1;
    }

    /// @notice Get invoice details
    function getInvoice(uint256 invoiceId) external view returns (Invoice memory) {
        if (invoices[invoiceId].id == 0) revert InvoiceDoesNotExist(invoiceId);
        return invoices[invoiceId];
    }
}
