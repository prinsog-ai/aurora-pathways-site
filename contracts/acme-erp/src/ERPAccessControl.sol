// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ERPAccessControl
/// @notice Role-based access control for the Acme Cloud ERP system
/// @dev Extends OpenZeppelin AccessControl with ERP-specific roles
contract ERPAccessControl is AccessControl {
    // --- Roles ---
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ACCOUNTANT_ROLE = keccak256("ACCOUNTANT_ROLE");
    bytes32 public constant WAREHOUSE_ROLE = keccak256("WAREHOUSE_ROLE");
    bytes32 public constant SUPPLIER_ROLE = keccak256("SUPPLIER_ROLE");
    bytes32 public constant APPROVER_ROLE = keccak256("APPROVER_ROLE");

    /// @notice Emitted when a supplier is registered
    event SupplierRegistered(address indexed supplier, string name);

    /// @notice Emitted when a supplier is deregistered
    event SupplierDeregistered(address indexed supplier);

    /// @notice Mapping of registered suppliers
    mapping(address => bool) public isSupplier;

    /// @notice Mapping of supplier names
    mapping(address => string) public supplierName;

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    /// @notice Register a supplier address
    /// @param supplier The supplier's address
    /// @param name The supplier's name
    function registerSupplier(address supplier, string calldata name) external onlyRole(ADMIN_ROLE) {
        isSupplier[supplier] = true;
        supplierName[supplier] = name;
        _grantRole(SUPPLIER_ROLE, supplier);
        emit SupplierRegistered(supplier, name);
    }

    /// @notice Deregister a supplier
    /// @param supplier The supplier's address
    function deregisterSupplier(address supplier) external onlyRole(ADMIN_ROLE) {
        isSupplier[supplier] = false;
        supplierName[supplier] = "";
        _revokeRole(SUPPLIER_ROLE, supplier);
        emit SupplierDeregistered(supplier);
    }

    /// @notice Grant the ACCOUNTANT_ROLE to an address
    function addAccountant(address accountant) external onlyRole(ADMIN_ROLE) {
        _grantRole(ACCOUNTANT_ROLE, accountant);
    }

    /// @notice Grant the WAREHOUSE_ROLE to an address
    function addWarehouseManager(address manager) external onlyRole(ADMIN_ROLE) {
        _grantRole(WAREHOUSE_ROLE, manager);
    }

    /// @notice Grant the APPROVER_ROLE to an address
    function addApprover(address approver) external onlyRole(ADMIN_ROLE) {
        _grantRole(APPROVER_ROLE, approver);
    }
}
