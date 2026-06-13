// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title EquipmentManager
/// @notice Tracks WES field equipment: inventory, assignment to technicians, maintenance schedules
contract EquipmentManager is Ownable {

    enum EquipmentStatus { Available, Assigned, Maintenance, Retired }
    enum Condition { Excellent, Good, Fair, Poor }

    struct Equipment {
        uint256 id;
        string name;            // e.g., "Fluke Multimeter 87V"
        string serialNumber;
        string category;        // e.g., "Testing", "Safety", "Power Tools"
        EquipmentStatus status;
        Condition condition;
        address assignedTo;     // technician address (0 if unassigned)
        uint256 purchaseDate;
        uint256 lastMaintenance;
        uint256 nextMaintenance;
        uint256 value;          // asset value in USD (8 decimals)
        string notes;
    }

    struct MaintenanceRecord {
        uint256 equipmentId;
        uint256 timestamp;
        Condition conditionBefore;
        Condition conditionAfter;
        string description;
        uint256 cost;
        address performedBy;
    }

    // Storage
    mapping(uint256 => Equipment) public equipment;
    uint256 public nextEquipmentId;
    mapping(uint256 => MaintenanceRecord[]) public maintenanceHistory;
    mapping(address => uint256[]) public technicianEquipment; // tech => equipment IDs
    mapping(string => uint256[]) public equipmentByCategory;

    // Events
    event EquipmentAdded(uint256 indexed id, string name, string category);
    event EquipmentAssigned(uint256 indexed id, address indexed technician);
    event EquipmentReturned(uint256 indexed id, address indexed technician, Condition condition);
    event MaintenancePerformed(uint256 indexed equipmentId, Condition newCondition, string description);
    event EquipmentRetired(uint256 indexed id);
    event ConditionUpdated(uint256 indexed id, Condition oldCondition, Condition newCondition);

    // Errors
    error EquipmentNotFound();
    error NotAvailable();
    error NotAssigned();
    error AlreadyAssigned();

    constructor() Ownable(msg.sender) {}

    /// @notice Add new equipment to inventory
    function addEquipment(
        string calldata _name,
        string calldata _serialNumber,
        string calldata _category,
        uint256 _purchaseDate,
        uint256 _nextMaintenance,
        uint256 _value,
        string calldata _notes
    ) external onlyOwner returns (uint256) {
        uint256 id = nextEquipmentId++;

        equipment[id] = Equipment({
            id: id,
            name: _name,
            serialNumber: _serialNumber,
            category: _category,
            status: EquipmentStatus.Available,
            condition: Condition.Excellent,
            assignedTo: address(0),
            purchaseDate: _purchaseDate,
            lastMaintenance: _purchaseDate,
            nextMaintenance: _nextMaintenance,
            value: _value,
            notes: _notes
        });

        equipmentByCategory[_category].push(id);
        emit EquipmentAdded(id, _name, _category);
        return id;
    }

    /// @notice Assign equipment to a technician
    function assignEquipment(uint256 _equipmentId, address _technician) external onlyOwner {
        Equipment storage eq = equipment[_equipmentId];
        if (eq.id == 0 && _equipmentId != 0) revert EquipmentNotFound();
        if (eq.status != EquipmentStatus.Available) revert NotAvailable();

        eq.status = EquipmentStatus.Assigned;
        eq.assignedTo = _technician;
        technicianEquipment[_technician].push(_equipmentId);

        emit EquipmentAssigned(_equipmentId, _technician);
    }

    /// @notice Return equipment from a technician
    function returnEquipment(uint256 _equipmentId, Condition _condition) external onlyOwner {
        Equipment storage eq = equipment[_equipmentId];
        if (eq.status != EquipmentStatus.Assigned) revert NotAssigned();

        address tech = eq.assignedTo;
        eq.status = EquipmentStatus.Available;
        eq.assignedTo = address(0);

        Condition oldCondition = eq.condition;
        eq.condition = _condition;

        if (_condition != oldCondition) {
            emit ConditionUpdated(_equipmentId, oldCondition, _condition);
        }

        emit EquipmentReturned(_equipmentId, tech, _condition);
    }

    /// @notice Record maintenance performed on equipment
    function recordMaintenance(
        uint256 _equipmentId,
        Condition _newCondition,
        string calldata _description,
        uint256 _cost
    ) external onlyOwner {
        Equipment storage eq = equipment[_equipmentId];
        if (eq.id == 0 && _equipmentId != 0) revert EquipmentNotFound();

        Condition oldCondition = eq.condition;
        eq.condition = _newCondition;
        eq.lastMaintenance = block.timestamp;

        maintenanceHistory[_equipmentId].push(MaintenanceRecord({
            equipmentId: _equipmentId,
            timestamp: block.timestamp,
            conditionBefore: oldCondition,
            conditionAfter: _newCondition,
            description: _description,
            cost: _cost,
            performedBy: msg.sender
        }));

        emit MaintenancePerformed(_equipmentId, _newCondition, _description);
    }

    /// @notice Send equipment for maintenance
    function sendToMaintenance(uint256 _equipmentId) external onlyOwner {
        Equipment storage eq = equipment[_equipmentId];
        eq.status = EquipmentStatus.Maintenance;
    }

    /// @notice Return equipment from maintenance to available
    function returnFromMaintenance(uint256 _equipmentId) external onlyOwner {
        Equipment storage eq = equipment[_equipmentId];
        require(eq.status == EquipmentStatus.Maintenance, "Not in maintenance");
        eq.status = EquipmentStatus.Available;
    }

    /// @notice Retire equipment
    function retireEquipment(uint256 _equipmentId) external onlyOwner {
        Equipment storage eq = equipment[_equipmentId];
        eq.status = EquipmentStatus.Retired;
        eq.assignedTo = address(0);
        emit EquipmentRetired(_equipmentId);
    }

    // --- View Functions ---

    function getEquipment(uint256 _equipmentId) external view returns (Equipment memory) {
        return equipment[_equipmentId];
    }

    function getTechnicianEquipment(address _tech) external view returns (uint256[] memory) {
        return technicianEquipment[_tech];
    }

    function getMaintenanceHistory(uint256 _equipmentId) external view returns (MaintenanceRecord[] memory) {
        return maintenanceHistory[_equipmentId];
    }

    function getEquipmentByCategory(string calldata _category) external view returns (uint256[] memory) {
        return equipmentByCategory[_category];
    }

    function totalEquipment() external view returns (uint256) {
        return nextEquipmentId;
    }

    /// @notice Get count of equipment needing maintenance soon (within 7 days)
    function getMaintenanceDueCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < nextEquipmentId; i++) {
            if (equipment[i].status != EquipmentStatus.Retired &&
                equipment[i].nextMaintenance <= block.timestamp + 7 days) {
                count++;
            }
        }
        return count;
    }
}
