// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ServiceLevelAgreement
/// @notice On-chain SLA tracking for WES work orders — response times, completion deadlines, penalty/bonus logic
contract ServiceLevelAgreement is Ownable {

    struct SLATemplate {
        uint256 id;
        string name;                  // e.g., "Emergency Electrical SLA"
        string serviceType;
        uint256 maxResponseTime;      // seconds from assignment to start
        uint256 maxCompletionTime;    // seconds from assignment to completion
        uint256 penaltyRate;          // basis points per hour late (e.g., 100 = 1%/hr)
        uint256 bonusRate;            // basis points bonus for early completion
        uint256 penaltyCap;           // max penalty as bps of payment (e.g., 5000 = 50%)
        bool isActive;
    }

    struct SLAInstance {
        uint256 templateId;
        uint256 workOrderId;
        address technician;
        uint256 assignedAt;
        uint256 responseDeadline;
        uint256 completionDeadline;
        uint256 actualStartTime;
        uint256 actualCompletionTime;
        bool responseMet;
        bool completionMet;
        int256 adjustment;            // positive = bonus, negative = penalty (in token units)
    }

    // Storage
    mapping(uint256 => SLATemplate) public templates;
    uint256 public nextTemplateId;
    mapping(uint256 => SLAInstance) public instances;  // workOrderId => instance

    // Events
    event SLATemplateCreated(uint256 indexed id, string name, string serviceType);
    event SLAInstanceCreated(uint256 indexed workOrderId, uint256 indexed templateId, uint256 responseDeadline, uint256 completionDeadline);
    event ResponseRecorded(uint256 indexed workOrderId, uint256 timestamp, bool onTime);
    event CompletionRecorded(uint256 indexed workOrderId, uint256 timestamp, bool onTime, int256 adjustment);
    event TemplateDeactivated(uint256 indexed id);

    // Errors
    error TemplateNotFound();
    error TemplateNotActive();
    error NoInstance();
    error AlreadyRecorded();

    constructor() Ownable(msg.sender) {}

    /// @notice Create an SLA template
    function createTemplate(
        string calldata _name,
        string calldata _serviceType,
        uint256 _maxResponseTime,
        uint256 _maxCompletionTime,
        uint256 _penaltyRate,
        uint256 _bonusRate,
        uint256 _penaltyCap
    ) external onlyOwner returns (uint256) {
        uint256 id = nextTemplateId++;

        templates[id] = SLATemplate({
            id: id,
            name: _name,
            serviceType: _serviceType,
            maxResponseTime: _maxResponseTime,
            maxCompletionTime: _maxCompletionTime,
            penaltyRate: _penaltyRate,
            bonusRate: _bonusRate,
            penaltyCap: _penaltyCap,
            isActive: true
        });

        emit SLATemplateCreated(id, _name, _serviceType);
        return id;
    }

    /// @notice Attach an SLA to a work order (called when technician assigned)
    function attachSLA(uint256 _templateId, uint256 _workOrderId, address _technician, uint256 _assignedAt) external onlyOwner {
        SLATemplate storage tmpl = templates[_templateId];
        if (tmpl.id == 0 && _templateId != 0) revert TemplateNotFound();
        if (!tmpl.isActive) revert TemplateNotActive();

        instances[_workOrderId] = SLAInstance({
            templateId: _templateId,
            workOrderId: _workOrderId,
            technician: _technician,
            assignedAt: _assignedAt,
            responseDeadline: _assignedAt + tmpl.maxResponseTime,
            completionDeadline: _assignedAt + tmpl.maxCompletionTime,
            actualStartTime: 0,
            actualCompletionTime: 0,
            responseMet: false,
            completionMet: false,
            adjustment: 0
        });

        emit SLAInstanceCreated(_workOrderId, _templateId,
            _assignedAt + tmpl.maxResponseTime,
            _assignedAt + tmpl.maxCompletionTime);
    }

    /// @notice Record technician response (on-site check-in)
    function recordResponse(uint256 _workOrderId, uint256 _timestamp) external onlyOwner {
        SLAInstance storage inst = instances[_workOrderId];
        if (inst.assignedAt == 0) revert NoInstance();
        if (inst.actualStartTime != 0) revert AlreadyRecorded();

        inst.actualStartTime = _timestamp;
        inst.responseMet = _timestamp <= inst.responseDeadline;

        emit ResponseRecorded(_workOrderId, _timestamp, inst.responseMet);
    }

    /// @notice Record work completion and calculate SLA adjustment
    function recordCompletion(uint256 _workOrderId, uint256 _timestamp, uint256 _paymentAmount) external onlyOwner {
        SLAInstance storage inst = instances[_workOrderId];
        if (inst.assignedAt == 0) revert NoInstance();

        inst.actualCompletionTime = _timestamp;
        inst.completionMet = _timestamp <= inst.completionDeadline;

        // Calculate adjustment
        int256 adjustment = 0;
        SLATemplate storage tmpl = templates[inst.templateId];

        if (!inst.completionMet) {
            // Penalty for late completion
            uint256 hoursLate = (_timestamp - inst.completionDeadline) / 1 hours;
            if (hoursLate == 0) hoursLate = 1; // minimum 1 hour penalty
            uint256 penaltyBps = tmpl.penaltyRate * hoursLate;
            if (penaltyBps > tmpl.penaltyCap) penaltyBps = tmpl.penaltyCap;
            adjustment = -int256((_paymentAmount * penaltyBps) / 10000);
        } else if (_timestamp < inst.completionDeadline) {
            // Bonus for early completion
            uint256 hoursEarly = (inst.completionDeadline - _timestamp) / 1 hours;
            uint256 bonusBps = tmpl.bonusRate * hoursEarly;
            // Cap bonus at 20%
            if (bonusBps > 2000) bonusBps = 2000;
            adjustment = int256((_paymentAmount * bonusBps) / 10000);
        }

        inst.adjustment = adjustment;
        emit CompletionRecorded(_workOrderId, _timestamp, inst.completionMet, adjustment);
    }

    /// @notice Deactivate an SLA template
    function deactivateTemplate(uint256 _templateId) external onlyOwner {
        templates[_templateId].isActive = false;
        emit TemplateDeactivated(_templateId);
    }

    // --- View Functions ---

    function getTemplate(uint256 _templateId) external view returns (SLATemplate memory) {
        return templates[_templateId];
    }

    function getInstance(uint256 _workOrderId) external view returns (SLAInstance memory) {
        return instances[_workOrderId];
    }

    function getTemplateCount() external view returns (uint256) {
        return nextTemplateId;
    }
}
