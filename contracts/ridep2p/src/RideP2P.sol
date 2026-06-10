// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RideP2P is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ────────────────────────────────────────────────────
    uint256 public constant PLATFORM_FEE_BPS = 300; // 3%
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ─── Enums ───────────────────────────────────────────────────────
    enum RideStatus { Active, Completed, Cancelled, Disputed }
    enum BookingStatus { Booked, Refunded, PaidOut }

    // ─── Structs ─────────────────────────────────────────────────────
    struct Ride {
        address driver;
        string origin;
        string destination;
        uint256 departureTime;
        uint256 pricePerSeat;
        uint256 totalSeats;
        uint256 bookedSeats;
        RideStatus status;
    }

    struct Booking {
        address rider;
        uint256 rideId;
        uint256 seats;
        uint256 amount;
        BookingStatus status;
    }

    struct Dispute {
        uint256 rideId;
        address initiator;
        string reason;
        bool resolved;
    }

    // ─── State ───────────────────────────────────────────────────────
    IERC20 public immutable usdc;
    uint256 public rideCounter;
    uint256 public bookingCounter;
    uint256 public disputeCounter;

    // rideId => Ride
    mapping(uint256 => Ride) public rides;
    // bookingId => Booking
    mapping(uint256 => Booking) public bookings;
    // disputeId => Dispute
    mapping(uint256 => Dispute) public disputes;
    // rideId => bookingId[]
    mapping(uint256 => uint256[]) public rideBookings;
    // address => verified
    mapping(address => bool) public verifiedDrivers;
    // address => cumulative rating points
    mapping(address => uint256) public driverRatingPoints;
    // address => number of ratings received
    mapping(address => uint256) public driverRatingCount;
    // address => rider rating points
    mapping(address => uint256) public riderRatingPoints;
    // address => rider rating count
    mapping(address => uint256) public riderRatingCount;
    // rideId => rating left by driver for rider (maps rider addr => rated bool)
    mapping(uint256 => mapping(address => bool)) public riderRatedForRide;
    // rideId => driver has been rated
    mapping(uint256 => mapping(address => bool)) public driverRatedForRide;

    // ─── Events ──────────────────────────────────────────────────────
    event RideCreated(uint256 indexed rideId, address indexed driver, string origin, string destination, uint256 departureTime, uint256 pricePerSeat, uint256 totalSeats);
    event RideBooked(uint256 indexed bookingId, uint256 indexed rideId, address indexed rider, uint256 seats, uint256 amount);
    event RideCompleted(uint256 indexed rideId, uint256 totalPayout, uint256 platformFee);
    event RideCancelledByDriver(uint256 indexed rideId);
    event BookingCancelled(uint256 indexed bookingId, uint256 indexed rideId, address indexed rider, uint256 refundAmount);
    event DisputeOpened(uint256 indexed disputeId, uint256 indexed rideId, address indexed initiator);
    event DisputeResolved(uint256 indexed disputeId, uint256 indexed rideId, bool refundRiders);
    event DriverVerified(address indexed driver, bool verified);
    event RatingGiven(address indexed ratee, uint8 rating);

    // ─── Modifiers ───────────────────────────────────────────────────
    modifier onlyDriver(uint256 rideId) {
        require(rides[rideId].driver == msg.sender, "Not the driver");
        _;
    }

    modifier rideIsActive(uint256 rideId) {
        require(rides[rideId].status == RideStatus.Active, "Ride not active");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(address _usdc) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC address");
        usdc = IERC20(_usdc);
    }

    // ─── Driver: Post a ride ─────────────────────────────────────────
    function createRide(
        string calldata origin,
        string calldata destination,
        uint256 departureTime,
        uint256 pricePerSeat,
        uint256 totalSeats
    ) external returns (uint256) {
        require(departureTime > block.timestamp, "Departure must be future");
        require(pricePerSeat > 0, "Price must be > 0");
        require(totalSeats > 0, "Seats must be > 0");

        rideCounter++;
        uint256 rideId = rideCounter;

        rides[rideId] = Ride({
            driver: msg.sender,
            origin: origin,
            destination: destination,
            departureTime: departureTime,
            pricePerSeat: pricePerSeat,
            totalSeats: totalSeats,
            bookedSeats: 0,
            status: RideStatus.Active
        });

        emit RideCreated(rideId, msg.sender, origin, destination, departureTime, pricePerSeat, totalSeats);
        return rideId;
    }

    // ─── Rider: Book a ride ──────────────────────────────────────────
    function bookRide(uint256 rideId, uint256 seats) external returns (uint256) {
        Ride storage ride = rides[rideId];
        require(ride.status == RideStatus.Active, "Ride not active");
        require(ride.driver != msg.sender, "Driver cannot book own ride");
        require(block.timestamp < ride.departureTime, "Ride already departed");
        require(ride.bookedSeats + seats <= ride.totalSeats, "Not enough seats");
        require(seats > 0, "Must book >= 1 seat");

        uint256 totalCost = ride.pricePerSeat * seats;

        // Transfer USDC from rider to contract (escrow)
        usdc.safeTransferFrom(msg.sender, address(this), totalCost);

        ride.bookedSeats += seats;

        bookingCounter++;
        uint256 bookingId = bookingCounter;

        bookings[bookingId] = Booking({
            rider: msg.sender,
            rideId: rideId,
            seats: seats,
            amount: totalCost,
            status: BookingStatus.Booked
        });

        rideBookings[rideId].push(bookingId);

        emit RideBooked(bookingId, rideId, msg.sender, seats, totalCost);
        return bookingId;
    }

    // ─── Driver: Complete ride (releases escrow) ─────────────────────
    function completeRide(uint256 rideId) external onlyDriver(rideId) rideIsActive(rideId) nonReentrant {
        Ride storage ride = rides[rideId];
        require(ride.bookedSeats > 0, "No bookings");
        require(block.timestamp >= ride.departureTime, "Too early");

        ride.status = RideStatus.Completed;

        // Collect all booking amounts
        uint256 totalRevenue = 0;
        uint256[] storage bookingIds = rideBookings[rideId];
        for (uint256 i = 0; i < bookingIds.length; i++) {
            Booking storage b = bookings[bookingIds[i]];
            if (b.status == BookingStatus.Booked) {
                totalRevenue += b.amount;
                b.status = BookingStatus.PaidOut;
            }
        }

        uint256 platformFee = (totalRevenue * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 driverPayout = totalRevenue - platformFee;

        if (platformFee > 0) {
            usdc.safeTransfer(owner(), platformFee);
        }
        if (driverPayout > 0) {
            usdc.safeTransfer(ride.driver, driverPayout);
        }

        emit RideCompleted(rideId, driverPayout, platformFee);
    }

    // ─── Rider: Cancel booking (before departure) ────────────────────
    function cancelBooking(uint256 bookingId) external nonReentrant {
        Booking storage b = bookings[bookingId];
        require(b.rider == msg.sender, "Not the rider");
        require(b.status == BookingStatus.Booked, "Not bookable");
        require(block.timestamp < rides[b.rideId].departureTime, "Already departed");

        b.status = BookingStatus.Refunded;

        // Update ride booked seats
        rides[b.rideId].bookedSeats -= b.seats;

        // Refund rider
        usdc.safeTransfer(msg.sender, b.amount);

        emit BookingCancelled(bookingId, b.rideId, msg.sender, b.amount);
    }

    // ─── Driver: Cancel ride (all riders get refunds) ────────────────
    function driverCancelRide(uint256 rideId) external onlyDriver(rideId) rideIsActive(rideId) nonReentrant {
        Ride storage ride = rides[rideId];
        ride.status = RideStatus.Cancelled;

        uint256[] storage bookingIds = rideBookings[rideId];
        for (uint256 i = 0; i < bookingIds.length; i++) {
            Booking storage b = bookings[bookingIds[i]];
            if (b.status == BookingStatus.Booked) {
                b.status = BookingStatus.Refunded;
                usdc.safeTransfer(b.rider, b.amount);
            }
        }

        emit RideCancelledByDriver(rideId);
    }

    // ─── Dispute ─────────────────────────────────────────────────────
    function openDispute(uint256 rideId, string calldata reason) external {
        Ride storage ride = rides[rideId];
        require(
            ride.status == RideStatus.Completed ||
            (ride.status == RideStatus.Active && block.timestamp >= ride.departureTime),
            "Invalid ride status"
        );

        // Only driver or a rider who booked can dispute
        if (msg.sender == ride.driver) {
            // ok
        } else {
            bool isRider = false;
            uint256[] storage bookingIds = rideBookings[rideId];
            for (uint256 i = 0; i < bookingIds.length; i++) {
                if (bookings[bookingIds[i]].rider == msg.sender) {
                    isRider = true;
                    break;
                }
            }
            require(isRider, "Not a participant");
        }

        ride.status = RideStatus.Disputed;

        disputeCounter++;
        disputes[disputeCounter] = Dispute({
            rideId: rideId,
            initiator: msg.sender,
            reason: reason,
            resolved: false
        });

        emit DisputeOpened(disputeCounter, rideId, msg.sender);
    }

    // ─── Admin: Resolve dispute ──────────────────────────────────────
    function resolveDispute(uint256 disputeId, bool refundRiders) external onlyOwner nonReentrant {
        Dispute storage d = disputes[disputeId];
        require(!d.resolved, "Already resolved");
        d.resolved = true;

        Ride storage ride = rides[d.rideId];

        if (refundRiders) {
            // Refund all riders
            uint256[] storage bookingIds = rideBookings[d.rideId];
            for (uint256 i = 0; i < bookingIds.length; i++) {
                Booking storage b = bookings[bookingIds[i]];
                if (b.status == BookingStatus.Booked) {
                    b.status = BookingStatus.Refunded;
                    usdc.safeTransfer(b.rider, b.amount);
                }
            }
            ride.status = RideStatus.Cancelled;
        } else {
            // Pay driver (same as completeRide logic)
            uint256 totalRevenue = 0;
            uint256[] storage bookingIds = rideBookings[d.rideId];
            for (uint256 i = 0; i < bookingIds.length; i++) {
                Booking storage b = bookings[bookingIds[i]];
                if (b.status == BookingStatus.Booked) {
                    totalRevenue += b.amount;
                    b.status = BookingStatus.PaidOut;
                }
            }
            uint256 platformFee = (totalRevenue * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
            uint256 driverPayout = totalRevenue - platformFee;
            if (platformFee > 0) {
                usdc.safeTransfer(owner(), platformFee);
            }
            if (driverPayout > 0) {
                usdc.safeTransfer(ride.driver, driverPayout);
            }
            ride.status = RideStatus.Completed;
        }

        emit DisputeResolved(disputeId, d.rideId, refundRiders);
    }

    // ─── Admin: Verify driver ────────────────────────────────────────
    function setDriverVerified(address driver, bool verified) external onlyOwner {
        verifiedDrivers[driver] = verified;
        emit DriverVerified(driver, verified);
    }

    // ─── Rating ──────────────────────────────────────────────────────
    function rateDriver(uint256 rideId, uint8 rating) external {
        require(rating >= 1 && rating <= 5, "Rating must be 1-5");
        Ride storage ride = rides[rideId];
        require(ride.status == RideStatus.Completed, "Ride not completed");
        require(!driverRatedForRide[rideId][msg.sender], "Already rated");

        // Verify caller is a rider of this ride
        bool isRider = false;
        uint256[] storage bookingIds = rideBookings[rideId];
        for (uint256 i = 0; i < bookingIds.length; i++) {
            if (bookings[bookingIds[i]].rider == msg.sender) {
                isRider = true;
                break;
            }
        }
        require(isRider, "Not a rider of this ride");

        driverRatedForRide[rideId][msg.sender] = true;
        driverRatingPoints[ride.driver] += rating;
        driverRatingCount[ride.driver]++;

        emit RatingGiven(ride.driver, rating);
    }

    function rateRider(uint256 rideId, address rider, uint8 rating) external {
        require(rating >= 1 && rating <= 5, "Rating must be 1-5");
        Ride storage ride = rides[rideId];
        require(ride.status == RideStatus.Completed, "Ride not completed");
        require(msg.sender == ride.driver, "Only driver can rate riders");
        require(!riderRatedForRide[rideId][rider], "Already rated");

        // Verify the rider actually booked this ride
        bool isRider = false;
        uint256[] storage bookingIds = rideBookings[rideId];
        for (uint256 i = 0; i < bookingIds.length; i++) {
            if (bookings[bookingIds[i]].rider == rider) {
                isRider = true;
                break;
            }
        }
        require(isRider, "Not a rider of this ride");

        riderRatedForRide[rideId][rider] = true;
        riderRatingPoints[rider] += rating;
        riderRatingCount[rider]++;

        emit RatingGiven(rider, rating);
    }

    // ─── View helpers ────────────────────────────────────────────────
    function getDriverRating(address driver) external view returns (uint256 avgRating, uint256 count) {
        count = driverRatingCount[driver];
        if (count == 0) return (0, 0);
        avgRating = driverRatingPoints[driver] / count;
    }

    function getRiderRating(address rider) external view returns (uint256 avgRating, uint256 count) {
        count = riderRatingCount[rider];
        if (count == 0) return (0, 0);
        avgRating = riderRatingPoints[rider] / count;
    }

    function getRideBookings(uint256 rideId) external view returns (uint256[] memory) {
        return rideBookings[rideId];
    }
}
