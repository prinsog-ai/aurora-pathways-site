// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TechnicianRegistry} from "./TechnicianRegistry.sol";

/// @title WorkOrderManager
/// @notice Core WES contract: manages field service work orders with escrow payments
/// @dev Clients create work orders → admin assigns certified technician → work completed → payment released
contract WorkOrderManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Priority { Low, Medium, High, Emergency }
    enum Status {
        Pending,
        Assigned,
        InProgress,
        Completed,
        Verified,
        Disputed,
        Cancelled
    }

    /// @notice Core order data (payment & state)
    struct OrderCore {
        address client;
        address technician;
        IERC20 paymentToken;
        uint256 paymentAmount;
        Priority priority;
        Status status;
        uint256 createdAt;
        uint256 assignedAt;
        uint256 completedAt;
        uint256 verifiedAt;
    }

    /// @notice Order details (descriptive fields, stored separately to avoid stack-too-deep)
    struct OrderDetails {
        string serviceType;
        string location;
        string description;
        string metadataHash;
        string completionNotes;
        string completionHash;
    }

    // Storage
    mapping(uint256 => OrderCore) public orderCore;
    mapping(uint256 => OrderDetails) public orderDetails;
    uint256 public orderCount;

    TechnicianRegistry public registry;
    IERC20 public defaultPaymentToken;
    address public treasury;

    uint256 public platformFee = 500;       // 5% platform fee in basis points
    uint256 public constant MAX_FEE = 1500; // 15% max

    // Events
    event WorkOrderCreated(uint256 indexed orderId, address indexed client, string serviceType, Priority priority, uint256 paymentAmount);
    event WorkOrderAssigned(uint256 indexed orderId, address indexed technician);
    event WorkOrderStarted(uint256 indexed orderId, address indexed technician);
    event WorkOrderCompleted(uint256 indexed orderId, address indexed technician, string completionNotes);
    event WorkOrderVerified(uint256 indexed orderId, address indexed verifier);
    event WorkOrderCancelled(uint256 indexed orderId);
    event WorkOrderDisputed(uint256 indexed orderId, address indexed disputer, string reason);
    event DisputeResolved(uint256 indexed orderId, bool payTechnician);
    event PaymentReleased(uint256 indexed orderId, address indexed technician, uint256 amount, uint256 fee);
    event PlatformFeeUpdated(uint256 newFee);
    event TreasuryUpdated(address newTreasury);

    // Errors
    error InvalidStatus(Status current, Status required);
    error NotClient();
    error NotTechnician();
    error NotAuthorized();
    error NotCertified();
    error NotActive();
    error ZeroAmount();
    error EmptyDescription();

    constructor(address _registry, address _paymentToken, address _treasury) Ownable(msg.sender) {
        registry = TechnicianRegistry(_registry);
        defaultPaymentToken = IERC20(_paymentToken);
        treasury = _treasury;
    }

    // --- Admin Functions ---

    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= MAX_FEE, "Fee exceeds maximum");
        platformFee = _fee;
        emit PlatformFeeUpdated(_fee);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    // --- Client Functions ---

    /// @notice Create a new work order with escrow payment
    function createWorkOrder(
        string calldata _serviceType,
        string calldata _location,
        string calldata _description,
        string calldata _metadataHash,
        Priority _priority,
        uint256 _paymentAmount
    ) external nonReentrant returns (uint256) {
        require(_paymentAmount > 0, "Zero amount");
        require(bytes(_description).length > 0, "Empty description");

        uint256 orderId = orderCount;
        orderCount++;

        orderCore[orderId] = OrderCore({
            client: msg.sender,
            technician: address(0),
            paymentToken: defaultPaymentToken,
            paymentAmount: _paymentAmount,
            priority: _priority,
            status: Status.Pending,
            createdAt: block.timestamp,
            assignedAt: 0,
            completedAt: 0,
            verifiedAt: 0
        });

        orderDetails[orderId] = OrderDetails({
            serviceType: _serviceType,
            location: _location,
            description: _description,
            metadataHash: _metadataHash,
            completionNotes: "",
            completionHash: ""
        });

        // Escrow payment
        defaultPaymentToken.safeTransferFrom(msg.sender, address(this), _paymentAmount);

        emit WorkOrderCreated(orderId, msg.sender, _serviceType, _priority, _paymentAmount);
        return orderId;
    }

    /// @notice Client verifies completed work → triggers payment release
    function verifyWorkOrder(uint256 _orderId) external nonReentrant {
        OrderCore storage core = orderCore[_orderId];
        if (msg.sender != core.client) revert NotClient();
        if (core.status != Status.Completed) revert InvalidStatus(core.status, Status.Completed);

        core.status = Status.Verified;
        core.verifiedAt = block.timestamp;

        _releasePayment(_orderId);

        emit WorkOrderVerified(_orderId, msg.sender);
    }

    /// @notice Cancel a pending work order (only before assignment)
    function cancelWorkOrder(uint256 _orderId) external nonReentrant {
        OrderCore storage core = orderCore[_orderId];
        if (msg.sender != core.client) revert NotClient();
        if (core.status != Status.Pending) revert InvalidStatus(core.status, Status.Pending);

        core.status = Status.Cancelled;
        core.paymentToken.safeTransfer(core.client, core.paymentAmount);

        emit WorkOrderCancelled(_orderId);
    }

    /// @notice Raise a dispute on a completed work order
    function disputeWorkOrder(uint256 _orderId, string calldata _reason) external {
        OrderCore storage core = orderCore[_orderId];
        if (msg.sender != core.client && msg.sender != core.technician) revert NotAuthorized();
        if (core.status != Status.Completed) revert InvalidStatus(core.status, Status.Completed);

        core.status = Status.Disputed;
        emit WorkOrderDisputed(_orderId, msg.sender, _reason);
    }

    // --- Technician Functions ---

    /// @notice Technician starts work (check-in)
    function startWork(uint256 _orderId) external {
        OrderCore storage core = orderCore[_orderId];
        if (msg.sender != core.technician) revert NotTechnician();
        if (core.status != Status.Assigned) revert InvalidStatus(core.status, Status.Assigned);

        core.status = Status.InProgress;
        emit WorkOrderStarted(_orderId, msg.sender);
    }

    /// @notice Technician marks work as completed with notes and evidence
    function completeWork(uint256 _orderId, string calldata _notes, string calldata _completionHash) external {
        OrderCore storage core = orderCore[_orderId];
        if (msg.sender != core.technician) revert NotTechnician();
        if (core.status != Status.InProgress) revert InvalidStatus(core.status, Status.InProgress);

        core.status = Status.Completed;
        core.completedAt = block.timestamp;

        orderDetails[_orderId].completionNotes = _notes;
        orderDetails[_orderId].completionHash = _completionHash;

        registry.recordJobCompletion(core.technician);

        emit WorkOrderCompleted(_orderId, core.technician, _notes);
    }

    // --- Admin Functions ---

    /// @notice Assign a certified technician to a pending work order
    function assignTechnician(uint256 _orderId, address _technician) external onlyOwner {
        OrderCore storage core = orderCore[_orderId];
        if (core.status != Status.Pending) revert InvalidStatus(core.status, Status.Pending);

        TechnicianRegistry.Technician memory tech = registry.getTechnician(_technician);
        if (!tech.isActive) revert NotActive();
        if (!tech.isCertified) revert NotCertified();

        core.technician = _technician;
        core.status = Status.Assigned;
        core.assignedAt = block.timestamp;

        registry.recordJobAssignment(_technician);

        emit WorkOrderAssigned(_orderId, _technician);
    }

    /// @notice Resolve a dispute (admin decision)
    function resolveDispute(uint256 _orderId, bool _payTechnician, string calldata /*_reason*/) external onlyOwner nonReentrant {
        OrderCore storage core = orderCore[_orderId];
        require(core.status == Status.Disputed, "Not disputed");

        if (_payTechnician) {
            core.status = Status.Verified;
            core.verifiedAt = block.timestamp;
            _releasePayment(_orderId);
        } else {
            core.status = Status.Cancelled;
            core.paymentToken.safeTransfer(core.client, core.paymentAmount);
        }

        emit DisputeResolved(_orderId, _payTechnician);
    }

    /// @notice Force-reassign a work order to a different technician
    function reassignTechnician(uint256 _orderId, address _newTechnician) external onlyOwner {
        OrderCore storage core = orderCore[_orderId];
        require(
            core.status == Status.Assigned || core.status == Status.InProgress,
            "Cannot reassign"
        );

        TechnicianRegistry.Technician memory tech = registry.getTechnician(_newTechnician);
        if (!tech.isActive) revert NotActive();
        if (!tech.isCertified) revert NotCertified();

        core.technician = _newTechnician;
        core.assignedAt = block.timestamp;
        core.status = Status.Assigned;

        registry.recordJobAssignment(_newTechnician);

        emit WorkOrderAssigned(_orderId, _newTechnician);
    }

    // --- Internal ---

    function _releasePayment(uint256 _orderId) internal {
        OrderCore storage core = orderCore[_orderId];

        uint256 fee = (core.paymentAmount * platformFee) / 10000;
        uint256 payout = core.paymentAmount - fee;

        core.paymentToken.safeTransfer(core.technician, payout);
        if (fee > 0) {
            core.paymentToken.safeTransfer(treasury, fee);
        }

        emit PaymentReleased(_orderId, core.technician, payout, fee);
    }

    // --- View Functions ---

    /// @notice Get core order data
    function getOrderCore(uint256 _orderId) external view returns (OrderCore memory) {
        return orderCore[_orderId];
    }

    /// @notice Get order details
    function getOrderDetails(uint256 _orderId) external view returns (OrderDetails memory) {
        return orderDetails[_orderId];
    }

    /// @notice Backward-compat alias used by tests
    function getWorkOrder(uint256 _orderId) external view returns (OrderCore memory) {
        return orderCore[_orderId];
    }

    /// @notice Backward-compat alias
    function workOrderCount() external view returns (uint256) {
        return orderCount;
    }
}
