// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TechnicianRegistry} from "../src/TechnicianRegistry.sol";
import {WorkOrderManager} from "../src/WorkOrderManager.sol";
import {EquipmentManager} from "../src/EquipmentManager.sol";
import {ServiceLevelAgreement} from "../src/ServiceLevelAgreement.sol";

/// @dev Mock USDC for testing
contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

/// @title WESFieldOpsTest
/// @notice Comprehensive test suite for the WES Field Operations system
contract WESFieldOpsTest is Test {
    MockUSDC public usdc;
    TechnicianRegistry public registry;
    WorkOrderManager public workOrders;
    EquipmentManager public equipment;
    ServiceLevelAgreement public sla;

    address public admin = address(this);
    address public treasury = address(0xBEEF);
    address public client1 = address(0x1001);
    address public client2 = address(0x1002);
    address public tech1 = address(0x2001);
    address public tech2 = address(0x2002);
    address public tech3 = address(0x2003);

    uint256 constant ONE_USDC = 1e6;
    uint256 constant PAYMENT = 1000 * ONE_USDC;

    function setUp() public {
        usdc = new MockUSDC();
        registry = new TechnicianRegistry();
        workOrders = new WorkOrderManager(address(registry), address(usdc), treasury);
        equipment = new EquipmentManager();
        sla = new ServiceLevelAgreement();

        usdc.mint(client1, 100_000 * ONE_USDC);
        usdc.mint(client2, 100_000 * ONE_USDC);

        vm.startPrank(admin);
        registry.registerTechnician(tech1, "John Electrician", TechnicianRegistry.Specialization.Electrical);
        registry.registerTechnician(tech2, "Jane Plumber", TechnicianRegistry.Specialization.Plumbing);
        registry.registerTechnician(tech3, "Bob HVAC", TechnicianRegistry.Specialization.HVAC);
        registry.certifyTechnician(tech1, TechnicianRegistry.Tier.Silver);
        registry.certifyTechnician(tech2, TechnicianRegistry.Tier.Gold);
        registry.certifyTechnician(tech3, TechnicianRegistry.Tier.Bronze);
        // Transfer registry ownership to WorkOrderManager so it can call recordJob* functions
        registry.transferOwnership(address(workOrders));
        vm.stopPrank();
    }

    // ===========================
    // TechnicianRegistry Tests
    // ===========================

    function test_registerTechnician() public view {
        TechnicianRegistry.Technician memory t = registry.getTechnician(tech1);
        assertEq(t.wallet, tech1);
        assertEq(t.name, "John Electrician");
        assertEq(uint8(t.specialization), uint8(TechnicianRegistry.Specialization.Electrical));
        assertTrue(t.isActive);
        assertTrue(t.isCertified);
        assertEq(uint8(t.tier), uint8(TechnicianRegistry.Tier.Silver));
    }

    function test_revertDuplicateRegistration() public {
        vm.prank(admin);
        vm.expectRevert(TechnicianRegistry.AlreadyRegistered.selector);
        registry.registerTechnician(tech1, "Duplicate", TechnicianRegistry.Specialization.General);
    }

    function test_deactivateReactivate() public {
        vm.prank(admin);
        registry.deactivateTechnician(tech1);
        assertFalse(registry.getTechnician(tech1).isActive);

        vm.prank(admin);
        registry.reactivateTechnician(tech1);
        assertTrue(registry.getTechnician(tech1).isActive);
    }

    function test_rateTechnician() public {
        vm.prank(client1);
        registry.rateTechnician(tech1, 5);

        vm.prank(client2);
        registry.rateTechnician(tech1, 4);

        TechnicianRegistry.Technician memory t = registry.getTechnician(tech1);
        assertEq(t.totalRating, 9);
        assertEq(t.ratingCount, 2);

        uint256 avg = registry.getAverageRating(tech1);
        assertEq(avg, 450);
    }

    function test_revertDuplicateRating() public {
        vm.prank(client1);
        registry.rateTechnician(tech1, 5);

        vm.prank(client1);
        vm.expectRevert(TechnicianRegistry.AlreadyRated.selector);
        registry.rateTechnician(tech1, 4);
    }

    function test_revertInvalidRating() public {
        vm.prank(client1);
        vm.expectRevert(TechnicianRegistry.InvalidRating.selector);
        registry.rateTechnician(tech1, 0);

        vm.prank(client2);
        vm.expectRevert(TechnicianRegistry.InvalidRating.selector);
        registry.rateTechnician(tech1, 6);
    }

    function test_tierAutoUpgrade() public {
        vm.startPrank(admin);
        for (uint256 i = 0; i < 11; i++) {
            registry.recordJobCompletion(tech3);
        }
        vm.stopPrank();

        vm.prank(client1);
        registry.rateTechnician(tech3, 5);

        address client3 = address(0x3003);
        address client4 = address(0x3004);
        vm.prank(client3);
        registry.rateTechnician(tech3, 4);
        vm.prank(client4);
        registry.rateTechnician(tech3, 4);

        TechnicianRegistry.Technician memory t = registry.getTechnician(tech3);
        assertEq(uint8(t.tier), uint8(TechnicianRegistry.Tier.Silver));
    }

    function test_getTechniciansBySpec() public view {
        address[] memory elect = registry.getTechniciansBySpec(TechnicianRegistry.Specialization.Electrical);
        assertEq(elect.length, 1);
        assertEq(elect[0], tech1);
    }

    // ===========================
    // WorkOrderManager Tests
    // ===========================

    function test_createWorkOrder() public {
        vm.startPrank(client1);
        usdc.approve(address(workOrders), PAYMENT);

        uint256 orderId = workOrders.createWorkOrder(
            "Electrical Inspection",
            "123 Main St, Dallas TX",
            "Full electrical panel inspection and testing",
            "QmHash123",
            WorkOrderManager.Priority.High,
            PAYMENT
        );
        vm.stopPrank();

        assertEq(orderId, 0);
        assertEq(workOrders.workOrderCount(), 1);

        WorkOrderManager.OrderCore memory core = workOrders.getOrderCore(0);
        assertEq(core.client, client1);
        assertEq(core.paymentAmount, PAYMENT);
        assertEq(uint8(core.priority), uint8(WorkOrderManager.Priority.High));
        assertEq(uint8(core.status), 0); // Pending

        assertEq(usdc.balanceOf(address(workOrders)), PAYMENT);
        assertEq(usdc.balanceOf(client1), 100_000 * ONE_USDC - PAYMENT);
    }

    function test_assignTechnician() public {
        _createAndAssignOrder();
        WorkOrderManager.OrderCore memory core = workOrders.getOrderCore(0);
        assertEq(core.technician, tech1);
        assertEq(uint8(core.status), 1); // Assigned
    }

    function test_revertAssignUncertifiedTech() public {
        address uncertified = address(0x9999);
        vm.prank(admin);
        registry.registerTechnician(uncertified, "New Guy", TechnicianRegistry.Specialization.General);

        _createOrder();

        vm.prank(admin);
        vm.expectRevert(TechnicianRegistry.NotCertified.selector);
        workOrders.assignTechnician(0, uncertified);
    }

    function test_revertAssignInactiveTech() public {
        vm.prank(admin);
        registry.deactivateTechnician(tech1);

        _createOrder();

        vm.prank(admin);
        vm.expectRevert(TechnicianRegistry.NotActive.selector);
        workOrders.assignTechnician(0, tech1);
    }

    function test_fullWorkOrderLifecycle() public {
        _createAndAssignOrder();

        vm.prank(tech1);
        workOrders.startWork(0);
        assertEq(uint8(workOrders.getOrderCore(0).status), 2); // InProgress

        vm.prank(tech1);
        workOrders.completeWork(0, "All circuits tested, panel replaced", "QmCompletionHash456");
        assertEq(uint8(workOrders.getOrderCore(0).status), 3); // Completed

        uint256 techBalBefore = usdc.balanceOf(tech1);
        uint256 treasuryBalBefore = usdc.balanceOf(treasury);

        vm.prank(client1);
        workOrders.verifyWorkOrder(0);

        assertEq(uint8(workOrders.getOrderCore(0).status), 4); // Verified

        uint256 fee = (PAYMENT * 500) / 10000;
        uint256 payout = PAYMENT - fee;

        assertEq(usdc.balanceOf(tech1), techBalBefore + payout);
        assertEq(usdc.balanceOf(treasury), treasuryBalBefore + fee);
    }

    function test_cancelPendingOrder() public {
        _createOrder();
        uint256 clientBalBefore = usdc.balanceOf(client1);

        vm.prank(client1);
        workOrders.cancelWorkOrder(0);

        assertEq(uint8(workOrders.getOrderCore(0).status), 6); // Cancelled
        assertEq(usdc.balanceOf(client1), clientBalBefore + PAYMENT);
    }

    function test_revertCancelAssignedOrder() public {
        _createAndAssignOrder();

        vm.prank(client1);
        vm.expectRevert(abi.encodeWithSignature(
            "InvalidStatus(uint8,uint8)",
            uint8(WorkOrderManager.Status.Assigned),
            uint8(WorkOrderManager.Status.Pending)
        ));
        workOrders.cancelWorkOrder(0);
    }

    function test_disputeAndResolve() public {
        _createAndAssignOrder();

        vm.prank(tech1);
        workOrders.startWork(0);

        vm.prank(tech1);
        workOrders.completeWork(0, "Work done", "QmHash");

        vm.prank(client1);
        workOrders.disputeWorkOrder(0, "Quality issues found");

        assertEq(uint8(workOrders.getOrderCore(0).status), 5); // Disputed

        uint256 techBalBefore = usdc.balanceOf(tech1);
        vm.prank(admin);
        workOrders.resolveDispute(0, true, "Reviewed evidence");

        uint256 fee = (PAYMENT * 500) / 10000;
        uint256 payout = PAYMENT - fee;
        assertEq(usdc.balanceOf(tech1), techBalBefore + payout);
    }

    function test_disputeAndResolveRefund() public {
        _createAndAssignOrder();

        vm.prank(tech1);
        workOrders.startWork(0);

        vm.prank(tech1);
        workOrders.completeWork(0, "Work done", "QmHash");

        vm.prank(client1);
        workOrders.disputeWorkOrder(0, "Work not done properly");

        uint256 clientBalBefore = usdc.balanceOf(client1);
        vm.prank(admin);
        workOrders.resolveDispute(0, false, "Work was substandard");

        assertEq(usdc.balanceOf(client1), clientBalBefore + PAYMENT);
    }

    function test_reassignTechnician() public {
        _createAndAssignOrder();

        vm.prank(admin);
        workOrders.reassignTechnician(0, tech2);

        WorkOrderManager.OrderCore memory core = workOrders.getOrderCore(0);
        assertEq(core.technician, tech2);
        assertEq(uint8(core.status), 1); // Assigned
    }

    function test_revertClientStartWork() public {
        _createAndAssignOrder();

        vm.prank(client1);
        vm.expectRevert(WorkOrderManager.NotTechnician.selector);
        workOrders.startWork(0);
    }

    function test_revertTechVerifyOrder() public {
        _createAndAssignOrder();

        vm.prank(tech1);
        workOrders.startWork(0);

        vm.prank(tech1);
        workOrders.completeWork(0, "Done", "QmHash");

        vm.prank(tech1);
        vm.expectRevert(WorkOrderManager.NotClient.selector);
        workOrders.verifyWorkOrder(0);
    }

    function test_multipleWorkOrders() public {
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(client1);
            usdc.approve(address(workOrders), PAYMENT);
            workOrders.createWorkOrder("Service", "Location", "Description", "QmHash", WorkOrderManager.Priority.Medium, PAYMENT);
            vm.stopPrank();
        }
        assertEq(workOrders.workOrderCount(), 3);
    }

    // ===========================
    // EquipmentManager Tests
    // ===========================

    function test_addEquipment() public {
        uint256 eqId = equipment.addEquipment(
            "Fluke 87V Multimeter", "FL87V-12345", "Testing",
            block.timestamp, block.timestamp + 180 days, 500 * ONE_USDC, "Primary testing multimeter"
        );

        EquipmentManager.Equipment memory eq = equipment.getEquipment(eqId);
        assertEq(eq.name, "Fluke 87V Multimeter");
        assertEq(eq.serialNumber, "FL87V-12345");
        assertEq(uint8(eq.status), 0); // Available
        assertEq(uint8(eq.condition), 0); // Excellent
    }

    function test_assignAndReturnEquipment() public {
        uint256 eqId = equipment.addEquipment(
            "Fluke 87V", "SN123", "Testing",
            block.timestamp, block.timestamp + 180 days, 500 * ONE_USDC, ""
        );

        equipment.assignEquipment(eqId, tech1);
        assertEq(equipment.getEquipment(eqId).assignedTo, tech1);
        assertEq(uint8(equipment.getEquipment(eqId).status), 1); // Assigned

        equipment.returnEquipment(eqId, EquipmentManager.Condition.Good);
        assertEq(equipment.getEquipment(eqId).assignedTo, address(0));
        assertEq(uint8(equipment.getEquipment(eqId).status), 0); // Available
        assertEq(uint8(equipment.getEquipment(eqId).condition), 1); // Good
    }

    function test_maintenanceTracking() public {
        uint256 eqId = equipment.addEquipment(
            "Drill", "DR456", "Power Tools",
            block.timestamp, block.timestamp + 90 days, 200 * ONE_USDC, ""
        );

        equipment.recordMaintenance(eqId, EquipmentManager.Condition.Good, "Routine inspection", 50 * ONE_USDC);

        EquipmentManager.MaintenanceRecord[] memory history = equipment.getMaintenanceHistory(eqId);
        assertEq(history.length, 1);
        assertEq(history[0].description, "Routine inspection");
    }

    function test_technicianEquipmentList() public {
        uint256 eq1 = equipment.addEquipment("Tool1", "T1", "Testing", block.timestamp, block.timestamp + 90 days, 100, "");
        uint256 eq2 = equipment.addEquipment("Tool2", "T2", "Testing", block.timestamp, block.timestamp + 90 days, 200, "");

        equipment.assignEquipment(eq1, tech1);
        equipment.assignEquipment(eq2, tech1);

        uint256[] memory techEq = equipment.getTechnicianEquipment(tech1);
        assertEq(techEq.length, 2);
        assertEq(techEq[0], eq1);
        assertEq(techEq[1], eq2);
    }

    function test_retireEquipment() public {
        uint256 eqId = equipment.addEquipment("OldTool", "OT1", "Testing", block.timestamp, block.timestamp + 90 days, 50, "");
        equipment.retireEquipment(eqId);
        assertEq(uint8(equipment.getEquipment(eqId).status), 3); // Retired
    }

    function test_maintenanceLifecycle() public {
        uint256 eqId = equipment.addEquipment("Tool", "T1", "Testing", block.timestamp, block.timestamp + 90 days, 100, "");

        equipment.sendToMaintenance(eqId);
        assertEq(uint8(equipment.getEquipment(eqId).status), 2); // Maintenance

        equipment.returnFromMaintenance(eqId);
        assertEq(uint8(equipment.getEquipment(eqId).status), 0); // Available
    }

    // ===========================
    // SLA Tests
    // ===========================

    function test_createSLATemplate() public {
        uint256 tmplId = sla.createTemplate(
            "Emergency SLA", "Emergency",
            1 hours, 4 hours, 200, 500, 5000
        );

        ServiceLevelAgreement.SLATemplate memory tmpl = sla.getTemplate(tmplId);
        assertEq(tmpl.name, "Emergency SLA");
        assertEq(tmpl.maxResponseTime, 1 hours);
        assertTrue(tmpl.isActive);
    }

    function test_attachAndRecordSLA() public {
        uint256 tmplId = sla.createTemplate(
            "Standard", "Standard",
            4 hours, 24 hours, 100, 200, 3000
        );

        sla.attachSLA(tmplId, 1, tech1, block.timestamp);

        sla.recordResponse(1, block.timestamp + 2 hours);

        ServiceLevelAgreement.SLAInstance memory inst = sla.getInstance(1);
        assertTrue(inst.responseMet);

        sla.recordCompletion(1, block.timestamp + 20 hours, PAYMENT);
        inst = sla.getInstance(1);
        assertTrue(inst.completionMet);
        assertTrue(inst.adjustment > 0); // bonus
    }

    function test_slaLateCompletionPenalty() public {
        uint256 tmplId = sla.createTemplate(
            "Standard", "Standard",
            4 hours, 24 hours, 100, 200, 3000
        );

        uint256 assignedTime = block.timestamp;
        sla.attachSLA(tmplId, 1, tech1, assignedTime);

        sla.recordResponse(1, assignedTime + 3 hours);

        sla.recordCompletion(1, assignedTime + 29 hours, PAYMENT);

        ServiceLevelAgreement.SLAInstance memory inst = sla.getInstance(1);
        assertFalse(inst.completionMet);
        assertTrue(inst.adjustment < 0); // penalty
    }

    function test_deactivateTemplate() public {
        uint256 tmplId = sla.createTemplate(
            "Old SLA", "Test", 1 hours, 4 hours, 100, 200, 3000
        );

        sla.deactivateTemplate(tmplId);
        assertFalse(sla.getTemplate(tmplId).isActive);
    }

    function test_revertAttachInactiveTemplate() public {
        uint256 tmplId = sla.createTemplate(
            "Old SLA", "Test", 1 hours, 4 hours, 100, 200, 3000
        );
        sla.deactivateTemplate(tmplId);

        vm.expectRevert(ServiceLevelAgreement.TemplateNotActive.selector);
        sla.attachSLA(tmplId, 1, tech1, block.timestamp);
    }

    // ===========================
    // Helper Functions
    // ===========================

    function _createOrder() internal {
        vm.startPrank(client1);
        usdc.approve(address(workOrders), PAYMENT);
        workOrders.createWorkOrder(
            "Electrical Inspection", "123 Main St",
            "Full panel inspection", "QmHash",
            WorkOrderManager.Priority.High, PAYMENT
        );
        vm.stopPrank();
    }

    function _createAndAssignOrder() internal {
        _createOrder();
        vm.prank(admin);
        workOrders.assignTechnician(0, tech1);
    }
}
