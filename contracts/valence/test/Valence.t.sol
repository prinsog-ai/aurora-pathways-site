// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/CarbonCredit.sol";
import "../src/CreditSplitter.sol";
import "../src/AttestationModule.sol";

contract ValenceTest is Test {
    CarbonCredit credit;
    CreditSplitter splitter;
    AttestationModule attestation;

    address siteOwner = address(0x2);
    address other = address(0x3);

    function setUp() public {
        credit = new CarbonCredit(address(this));
        splitter = new CreditSplitter(address(credit));
        attestation = new AttestationModule(address(credit), address(splitter));
        credit.setMinter(address(attestation));
        splitter.registerSite("bakken-1", siteOwner, 6000);
        // After setup, transfer splitter ownership to attestation
        splitter.transferOwnership(address(attestation));
    }

    function test_initial_state() public {
        assertEq(credit.name(), "Valence Carbon Credit");
        assertEq(credit.symbol(), "VC02");
        assertEq(credit.minter(), address(attestation));
        assertEq(splitter.getSiteCount(), 1);
        assertEq(splitter.owner(), address(attestation));
    }

    function test_mint_only_minter() public {
        vm.prank(address(attestation));
        credit.mint(address(1), 100, "test");
        assertEq(credit.balanceOf(address(1)), 100);
        assertEq(credit.totalMinted(), 100);
    }

    function test_mint_rejects_unauthorized() public {
        vm.prank(other);
        vm.expectRevert("Not authorized minter");
        credit.mint(other, 100, "test");
    }

    function test_retire() public {
        vm.prank(address(attestation));
        credit.mint(other, 100, "test");
        vm.prank(other);
        credit.retire(50, "ESG");
        assertEq(credit.balanceOf(other), 50);
        assertEq(credit.totalRetired(), 50);
    }

    function test_retire_insufficient() public {
        vm.prank(address(attestation));
        credit.mint(other, 10, "test");
        vm.prank(other);
        vm.expectRevert("Insufficient balance");
        credit.retire(20, "test");
    }

    function test_register_site() public {
        vm.prank(address(attestation));
        splitter.registerSite("permian-1", other, 5500);
        assertEq(splitter.getSiteCount(), 2);
    }

    function test_register_duplicate() public {
        vm.prank(address(attestation));
        vm.expectRevert("Site exists");
        splitter.registerSite("bakken-1", siteOwner, 5000);
    }

    function test_distribute_60_40() public {
        vm.prank(address(attestation));
        credit.mint(address(splitter), 1000, "bakken-1");
        vm.prank(address(attestation));
        splitter.distribute("bakken-1", 1000);
        // Splitter owner is attestation, so 60% goes to attestation
        assertEq(credit.balanceOf(address(attestation)), 600);
        assertEq(credit.balanceOf(siteOwner), 400);
    }

    function test_update_share() public {
        vm.prank(address(attestation));
        splitter.updateShare("bakken-1", 7000);
        vm.prank(address(attestation));
        credit.mint(address(splitter), 1000, "bakken-1");
        vm.prank(address(attestation));
        splitter.distribute("bakken-1", 1000);
        assertEq(credit.balanceOf(address(attestation)), 700);
        assertEq(credit.balanceOf(siteOwner), 300);
    }

    function test_attest_creates_record() public {
        uint256 id = attestation.attest("bakken-1", 15000);
        (string memory siteId, uint256 volume, uint256 co2,,,,) = attestation.attestations(id);
        assertEq(siteId, "bakken-1");
        assertEq(volume, 15000);
        assertEq(co2, 540);
    }

    function test_finalize_mints_and_distributes() public {
        uint256 id = attestation.attest("bakken-1", 15000);
        vm.warp(block.timestamp + 3 days);
        attestation.finalize(id);
        // Attestation owns splitter, so 60% goes to attestation, 40% to siteOwner
        assertEq(credit.balanceOf(address(attestation)), 324);
        assertEq(credit.balanceOf(siteOwner), 216);
        assertEq(credit.totalMinted(), 540);
    }

    function test_dispute_blocks_finalization() public {
        uint256 id = attestation.attest("bakken-1", 15000);
        attestation.dispute(id);
        vm.warp(block.timestamp + 3 days);
        vm.expectRevert("Under dispute");
        attestation.finalize(id);
    }

    function test_dispute_window_expired() public {
        uint256 id = attestation.attest("bakken-1", 15000);
        vm.warp(block.timestamp + 3 days);
        vm.expectRevert("Dispute window closed");
        attestation.dispute(id);
    }

    function test_resolve_dispute_approve() public {
        uint256 id = attestation.attest("bakken-1", 15000);
        attestation.dispute(id);
        attestation.resolveDispute(id, true);
        vm.warp(block.timestamp + 3 days);
        attestation.finalize(id);
        assertEq(credit.totalMinted(), 540);
    }

    function test_resolve_dispute_reject() public {
        uint256 id = attestation.attest("bakken-1", 15000);
        attestation.dispute(id);
        attestation.resolveDispute(id, false);
        (,,,,,, bool finalized) = attestation.attestations(id);
        assertTrue(finalized);
        assertEq(credit.totalMinted(), 0);
    }

    function test_full_pipeline() public {
        vm.prank(address(attestation));
        splitter.registerSite("permian-1", address(0x4), 5000);
        uint256 id1 = attestation.attest("bakken-1", 15000);
        uint256 id2 = attestation.attest("permian-1", 20000);
        vm.warp(block.timestamp + 3 days);
        attestation.finalize(id1);
        attestation.finalize(id2);
        assertEq(credit.totalMinted(), 1260);
        // Bakken: 540 * 60% = 324 to attestation, 216 to siteOwner
        // Permian: 720 * 50% = 360 to attestation, 360 to permian owner
        assertEq(credit.balanceOf(address(attestation)), 684);
        assertEq(credit.balanceOf(siteOwner), 216);
        assertEq(credit.balanceOf(address(0x4)), 360);
    }

    function test_set_minter() public {
        credit.setMinter(other);
        assertEq(credit.minter(), other);
    }

    function test_set_dispute_window() public {
        attestation.setDisputeWindow(1 days);
        assertEq(attestation.disputeWindow(), 1 days);
    }

    receive() external payable {}
}
