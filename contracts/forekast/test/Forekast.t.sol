// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Forekast.sol";
import "../src/MockUSDC.sol";

contract ForekastTest is Test {
    Forekast public forekast;
    MockUSDC public usdc;
    address public owner = address(this);
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        usdc = new MockUSDC("USD Coin", "USDC", 6);
        forekast = new Forekast(address(usdc), owner);

        usdc.mint(alice, 1000e6);
        usdc.mint(bob, 1000e6);
        usdc.mint(owner, 1000e6);

        vm.prank(alice);
        usdc.approve(address(forekast), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(forekast), type(uint256).max);
        vm.startPrank(owner);
        usdc.approve(address(forekast), type(uint256).max);
        vm.stopPrank();
    }

    function testCreateMarket() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 id = forekast.createMarket("Will BTC hit 100k?", Forekast.Category.Crypto, deadline, 100e6);
        assertEq(id, 0);
        assertEq(forekast.marketCount(), 1);
    }

    function testPlaceBet() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 id = forekast.createMarket("Will ETH merge?", Forekast.Category.Crypto, deadline, 100e6);

        vm.prank(alice);
        forekast.placeBet(id, false, 50e6);

        Forekast.Market memory market = forekast.getMarket(id);
        assertEq(market.totalNo, 50e6);
    }

    function testResolveMarketYes() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 id = forekast.createMarket("Will BTC hit 100k?", Forekast.Category.Crypto, deadline, 100e6);

        vm.prank(alice);
        forekast.placeBet(id, false, 100e6);

        vm.warp(deadline + 1);
        forekast.resolveMarket(id, true);

        // Alice had 100e6 on No (lost)
        // Owner had 100e6 on Yes (won)
        // Loser pool = 100e6, fee = 3e6, prize pool = 97e6
        // Owner payout = 100e6 + 97e6 = 197e6
        uint256 ownerBalBefore = usdc.balanceOf(owner);
        forekast.claimWinnings(id);
        uint256 ownerBalAfter = usdc.balanceOf(owner);
        assertEq(ownerBalAfter - ownerBalBefore, 197e6);
    }

    function testResolveMarketNo() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 id = forekast.createMarket("Will XRP win?", Forekast.Category.Crypto, deadline, 50e6);

        vm.prank(alice);
        forekast.placeBet(id, false, 50e6);

        vm.warp(deadline + 1);
        forekast.resolveMarket(id, false);

        // Owner had 50e6 on Yes (lost)
        // Alice had 50e6 on No (won)
        // Loser pool = 50e6, fee = 1.5e6, prize = 48.5e6
        // Alice payout = 50e6 + 48.5e6 = 98.5e6
        uint256 aliceBalBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        forekast.claimWinnings(id);
        uint256 aliceBalAfter = usdc.balanceOf(alice);
        assertEq(aliceBalAfter - aliceBalBefore, 98_500_000);
    }

    function testCannotBetAfterDeadline() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 id = forekast.createMarket("Test", Forekast.Category.Other, deadline, 10e6);

        vm.warp(deadline + 1);
        vm.prank(alice);
        vm.expectRevert("Market deadline passed");
        forekast.placeBet(id, true, 10e6);
    }

    function testOnlyOwnerOrCreatorCanResolve() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 id = forekast.createMarket("Test", Forekast.Category.Other, deadline, 10e6);
        vm.warp(deadline + 1);
        vm.prank(alice);
        vm.expectRevert("Not authorized");
        forekast.resolveMarket(id, true);
    }

    function testWithdrawFees() public {
        uint256 deadline = block.timestamp + 1 days;
        uint256 id = forekast.createMarket("Test", Forekast.Category.Other, deadline, 100e6);

        vm.prank(alice);
        forekast.placeBet(id, false, 100e6);

        vm.warp(deadline + 1);
        forekast.resolveMarket(id, true);

        forekast.claimWinnings(id); // triggers fee accumulation

        uint256 balBefore = usdc.balanceOf(owner);
        forekast.withdrawFees();
        uint256 balAfter = usdc.balanceOf(owner);
        assertEq(balAfter - balBefore, 3e6); // 3% of 100e6 loser pool
    }
}
