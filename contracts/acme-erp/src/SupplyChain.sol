// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERPAccessControl} from "./ERPAccessControl.sol";

/// @title SupplyChain
/// @notice On-chain supply chain tracking for Acme Cloud ERP
/// @dev Tracks items through lifecycle stages with role-based permissions
contract SupplyChain is ERPAccessControl {
    // --- Enums ---
    enum ItemStage {
        Created,        // 0 — Item registered
        Manufactured,   // 1 — Manufacturing complete
        InTransit,      // 2 — Shipped / in transit
        Received,       // 3 — Received at destination
        QualityChecked, // 4 — Quality inspection passed
        Delivered,      // 5 — Final delivery confirmed
        Disputed        // 6 — Issue flagged
    }

    // --- Structs ---
    struct Item {
        uint256 id;
        string name;
        string description;
        string sku;           // Stock Keeping Unit
        address supplier;
        ItemStage stage;
        uint256 createdAt;
        uint256 updatedAt;
        string location;      // Current physical location
        string notes;         // Free-form notes
    }

    struct StageHistory {
        ItemStage stage;
        uint256 timestamp;
        address updatedBy;
        string location;
        string notes;
    }

    // --- State ---
    uint256 public nextItemId = 1;
    mapping(uint256 => Item) public items;
    mapping(uint256 => StageHistory[]) public stageHistory;
    mapping(address => uint256[]) public supplierItems;

    // --- Events ---
    event ItemCreated(
        uint256 indexed itemId,
        string name,
        string sku,
        address indexed supplier
    );
    event StageUpdated(
        uint256 indexed itemId,
        ItemStage oldStage,
        ItemStage newStage,
        address indexed updatedBy,
        string location
    );

    // --- Errors ---
    error ItemDoesNotExist(uint256 itemId);
    error InvalidStageTransition(ItemStage from, ItemStage to);
    error NotAuthorized();

    constructor(address admin) ERPAccessControl(admin) {}

    /// @notice Register a new supply chain item
    /// @param name Item name
    /// @param description Item description
    /// @param sku Stock Keeping Unit code
    /// @param supplier Supplier address
    /// @return itemId The new item's ID
    function createItem(
        string calldata name,
        string calldata description,
        string calldata sku,
        address supplier
    ) external onlyRole(WAREHOUSE_ROLE) returns (uint256 itemId) {
        itemId = nextItemId++;
        items[itemId] = Item({
            id: itemId,
            name: name,
            description: description,
            sku: sku,
            supplier: supplier,
            stage: ItemStage.Created,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            location: "",
            notes: ""
        });

        supplierItems[supplier].push(itemId);

        stageHistory[itemId].push(StageHistory({
            stage: ItemStage.Created,
            timestamp: block.timestamp,
            updatedBy: msg.sender,
            location: "",
            notes: "Item registered"
        }));

        emit ItemCreated(itemId, name, sku, supplier);
    }

    /// @notice Advance an item to the next stage
    /// @param itemId The item ID
    /// @param newStage Target stage
    /// @param location Current location
    /// @param notes Additional notes
    function updateStage(
        uint256 itemId,
        ItemStage newStage,
        string calldata location,
        string calldata notes
    ) external {
        Item storage item = items[itemId];
        if (item.id == 0) revert ItemDoesNotExist(itemId);
        if (!_canUpdateStage(msg.sender, item, newStage)) revert NotAuthorized();
        if (!_isValidTransition(item.stage, newStage)) {
            revert InvalidStageTransition(item.stage, newStage);
        }

        ItemStage oldStage = item.stage;
        item.stage = newStage;
        item.updatedAt = block.timestamp;
        item.location = location;
        item.notes = notes;

        stageHistory[itemId].push(StageHistory({
            stage: newStage,
            timestamp: block.timestamp,
            updatedBy: msg.sender,
            location: location,
            notes: notes
        }));

        emit StageUpdated(itemId, oldStage, newStage, msg.sender, location);
    }

    /// @notice Get full stage history for an item
    function getStageHistory(uint256 itemId) external view returns (StageHistory[] memory) {
        if (items[itemId].id == 0) revert ItemDoesNotExist(itemId);
        return stageHistory[itemId];
    }

    /// @notice Get all items for a supplier
    function getSupplierItems(address supplier) external view returns (uint256[] memory) {
        return supplierItems[supplier];
    }

    /// @notice Get item count
    function itemCount() external view returns (uint256) {
        return nextItemId - 1;
    }

    /// @notice Get item details
    function getItem(uint256 itemId) external view returns (Item memory) {
        if (items[itemId].id == 0) revert ItemDoesNotExist(itemId);
        return items[itemId];
    }

    // --- Internal ---

    function _isValidTransition(ItemStage from, ItemStage to) internal pure returns (bool) {
        // Disputed can be set from any stage
        if (to == ItemStage.Disputed) return true;
        // Sequential forward transitions
        return uint8(to) == uint8(from) + 1;
    }

    function _canUpdateStage(address user, Item memory item, ItemStage newStage) internal view returns (bool) {
        if (hasRole(ADMIN_ROLE, user)) return true;
        if (hasRole(WAREHOUSE_ROLE, user)) return true;
        if (hasRole(ACCOUNTANT_ROLE, user) && newStage == ItemStage.Delivered) return true;
        if (hasRole(SUPPLIER_ROLE, user) && item.supplier == user) return true;
        return false;
    }
}
