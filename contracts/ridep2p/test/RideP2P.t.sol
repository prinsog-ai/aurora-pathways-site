// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/RideP2P.sol";
import "../src/MockUSDC.sol";

contract RideP2PTest is Test {
    RideP2P public ridep2p;
    MockUSDC public usdc;

    address public admin = address(this);
    address public driver = address(0xA);
    address public rider1 = address(0xB);
    address public rider2 = address(0xC);

    uint256 public constant PRICE_PER_SEAT = 10e6; // 10 USDC
    uint256 public constant SEATS = 3;

    function setUp() public {
        usdc = new MockUSDC("USD Coin", "USDC", 6);
        ridep2p = new RideP2P(address(usdc));

        usdc.mint(rider1, 1000e6);
        usdc.mint(rider2, 1000e6);

        vm.prank(rider1);
        usdc.approve(address(ridep2p), type(uint256).max);
        vm.prank(rider2);
        usdc.approve(address(ridep2p), type(uint256).max);
    }

    function _futureTime() internal view returns (uint256) {
        return block.timestamp + 1 days;
    }

    // ─── Create Ride ─────────────────────────────────────────────────
    function testCreateRide() public {
        uint256 ft = _futureTime();
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", ft, PRICE_PER_SEAT, SEATS);

        assertEq(rideId, 1);
        (
            address d,
            ,
            ,
            uint256 dep,
            uint256 price,
            uint256 total,
            uint256 booked,
            
        ) = ridep2p.rides(rideId);
        assertEq(d, driver);
        assertEq(dep, ft);
        assertEq(price, PRICE_PER_SEAT);
        assertEq(total, SEATS);
        assertEq(booked, 0);
    }

    function testCreateRideRevertsPastDeparture() public {
        vm.prank(driver);
        vm.expectRevert("Departure must be future");
        ridep2p.createRide("NYC", "Boston", block.timestamp - 1, PRICE_PER_SEAT, SEATS);
    }

    function testCreateRideRevertsZeroPrice() public {
        vm.prank(driver);
        vm.expectRevert("Price must be > 0");
        ridep2p.createRide("NYC", "Boston", _futureTime(), 0, SEATS);
    }

    // ─── Book Ride ───────────────────────────────────────────────────
    function testBookRide() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        uint256 bookingId = ridep2p.bookRide(rideId, 1);

        assertEq(bookingId, 1);
        (address r, , uint256 seats, uint256 amount, ) = ridep2p.bookings(bookingId);
        assertEq(r, rider1);
        assertEq(seats, 1);
        assertEq(amount, PRICE_PER_SEAT);

        assertEq(usdc.balanceOf(address(ridep2p)), PRICE_PER_SEAT);
        assertEq(usdc.balanceOf(rider1), 1000e6 - PRICE_PER_SEAT);
    }

    function testBookRideMultipleSeats() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        uint256 bookingId = ridep2p.bookRide(rideId, 2);

        (, , , uint256 amount, ) = ridep2p.bookings(bookingId);
        assertEq(amount, PRICE_PER_SEAT * 2);
    }

    function testBookRideRevertsOverCapacity() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, 1);

        vm.prank(rider1);
        ridep2p.bookRide(rideId, 1);

        vm.prank(rider2);
        vm.expectRevert("Not enough seats");
        ridep2p.bookRide(rideId, 1);
    }

    function testBookRideRevertsDriverCannotBook() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(driver);
        vm.expectRevert("Driver cannot book own ride");
        ridep2p.bookRide(rideId, 1);
    }

    // ─── Complete Ride ───────────────────────────────────────────────
    function testCompleteRide() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        ridep2p.bookRide(rideId, 2);
        vm.prank(rider2);
        ridep2p.bookRide(rideId, 1);

        uint256 totalRevenue = PRICE_PER_SEAT * 3;
        uint256 expectedFee = (totalRevenue * 300) / 10000;
        uint256 expectedPayout = totalRevenue - expectedFee;

        vm.prank(driver);
        ridep2p.completeRide(rideId);

        assertEq(usdc.balanceOf(driver), expectedPayout);
        assertEq(usdc.balanceOf(admin), expectedFee);
        assertEq(usdc.balanceOf(address(ridep2p)), 0);
    }

    function testCompleteRideRevertsNotDriver() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        ridep2p.bookRide(rideId, 1);

        vm.prank(rider1);
        vm.expectRevert("Not the driver");
        ridep2p.completeRide(rideId);
    }

    function testCompleteRideRevertsNoBookings() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(driver);
        vm.expectRevert("No bookings");
        ridep2p.completeRide(rideId);
    }

    // ─── Cancel Booking ──────────────────────────────────────────────
    function testCancelBooking() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        uint256 bookingId = ridep2p.bookRide(rideId, 1);

        uint256 balBefore = usdc.balanceOf(rider1);

        vm.prank(rider1);
        ridep2p.cancelBooking(bookingId);

        assertEq(usdc.balanceOf(rider1), balBefore + PRICE_PER_SEAT);
        (, , , , RideP2P.BookingStatus status) = ridep2p.bookings(bookingId);
        assertTrue(status == RideP2P.BookingStatus.Refunded);
    }

    function testCancelBookingRevertsAfterDeparture() public {
        uint256 ft = _futureTime();
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", ft, PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        uint256 bookingId = ridep2p.bookRide(rideId, 1);

        vm.warp(ft + 1);

        vm.prank(rider1);
        vm.expectRevert("Already departed");
        ridep2p.cancelBooking(bookingId);
    }

    function testCancelBookingRevertsNotRider() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        uint256 bookingId = ridep2p.bookRide(rideId, 1);

        vm.prank(rider2);
        vm.expectRevert("Not the rider");
        ridep2p.cancelBooking(bookingId);
    }

    // ─── Driver Cancel Ride ──────────────────────────────────────────
    function testDriverCancelRide() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        ridep2p.bookRide(rideId, 2);
        vm.prank(rider2);
        ridep2p.bookRide(rideId, 1);

        uint256 r1Bal = usdc.balanceOf(rider1);
        uint256 r2Bal = usdc.balanceOf(rider2);

        vm.prank(driver);
        ridep2p.driverCancelRide(rideId);

        assertEq(usdc.balanceOf(rider1), r1Bal + PRICE_PER_SEAT * 2);
        assertEq(usdc.balanceOf(rider2), r2Bal + PRICE_PER_SEAT);

        (, , , , , , , RideP2P.RideStatus rideStatus) = ridep2p.rides(rideId);
        assertTrue(rideStatus == RideP2P.RideStatus.Cancelled);
    }

    // ─── Disputes ────────────────────────────────────────────────────
    function testOpenDispute() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        ridep2p.bookRide(rideId, 1);

        vm.prank(rider1);
        ridep2p.openDispute(rideId, "Driver didn't show up");

        (, , string memory reason, bool resolved) = ridep2p.disputes(1);
        assertEq(reason, "Driver didn't show up");
        assertFalse(resolved);
    }

    function testResolveDisputeRefundRiders() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        ridep2p.bookRide(rideId, 1);

        vm.prank(rider1);
        ridep2p.openDispute(rideId, "Issue");

        uint256 r1Bal = usdc.balanceOf(rider1);

        ridep2p.resolveDispute(1, true);

        assertEq(usdc.balanceOf(rider1), r1Bal + PRICE_PER_SEAT);
    }

    function testResolveDisputePayDriver() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        ridep2p.bookRide(rideId, 1);

        vm.prank(rider1);
        ridep2p.openDispute(rideId, "Issue");

        uint256 totalRev = PRICE_PER_SEAT;
        uint256 expectedFee = (totalRev * 300) / 10000;
        uint256 expectedPayout = totalRev - expectedFee;

        ridep2p.resolveDispute(1, false);

        assertEq(usdc.balanceOf(driver), expectedPayout);
    }

    function testResolveDisputeRevertsAlreadyResolved() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        ridep2p.bookRide(rideId, 1);

        vm.prank(rider1);
        ridep2p.openDispute(rideId, "Issue");

        ridep2p.resolveDispute(1, true);

        vm.expectRevert("Already resolved");
        ridep2p.resolveDispute(1, true);
    }

    // ─── Driver Verification ─────────────────────────────────────────
    function testSetDriverVerified() public {
        ridep2p.setDriverVerified(driver, true);
        assertTrue(ridep2p.verifiedDrivers(driver));
    }

    function testSetDriverVerifiedRevertsNotOwner() public {
        vm.prank(driver);
        vm.expectRevert();
        ridep2p.setDriverVerified(driver, true);
    }

    // ─── Ratings ─────────────────────────────────────────────────────
    function testRateDriver() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        ridep2p.bookRide(rideId, 1);

        vm.prank(driver);
        ridep2p.completeRide(rideId);

        vm.prank(rider1);
        ridep2p.rateDriver(rideId, 5);

        (uint256 avg, uint256 count) = ridep2p.getDriverRating(driver);
        assertEq(avg, 5);
        assertEq(count, 1);
    }

    function testRateRider() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        ridep2p.bookRide(rideId, 1);

        vm.prank(driver);
        ridep2p.completeRide(rideId);

        vm.prank(driver);
        ridep2p.rateRider(rideId, rider1, 4);

        (uint256 avg, uint256 count) = ridep2p.getRiderRating(rider1);
        assertEq(avg, 4);
        assertEq(count, 1);
    }

    function testRatingRevertsInvalidRating() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        ridep2p.bookRide(rideId, 1);

        vm.prank(driver);
        ridep2p.completeRide(rideId);

        vm.prank(rider1);
        vm.expectRevert("Rating must be 1-5");
        ridep2p.rateDriver(rideId, 0);
    }

    function testRatingRevertsDoubleRate() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        ridep2p.bookRide(rideId, 1);

        vm.prank(driver);
        ridep2p.completeRide(rideId);

        vm.prank(rider1);
        ridep2p.rateDriver(rideId, 5);

        vm.prank(rider1);
        vm.expectRevert("Already rated");
        ridep2p.rateDriver(rideId, 4);
    }

    // ─── Full Flow ───────────────────────────────────────────────────
    function testFullRideFlow() public {
        vm.prank(driver);
        uint256 rideId = ridep2p.createRide("NYC", "Boston", _futureTime(), PRICE_PER_SEAT, SEATS);

        vm.prank(rider1);
        uint256 b1 = ridep2p.bookRide(rideId, 1);
        vm.prank(rider2);
        ridep2p.bookRide(rideId, 2);

        vm.prank(rider1);
        ridep2p.cancelBooking(b1);

        vm.prank(driver);
        ridep2p.completeRide(rideId);

        vm.prank(rider2);
        ridep2p.rateDriver(rideId, 4);
        vm.prank(driver);
        ridep2p.rateRider(rideId, rider2, 5);

        (uint256 driverAvg,) = ridep2p.getDriverRating(driver);
        assertEq(driverAvg, 4);

        (uint256 riderAvg,) = ridep2p.getRiderRating(rider2);
        assertEq(riderAvg, 5);

        uint256 totalRev = PRICE_PER_SEAT * 2;
        uint256 fee = (totalRev * 300) / 10000;
        uint256 payout = totalRev - fee;
        assertEq(usdc.balanceOf(driver), payout);
        assertEq(usdc.balanceOf(admin), fee);
        assertEq(usdc.balanceOf(address(ridep2p)), 0);
    }
}
