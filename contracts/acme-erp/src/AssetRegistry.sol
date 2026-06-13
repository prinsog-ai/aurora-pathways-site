// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERPAccessControl} from "./ERPAccessControl.sol";

/// @title AssetRegistry
/// @notice On-chain company asset registry for Acme Cloud ERP
/// @dev Track physical and digital assets, maintenance schedules, depreciation
contract AssetRegistry is ERPAccessControl {
    // --- Enums ---
    enum AssetStatus {
        Active,       // 0 — In use
        Maintenance,  // 1 — Under maintenance
        Retired,      // 2 — No longer in use
        Disposed      // 3 — Disposed / written off
    }

    enum AssetCategory {
        Equipment,    // 0 — Machinery, tools
        Vehicle,      // 1 — Company vehicles
        IT,           // 2 — Computers, servers
        Furniture,    // 3 — Office furniture
        Property,     // 4 — Real estate
        Other         // 5 — Misc
    }

    // --- Structs ---
    struct Asset {
        uint256 id;
        string name;
        string description;
        AssetCategory category;
        AssetStatus status;
        address assignedTo;     // Employee/department
        uint256 purchasePrice;  // Original cost in wei
        uint256 purchaseDate;
        uint256 lastMaintenance;
        uint256 nextMaintenance;
        string serialNumber;
        string location;
        string ipfsHash;        // Documentation/receipts
    }

    struct MaintenanceRecord {
        uint256 timestamp;
        address performedBy;
        string description;
        uint256 cost;
    }

    // --- State ---
    uint256 public nextAssetId = 1;
    uint256 public depreciationRateBps;  // Basis points (e.g., 2000 = 20% per year)

    mapping(uint256 => Asset) public assets;
    mapping(uint256 => MaintenanceRecord[]) public maintenanceRecords;
    mapping(address => uint256[]) public assignedAssets;
    mapping(AssetCategory => uint256) public categoryCount;

    // --- Events ---
    event AssetRegistered(
        uint256 indexed assetId,
        string name,
        AssetCategory category,
        uint256 purchasePrice
    );
    event AssetStatusChanged(uint256 indexed assetId, AssetStatus oldStatus, AssetStatus newStatus);
    event AssetAssigned(uint256 indexed assetId, address indexed assignedTo);
    event MaintenanceRecorded(uint256 indexed assetId, address indexed performedBy, uint256 cost);
    event AssetDisposed(uint256 indexed assetId, uint256 timestamp);

    // --- Errors ---
    error AssetDoesNotExist(uint256 assetId);
    error InvalidStatusTransition(AssetStatus from, AssetStatus to);
    error NotAuthorized();

    constructor(address admin, uint256 _depreciationRateBps) ERPAccessControl(admin) {
        depreciationRateBps = _depreciationRateBps;
    }

    /// @notice Register a new asset
    function registerAsset(
        string calldata name,
        string calldata description,
        AssetCategory category,
        uint256 purchasePrice,
        uint256 purchaseDate,
        string calldata serialNumber,
        string calldata location,
        string calldata ipfsHash
    ) external onlyRole(WAREHOUSE_ROLE) returns (uint256 assetId) {
        assetId = nextAssetId++;
        assets[assetId] = Asset({
            id: assetId,
            name: name,
            description: description,
            category: category,
            status: AssetStatus.Active,
            assignedTo: address(0),
            purchasePrice: purchasePrice,
            purchaseDate: purchaseDate,
            lastMaintenance: 0,
            nextMaintenance: 0,
            serialNumber: serialNumber,
            location: location,
            ipfsHash: ipfsHash
        });

        categoryCount[category]++;

        emit AssetRegistered(assetId, name, category, purchasePrice);
    }

    /// @notice Update asset status
    function updateStatus(uint256 assetId, AssetStatus newStatus) external onlyRole(WAREHOUSE_ROLE) {
        Asset storage asset = assets[assetId];
        if (asset.id == 0) revert AssetDoesNotExist(assetId);
        if (!_isValidTransition(asset.status, newStatus)) {
            revert InvalidStatusTransition(asset.status, newStatus);
        }

        AssetStatus oldStatus = asset.status;
        asset.status = newStatus;

        emit AssetStatusChanged(assetId, oldStatus, newStatus);

        if (newStatus == AssetStatus.Disposed) {
            emit AssetDisposed(assetId, block.timestamp);
        }
    }

    /// @notice Assign an asset to an employee/department
    function assignAsset(uint256 assetId, address assignee) external onlyRole(WAREHOUSE_ROLE) {
        Asset storage asset = assets[assetId];
        if (asset.id == 0) revert AssetDoesNotExist(assetId);

        // Remove from previous assignee if any
        if (asset.assignedTo != address(0)) {
            _removeFromAssigned(asset.assignedTo, assetId);
        }

        asset.assignedTo = assignee;
        assignedAssets[assignee].push(assetId);

        emit AssetAssigned(assetId, assignee);
    }

    /// @notice Record maintenance on an asset
    function recordMaintenance(
        uint256 assetId,
        string calldata description,
        uint256 cost,
        uint256 nextMaintenanceDate
    ) external onlyRole(WAREHOUSE_ROLE) {
        Asset storage asset = assets[assetId];
        if (asset.id == 0) revert AssetDoesNotExist(assetId);

        maintenanceRecords[assetId].push(MaintenanceRecord({
            timestamp: block.timestamp,
            performedBy: msg.sender,
            description: description,
            cost: cost
        }));

        asset.lastMaintenance = block.timestamp;
        asset.nextMaintenance = nextMaintenanceDate;

        emit MaintenanceRecorded(assetId, msg.sender, cost);
    }

    /// @notice Calculate current depreciated value
    /// @param assetId The asset ID
    /// @return currentValue Current estimated value
    function getDepreciatedValue(uint256 assetId) external view returns (uint256 currentValue) {
        Asset storage asset = assets[assetId];
        if (asset.id == 0) revert AssetDoesNotExist(assetId);

        uint256 ageInYears = (block.timestamp - asset.purchaseDate) / 365 days;
        uint256 depreciation = (asset.purchasePrice * depreciationRateBps * ageInYears) / 10000;

        if (depreciation >= asset.purchasePrice) return 0;
        return asset.purchasePrice - depreciation;
    }

    /// @notice Get maintenance history for an asset
    function getMaintenanceHistory(uint256 assetId) external view returns (MaintenanceRecord[] memory) {
        return maintenanceRecords[assetId];
    }

    /// @notice Get assets assigned to an address
    function getAssignedAssets(address assignee) external view returns (uint256[] memory) {
        return assignedAssets[assignee];
    }

    /// @notice Get asset count
    function assetCount() external view returns (uint256) {
        return nextAssetId - 1;
    }

    /// @notice Get asset details
    function getAsset(uint256 assetId) external view returns (Asset memory) {
        if (assets[assetId].id == 0) revert AssetDoesNotExist(assetId);
        return assets[assetId];
    }

    // --- Internal ---

    function _isValidTransition(AssetStatus from, AssetStatus to) internal pure returns (bool) {
        if (from == AssetStatus.Disposed) return false; // Can't change from disposed
        if (to == AssetStatus.Disposed) return true;     // Can dispose from any non-disposed
        if (from == AssetStatus.Retired && to != AssetStatus.Disposed) return false;
        return true;
    }

    function _removeFromAssigned(address assignee, uint256 assetId) internal {
        uint256[] storage assigned = assignedAssets[assignee];
        for (uint256 i = 0; i < assigned.length; i++) {
            if (assigned[i] == assetId) {
                assigned[i] = assigned[assigned.length - 1];
                assigned.pop();
                break;
            }
        }
    }
}
