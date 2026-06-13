// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERPAccessControl} from "./ERPAccessControl.sol";

/// @title PurchaseOrder
/// @notice On-chain purchase order management for Acme Cloud ERP
/// @dev Full lifecycle: Draft → Submitted → Approved → Fulfilled → Completed
contract PurchaseOrder is ERPAccessControl {
    // --- Enums ---
    enum POStatus {
        Draft,       // 0 — Being created
        Submitted,   // 1 — Submitted for approval
        Approved,    // 2 — Approved by management
        Rejected,    // 3 — Rejected
        Fulfilled,   // 4 — Goods/services delivered
        Completed,   // 5 — Closed / paid
        Cancelled    // 6 — Cancelled
    }

    // --- Structs ---
    struct PurchaseOrderData {
        uint256 id;
        address requester;      // Employee who requested
        address supplier;       // Supplier address
        uint256 totalAmount;    // Expected total in wei
        address paymentToken;   // ERC-20 for payment
        POStatus status;
        uint256 createdAt;
        uint256 updatedAt;
        uint256 deliveryDate;   // Expected delivery date
        string description;
        string ipfsHash;        // Supporting documents
    }

    struct POLineItem {
        string description;
        uint256 quantity;
        uint256 unitPrice;
        uint256 totalPrice;
    }

    struct Approval {
        address approver;
        bool approved;
        uint256 timestamp;
        string comments;
    }

    // --- State ---
    uint256 public nextPOId = 1;
    uint256 public requiredApprovals;  // How many approvals needed

    mapping(uint256 => PurchaseOrderData) public purchaseOrders;
    mapping(uint256 => POLineItem[]) public lineItems;
    mapping(uint256 => Approval[]) public approvals;
    mapping(uint256 => mapping(address => bool)) public hasApproved;
    mapping(address => uint256[]) public requesterPOs;
    mapping(address => uint256[]) public supplierPOs;

    // --- Events ---
    event POCreated(
        uint256 indexed poId,
        address indexed requester,
        address indexed supplier,
        uint256 totalAmount
    );
    event POSubmitted(uint256 indexed poId);
    event POApproval(uint256 indexed poId, address indexed approver, bool approved);
    event POApproved(uint256 indexed poId);
    event PORejected(uint256 indexed poId, string reason);
    event POFulfilled(uint256 indexed poId, uint256 timestamp);
    event POCompleted(uint256 indexed poId, uint256 timestamp);
    event POCancelled(uint256 indexed poId);

    // --- Errors ---
    error PODoesNotExist(uint256 poId);
    error InvalidStatusTransition(POStatus from, POStatus to);
    error NotAuthorized();
    error AlreadyApproved(address approver);
    error InsufficientApprovals(uint256 required, uint256 current);
    error NoLineItems();

    constructor(address admin, uint256 _requiredApprovals) ERPAccessControl(admin) {
        requiredApprovals = _requiredApprovals;
    }

    /// @notice Create a new purchase order
    /// @param supplier Supplier address
    /// @param totalAmount Expected total amount
    /// @param paymentToken ERC-20 token for payment
    /// @param deliveryDate Expected delivery timestamp
    /// @param description PO description
    /// @param ipfsHash IPFS CID for supporting documents
    /// @return poId The new PO ID
    function createPO(
        address supplier,
        uint256 totalAmount,
        address paymentToken,
        uint256 deliveryDate,
        string calldata description,
        string calldata ipfsHash
    ) external onlyRole(WAREHOUSE_ROLE) returns (uint256 poId) {
        poId = nextPOId++;
        purchaseOrders[poId] = PurchaseOrderData({
            id: poId,
            requester: msg.sender,
            supplier: supplier,
            totalAmount: totalAmount,
            paymentToken: paymentToken,
            status: POStatus.Draft,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            deliveryDate: deliveryDate,
            description: description,
            ipfsHash: ipfsHash
        });

        requesterPOs[msg.sender].push(poId);
        supplierPOs[supplier].push(poId);

        emit POCreated(poId, msg.sender, supplier, totalAmount);
    }

    /// @notice Add a line item to a purchase order
    function addLineItem(
        uint256 poId,
        string calldata description,
        uint256 quantity,
        uint256 unitPrice
    ) external {
        PurchaseOrderData storage po = purchaseOrders[poId];
        if (po.id == 0) revert PODoesNotExist(poId);
        if (msg.sender != po.requester && !hasRole(ADMIN_ROLE, msg.sender)) revert NotAuthorized();
        if (po.status != POStatus.Draft) revert InvalidStatusTransition(po.status, POStatus.Draft);

        uint256 totalPrice = quantity * unitPrice;
        lineItems[poId].push(POLineItem({
            description: description,
            quantity: quantity,
            unitPrice: unitPrice,
            totalPrice: totalPrice
        }));
    }

    /// @notice Submit PO for approval
    function submitPO(uint256 poId) external {
        PurchaseOrderData storage po = purchaseOrders[poId];
        if (po.id == 0) revert PODoesNotExist(poId);
        if (msg.sender != po.requester && !hasRole(ADMIN_ROLE, msg.sender)) revert NotAuthorized();
        if (po.status != POStatus.Draft) revert InvalidStatusTransition(po.status, POStatus.Submitted);
        if (lineItems[poId].length == 0) revert NoLineItems();

        po.status = POStatus.Submitted;
        po.updatedAt = block.timestamp;

        emit POSubmitted(poId);
    }

    /// @notice Approve or reject a submitted PO
    /// @param poId The PO ID
    /// @param approved Whether to approve or reject
    /// @param comments Approval/rejection comments
    function approvePO(uint256 poId, bool approved, string calldata comments) external onlyRole(APPROVER_ROLE) {
        PurchaseOrderData storage po = purchaseOrders[poId];
        if (po.id == 0) revert PODoesNotExist(poId);
        if (po.status != POStatus.Submitted) revert InvalidStatusTransition(po.status, po.status);
        if (hasApproved[poId][msg.sender]) revert AlreadyApproved(msg.sender);

        hasApproved[poId][msg.sender] = true;
        approvals[poId].push(Approval({
            approver: msg.sender,
            approved: approved,
            timestamp: block.timestamp,
            comments: comments
        }));

        emit POApproval(poId, msg.sender, approved);

        if (!approved) {
            po.status = POStatus.Rejected;
            po.updatedAt = block.timestamp;
            emit PORejected(poId, comments);
            return;
        }

        // Count approvals
        uint256 approvalCount = 0;
        for (uint256 i = 0; i < approvals[poId].length; i++) {
            if (approvals[poId][i].approved) approvalCount++;
        }

        if (approvalCount >= requiredApprovals) {
            po.status = POStatus.Approved;
            po.updatedAt = block.timestamp;
            emit POApproved(poId);
        }
    }

    /// @notice Mark a PO as fulfilled (goods received)
    function fulfillPO(uint256 poId) external {
        PurchaseOrderData storage po = purchaseOrders[poId];
        if (po.id == 0) revert PODoesNotExist(poId);
        if (!hasRole(WAREHOUSE_ROLE, msg.sender) && !hasRole(ADMIN_ROLE, msg.sender)) revert NotAuthorized();
        if (po.status != POStatus.Approved) revert InvalidStatusTransition(po.status, POStatus.Fulfilled);

        po.status = POStatus.Fulfilled;
        po.updatedAt = block.timestamp;

        emit POFulfilled(poId, block.timestamp);
    }

    /// @notice Complete a PO (after payment)
    function completePO(uint256 poId) external {
        PurchaseOrderData storage po = purchaseOrders[poId];
        if (po.id == 0) revert PODoesNotExist(poId);
        if (!hasRole(ACCOUNTANT_ROLE, msg.sender) && !hasRole(ADMIN_ROLE, msg.sender)) revert NotAuthorized();
        if (po.status != POStatus.Fulfilled) revert InvalidStatusTransition(po.status, POStatus.Completed);

        po.status = POStatus.Completed;
        po.updatedAt = block.timestamp;

        emit POCompleted(poId, block.timestamp);
    }

    /// @notice Cancel a draft or submitted PO
    function cancelPO(uint256 poId) external {
        PurchaseOrderData storage po = purchaseOrders[poId];
        if (po.id == 0) revert PODoesNotExist(poId);
        if (msg.sender != po.requester && !hasRole(ADMIN_ROLE, msg.sender)) revert NotAuthorized();
        if (po.status != POStatus.Draft && po.status != POStatus.Submitted) {
            revert InvalidStatusTransition(po.status, POStatus.Cancelled);
        }

        po.status = POStatus.Cancelled;
        po.updatedAt = block.timestamp;

        emit POCancelled(poId);
    }

    /// @notice Get line items for a PO
    function getLineItems(uint256 poId) external view returns (POLineItem[] memory) {
        return lineItems[poId];
    }

    /// @notice Get approvals for a PO
    function getApprovals(uint256 poId) external view returns (Approval[] memory) {
        return approvals[poId];
    }

    /// @notice Get POs for a requester
    function getRequesterPOs(address requester) external view returns (uint256[] memory) {
        return requesterPOs[requester];
    }

    /// @notice Get POs for a supplier
    function getSupplierPOs(address supplier) external view returns (uint256[] memory) {
        return supplierPOs[supplier];
    }

    /// @notice Get total PO count
    function poCount() external view returns (uint256) {
        return nextPOId - 1;
    }

    /// @notice Get PO details
    function getPO(uint256 poId) external view returns (PurchaseOrderData memory) {
        if (purchaseOrders[poId].id == 0) revert PODoesNotExist(poId);
        return purchaseOrders[poId];
    }
}
