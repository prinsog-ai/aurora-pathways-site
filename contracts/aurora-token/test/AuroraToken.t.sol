// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AuroraToken} from "../src/AuroraToken.sol";

contract AuroraTokenTest is Test {
    AuroraToken public token;
    address public owner = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public carol = address(4);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        vm.prank(owner);
        token = new AuroraToken(owner);
    }

    // ── Deployment ──────────────────────────────────────────────

    function test_DeployerIsOwner() public view {
        assertEq(token.owner(), owner);
    }

    function test_NameAndSymbol() public view {
        assertEq(token.name(), "Aurora Token");
        assertEq(token.symbol(), "AURA");
    }

    function test_Decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_InitialSupplyIsZero() public view {
        assertEq(token.totalSupply(), 0);
    }

    function test_MaxSupplyConstant() public view {
        assertEq(token.MAX_SUPPLY(), 1_000_000_000 * 1e18);
    }

    // ── Minting ─────────────────────────────────────────────────

    function test_OwnerCanMint() public {
        vm.prank(owner);
        token.mint(alice, 1000 * 1e18);
        assertEq(token.balanceOf(alice), 1000 * 1e18);
        assertEq(token.totalSupply(), 1000 * 1e18);
    }

    function test_MintEmitsTransfer() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), alice, 500 * 1e18);
        token.mint(alice, 500 * 1e18);
    }

    function test_NonOwnerCannotMint() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 100 * 1e18);
    }

    function test_CannotExceedMaxSupply() public {
        uint256 maxSupply = token.MAX_SUPPLY();

        vm.prank(owner);
        token.mint(alice, maxSupply);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AuroraToken.ExceedsMaxSupply.selector, maxSupply + 1, maxSupply));
        token.mint(bob, 1);
    }

    function test_MultipleMintsToCap() public {
        uint256 maxSupply = token.MAX_SUPPLY();

        vm.startPrank(owner);
        token.mint(alice, maxSupply / 2);
        token.mint(bob, maxSupply / 2);
        vm.stopPrank();

        assertEq(token.totalSupply(), maxSupply);
        assertEq(token.balanceOf(alice), maxSupply / 2);
        assertEq(token.balanceOf(bob), maxSupply / 2);
    }

    function test_MintZeroSucceedsNoop() public {
        vm.startPrank(owner);
        uint256 supplyBefore = token.totalSupply();
        token.mint(alice, 0);
        assertEq(token.totalSupply(), supplyBefore);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 0);
    }

    function test_MintToZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert();
        token.mint(address(0), 100 * 1e18);
    }

    // ── Burning ─────────────────────────────────────────────────

    function test_Burn() public {
        vm.prank(owner);
        token.mint(alice, 500 * 1e18);

        vm.prank(alice);
        token.burn(200 * 1e18);

        assertEq(token.balanceOf(alice), 300 * 1e18);
        assertEq(token.totalSupply(), 300 * 1e18);
    }

    function test_BurnEmitsTransfer() public {
        vm.prank(owner);
        token.mint(alice, 500 * 1e18);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, address(0), 100 * 1e18);
        token.burn(100 * 1e18);
    }

    function test_CannotBurnMoreThanBalance() public {
        vm.prank(owner);
        token.mint(alice, 100 * 1e18);

        vm.prank(alice);
        vm.expectRevert();
        token.burn(200 * 1e18);
    }

    function test_BurnZeroSucceedsNoop() public {
        vm.prank(owner);
        token.mint(alice, 100 * 1e18);

        uint256 supplyBefore = token.totalSupply();
        vm.prank(alice);
        token.burn(0);

        assertEq(token.totalSupply(), supplyBefore);
        assertEq(token.balanceOf(alice), 100 * 1e18);
    }

    function test_BurnWithZeroBalanceReverts() public {
        vm.prank(carol);
        vm.expectRevert();
        token.burn(1);
    }

    // ── Transfers ───────────────────────────────────────────────

    function test_Transfer() public {
        vm.prank(owner);
        token.mint(alice, 100 * 1e18);

        vm.prank(alice);
        token.transfer(bob, 40 * 1e18);

        assertEq(token.balanceOf(alice), 60 * 1e18);
        assertEq(token.balanceOf(bob), 40 * 1e18);
    }

    function test_TransferEmitsEvent() public {
        vm.prank(owner);
        token.mint(alice, 300 * 1e18);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, bob, 150 * 1e18);
        token.transfer(bob, 150 * 1e18);
    }

    function test_TransferFullBalance() public {
        vm.prank(owner);
        token.mint(alice, 1000 * 1e18);

        vm.prank(alice);
        token.transfer(bob, 1000 * 1e18);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1000 * 1e18);
    }

    function test_TransferToZeroAddressReverts() public {
        vm.prank(owner);
        token.mint(alice, 100 * 1e18);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(address(0), 50 * 1e18);
    }

    function test_TransferMoreThanBalanceReverts() public {
        vm.prank(owner);
        token.mint(alice, 100 * 1e18);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 101 * 1e18);
    }

    function test_TransferZeroSucceedsNoop() public {
        vm.prank(owner);
        token.mint(alice, 100 * 1e18);

        vm.prank(alice);
        bool result = token.transfer(bob, 0);

        assertTrue(result);
        assertEq(token.balanceOf(alice), 100 * 1e18);
        assertEq(token.balanceOf(bob), 0);
    }

    // ── Approvals & Allowance ───────────────────────────────────

    function test_Approve() public {
        vm.prank(owner);
        token.mint(alice, 1000 * 1e18);

        vm.prank(alice);
        token.approve(bob, 300 * 1e18);

        assertEq(token.allowance(alice, bob), 300 * 1e18);
    }

    function test_ApproveEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Approval(alice, bob, 500 * 1e18);
        token.approve(bob, 500 * 1e18);
    }

    function test_ApproveOverwrite() public {
        vm.prank(alice);
        token.approve(bob, 100 * 1e18);
        assertEq(token.allowance(alice, bob), 100 * 1e18);

        vm.prank(alice);
        token.approve(bob, 200 * 1e18);
        assertEq(token.allowance(alice, bob), 200 * 1e18);
    }

    function test_TransferFrom() public {
        vm.prank(owner);
        token.mint(alice, 1000 * 1e18);

        vm.prank(alice);
        token.approve(bob, 400 * 1e18);

        vm.prank(bob);
        token.transferFrom(alice, carol, 250 * 1e18);

        assertEq(token.balanceOf(alice), 750 * 1e18);
        assertEq(token.balanceOf(carol), 250 * 1e18);
        assertEq(token.allowance(alice, bob), 150 * 1e18);
    }

    function test_TransferFromEmitsTransfer() public {
        vm.prank(owner);
        token.mint(alice, 1000 * 1e18);

        vm.prank(alice);
        token.approve(bob, 500 * 1e18);

        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, carol, 300 * 1e18);
        token.transferFrom(alice, carol, 300 * 1e18);
    }

    function test_TransferFromExceedsAllowanceReverts() public {
        vm.prank(owner);
        token.mint(alice, 1000 * 1e18);

        vm.prank(alice);
        token.approve(bob, 100 * 1e18);

        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, carol, 101 * 1e18);
    }

    function test_TransferFromNoAllowanceReverts() public {
        vm.prank(owner);
        token.mint(alice, 1000 * 1e18);

        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, carol, 1);
    }

    function test_ApproveZeroAddressSpenderReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        token.approve(address(0), 100 * 1e18);
    }

    // ── Ownership ───────────────────────────────────────────────

    function test_TransferOwnership() public {
        vm.prank(owner);
        token.transferOwnership(alice);

        assertEq(token.owner(), alice);
    }

    function test_TransferOwnershipEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, alice);
        token.transferOwnership(alice);
    }

    function test_NonOwnerCannotTransferOwnership() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transferOwnership(alice);
    }

    function test_OwnerCanRenounce() public {
        vm.prank(owner);
        token.renounceOwnership();
        assertEq(token.owner(), address(0));
    }
}
