// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AcmeAuditTrail.sol";
import "../src/AcmeSupplyChain.sol";
import "../src/AcmeSettlement.sol";

contract AcmeTest is Test {
    AcmeAuditTrail audit;
    AcmeSupplyChain supply;
    AcmeSettlement settlement;

    address admin = address(this);
    address user1 = address(0x10);
    address user2 = address(0x20);

    function setUp() public {
        audit = new AcmeAuditTrail();
        supply = new AcmeSupplyChain();
        settlement = new AcmeSettlement();
    }

    // ═══ AUDIT TRAIL TESTS ═══

    function test_record_audit() public {
        uint256 id = audit.record("invoice", "INV-001", "created", "abc123hash");
        assertEq(id, 0);
        assertEq(audit.getEntryCount(), 1);
    }

    function test_audit_chain_integrity() public {
        audit.record("invoice", "INV-001", "created", "hash1");
        audit.record("invoice", "INV-001", "approved", "hash2");
        audit.record("invoice", "INV-001", "paid", "hash3");

        uint256[] memory history = audit.getEntityHistory("INV-001");
        assertEq(history.length, 3);
        assertEq(audit.lastHash(), "hash3");
    }

    function test_verify_integrity() public {
        uint256 id = audit.record("patient", "PAT-001", "created", "datahash123");
        assertTrue(audit.verifyIntegrity(id, "datahash123"));
    }

    function test_audit_from_different_actors() public {
        vm.prank(user1);
        audit.record("po", "PO-001", "created", "h1");
        vm.prank(user2);
        audit.record("po", "PO-001", "approved", "h2");

        uint256[] memory history = audit.getEntityHistory("PO-001");
        assertEq(history.length, 2);
    }

    // ═══ SUPPLY CHAIN TESTS ═══

    function test_create_product() public {
        uint256 id = supply.createProduct("Widget A", "Acme Mfg", "QmMeta");
        assertEq(id, 0);
        (,,,,,, bool exists) = supply.products(id);
        assertTrue(exists);
    }

    function test_record_transfer() public {
        uint256 id = supply.createProduct("Widget A", "Acme Mfg", "QmMeta");
        supply.authorizeHandler(user1, true);

        vm.prank(user1);
        supply.recordTransfer(id, user2, "Warehouse A", "QmCondition", "Good condition");

        assertEq(supply.getTransferCount(id), 1);
    }

    function test_full_supply_chain() public {
        uint256 id = supply.createProduct("Pharma Drug", "PharmaCo", "QmMeta");
        supply.authorizeHandler(user1, true);
        supply.authorizeHandler(user2, true);

        vm.prank(user1);
        supply.recordTransfer(id, user2, "Factory", "Qm1", "Shipped");
        vm.prank(user2);
        supply.recordTransfer(id, admin, "Distribution Center", "Qm2", "Received");

        AcmeSupplyChain.Transfer[] memory chain = supply.getProductChain(id);
        assertEq(chain.length, 2);
        assertEq(chain[0].location, "Factory");
        assertEq(chain[1].location, "Distribution Center");
    }

    function test_unauthorized_transfer_rejected() public {
        uint256 id = supply.createProduct("Widget", "Mfg", "Qm");
        vm.prank(user1);
        vm.expectRevert("Not authorized");
        supply.recordTransfer(id, user2, "Loc", "Qm", "Notes");
    }

    // ═══ SETTLEMENT TESTS ═══

    function test_create_settlement() public {
        // Deposit funds
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        (bool sent,) = address(settlement).call{value: 1 ether}("");
        assertTrue(sent);

        vm.prank(user1);
        uint256 id = settlement.createSettlement(user2, 0.5 ether, "USD", "US", "UK");
        assertEq(id, 0);
        assertEq(settlement.getBalance(user1), 0.5 ether);
    }

    function test_settle() public {
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        address(settlement).call{value: 1 ether}("");

        vm.prank(user1);
        uint256 id = settlement.createSettlement(user2, 0.5 ether, "USD", "US", "UK");

        settlement.settle(id);
        assertEq(settlement.getBalance(user2), 0.5 ether);
        (,,,,,,,,, bool settled, bool disputed) = settlement.settlements(id);
        assertTrue(settled);
    }

    function test_dispute_refunds_sender() public {
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        address(settlement).call{value: 1 ether}("");

        vm.prank(user1);
        uint256 id = settlement.createSettlement(user2, 0.5 ether, "USD", "US", "UK");

        vm.prank(user1);
        settlement.dispute(id);
        assertEq(settlement.getBalance(user1), 1 ether); // Refunded
        (,,,,,,,,, bool settled2, bool disputed) = settlement.settlements(id);
        assertTrue(disputed);
    }

    function test_withdraw() public {
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        address(settlement).call{value: 1 ether}("");

        vm.prank(user1);
        settlement.createSettlement(user2, 0.5 ether, "USD", "US", "UK");
        settlement.settle(settlement.getSettlementCount() - 1);

        uint256 balBefore = user2.balance;
        vm.prank(user2);
        settlement.withdraw(0.5 ether);
        assertEq(user2.balance, balBefore + 0.5 ether);
    }

    function test_insufficient_balance() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        address(settlement).call{value: 0.1 ether}("");

        vm.prank(user1);
        vm.expectRevert("Insufficient balance");
        settlement.createSettlement(user2, 1 ether, "USD", "US", "UK");
    }

    receive() external payable {}
}
