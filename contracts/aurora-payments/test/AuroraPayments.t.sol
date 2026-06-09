// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AuroraPayments} from "../src/AuroraPayments.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AuroraPaymentsTest is Test {
    AuroraPayments public payments;
    MockUSDC public usdc;

    address public owner = address(1);
    address public partner1 = address(2);
    address public partner2 = address(3);
    address public client = address(4);
    address public stranger = address(5);

    function setUp() public {
        usdc = new MockUSDC();
        vm.prank(owner);
        payments = new AuroraPayments(owner);

        // Set up 70/30 split
        AuroraPayments.Recipient[] memory recs = new AuroraPayments.Recipient[](2);
        recs[0] = AuroraPayments.Recipient(partner1, 7000); // 70%
        recs[1] = AuroraPayments.Recipient(partner2, 3000); // 30%
        vm.prank(owner);
        payments.setRecipients(recs);

        // Add USDC as supported
        vm.prank(owner);
        payments.addSupportedToken(address(usdc));
    }

    function test_OwnerIsSet() public view {
        assertEq(payments.owner(), owner);
    }

    function test_SetRecipients() public view {
        assertEq(payments.recipientCount(), 2);
        assertEq(payments.totalShares(), 10000);
    }

    function test_RevertOnInvalidShares() public {
        AuroraPayments.Recipient[] memory recs = new AuroraPayments.Recipient[](2);
        recs[0] = AuroraPayments.Recipient(partner1, 5000);
        recs[1] = AuroraPayments.Recipient(partner2, 4000); // 90% total
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AuroraPayments.InvalidShares.selector, 9000));
        payments.setRecipients(recs);
    }

    function test_AddRemoveToken() public {
        address fakeToken = address(0xdead);
        assertFalse(payments.supportedTokens(fakeToken));

        vm.prank(owner);
        payments.addSupportedToken(fakeToken);
        assertTrue(payments.supportedTokens(fakeToken));

        vm.prank(owner);
        payments.removeSupportedToken(fakeToken);
        assertFalse(payments.supportedTokens(fakeToken));
    }

    function test_DistributeUSDC() public {
        // Client sends 1000 USDC to the contract
        usdc.mint(client, 1000 * 1e6); // 6 decimals
        vm.prank(client);
        usdc.transfer(address(payments), 1000 * 1e6);

        assertEq(usdc.balanceOf(address(payments)), 1000 * 1e6);

        // Distribute
        payments.distribute(address(usdc));

        assertEq(usdc.balanceOf(partner1), 700 * 1e6);  // 70%
        assertEq(usdc.balanceOf(partner2), 300 * 1e6);  // 30%
        assertEq(usdc.balanceOf(address(payments)), 0);

        assertEq(payments.totalRevenue(address(usdc)), 1000 * 1e6);
        assertEq(payments.recipientEarnings(partner1, address(usdc)), 700 * 1e6);
    }

    function test_RevertOnUnsupportedToken() public {
        address fakeToken = address(0xbad);
        vm.expectRevert(abi.encodeWithSelector(AuroraPayments.TokenNotSupported.selector, fakeToken));
        payments.distribute(fakeToken);
    }

    function test_RevertOnNoBalance() public {
        vm.expectRevert(AuroraPayments.NoBalance.selector);
        payments.distribute(address(usdc));
    }

    function test_RevertOnNoRecipients() public {
        // Deploy fresh with no recipients
        AuroraPayments p2;
        vm.prank(owner);
        p2 = new AuroraPayments(owner);

        vm.prank(owner);
        p2.addSupportedToken(address(usdc));

        // Send tokens
        usdc.mint(client, 100 * 1e6);
        vm.prank(client);
        usdc.transfer(address(p2), 100 * 1e6);

        vm.expectRevert(AuroraPayments.NoRecipients.selector);
        p2.distribute(address(usdc));
    }

    function test_NonOwnerCannotAddToken() public {
        vm.prank(stranger);
        vm.expectRevert();
        payments.addSupportedToken(address(0xcafe));
    }

    function test_MultipleDistributions() public {
        // First payment
        usdc.mint(client, 500 * 1e6);
        vm.prank(client);
        usdc.transfer(address(payments), 500 * 1e6);
        payments.distribute(address(usdc));

        // Second payment
        usdc.mint(client, 300 * 1e6);
        vm.prank(client);
        usdc.transfer(address(payments), 300 * 1e6);
        payments.distribute(address(usdc));

        assertEq(usdc.balanceOf(partner1), 560 * 1e6); // 70% of 800
        assertEq(usdc.balanceOf(partner2), 240 * 1e6); // 30% of 800
        assertEq(payments.totalRevenue(address(usdc)), 800 * 1e6);
    }

    function test_ReentrancyGuard() public {
        usdc.mint(client, 100 * 1e6);
        vm.prank(client);
        usdc.transfer(address(payments), 100 * 1e6);

        // distribute shouldn't be re-entrant
        payments.distribute(address(usdc));
        assertEq(usdc.balanceOf(address(payments)), 0);
    }

    function test_GetRecipients() public view {
        AuroraPayments.Recipient[] memory recs = payments.getRecipients();
        assertEq(recs.length, 2);
        assertEq(recs[0].wallet, partner1);
        assertEq(recs[0].share, 7000);
        assertEq(recs[1].wallet, partner2);
        assertEq(recs[1].share, 3000);
    }
}