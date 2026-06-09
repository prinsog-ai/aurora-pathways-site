// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TokenVesting} from "../src/TokenVesting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TokenVestingTest is Test {
    TokenVesting public vesting;
    MockToken public token;

    address public owner = address(1);
    address public beneficiary1 = address(2);
    address public beneficiary2 = address(3);
    address public stranger = address(4);

    uint256 constant START_TIME = 1000;
    uint256 constant CLIFF = 30 days;
    uint256 constant DURATION = 365 days;
    uint256 constant AMOUNT = 10_000 ether;

    event ScheduleCreated(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration,
        bool revocable
    );
    event TokensClaimed(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount);
    event ScheduleRevoked(uint256 indexed scheduleId, uint256 unvestedAmount);

    function setUp() public {
        token = new MockToken();

        vm.prank(owner);
        vesting = new TokenVesting(address(token), owner);

        // Give owner tokens for creating schedules
        token.mint(owner, 1_000_000 ether);
        vm.prank(owner);
        token.approve(address(vesting), type(uint256).max);
    }

    // ── Deployment ──────────────────────────────────────────────

    function test_Deploy() public view {
        assertEq(address(vesting.token()), address(token));
        assertEq(vesting.owner(), owner);
        assertEq(vesting.scheduleCount(), 0);
        assertEq(vesting.totalAllocated(), 0);
        assertEq(vesting.totalClaimed(), 0);
    }

    function test_DeployRevertsZeroToken() public {
        vm.expectRevert("Invalid token");
        new TokenVesting(address(0), owner);
    }

    // ── Schedule Creation ──────────────────────────────────────

    function test_CreateSchedule() public {
        vm.warp(START_TIME);
        vm.prank(owner);

        uint256 scheduleId = vesting.createSchedule(
            beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true
        );

        assertEq(scheduleId, 0);
        assertEq(vesting.scheduleCount(), 1);
        assertEq(vesting.totalAllocated(), AMOUNT);

        (address ben, uint256 total, uint256 claimed, uint256 start, uint256 cliff, uint256 vestDuration, bool revocable, bool revoked, uint256 revokedAt) = vesting.schedules(0);
        assertEq(ben, beneficiary1);
        assertEq(total, AMOUNT);
        assertEq(claimed, 0);
        assertEq(start, START_TIME);
        assertEq(cliff, CLIFF);
        assertEq(vestDuration, DURATION);
        assertTrue(revocable);
        assertFalse(revoked);
        assertEq(revokedAt, 0);

        // Tokens should be transferred to vesting contract
        assertEq(token.balanceOf(address(vesting)), AMOUNT);
    }

    function test_CreateScheduleEmitsEvent() public {
        vm.warp(START_TIME);
        vm.prank(owner);

        vm.expectEmit(true, true, false, true);
        emit ScheduleCreated(0, beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);
    }

    function test_CreateScheduleNonRevocable() public {
        vm.warp(START_TIME);
        vm.prank(owner);

        uint256 id = vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, false);
        (,,,,,,bool revocable,,) = vesting.schedules(id);
        assertFalse(revocable);
    }

    function test_CreateMultipleSchedules() public {
        vm.warp(START_TIME);
        vm.startPrank(owner);

        vesting.createSchedule(beneficiary1, 5000 ether, START_TIME, 0, 180 days, true);
        vesting.createSchedule(beneficiary2, 3000 ether, START_TIME + 10, CLIFF, DURATION, false);
        vesting.createSchedule(beneficiary1, 2000 ether, START_TIME, CLIFF, 90 days, true);
        vm.stopPrank();

        assertEq(vesting.scheduleCount(), 3);
        assertEq(vesting.totalAllocated(), 10_000 ether);
    }

    function test_CreateScheduleZeroCliff() public {
        vm.warp(START_TIME);
        vm.prank(owner);

        uint256 id = vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, 0, DURATION, true);
        (,,,,uint256 cliff,,,,) = vesting.schedules(id);
        assertEq(cliff, 0);
    }

    function test_RevertOnZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(TokenVesting.InvalidAmount.selector);
        vesting.createSchedule(beneficiary1, 0, START_TIME, CLIFF, DURATION, true);
    }

    function test_RevertOnZeroDuration() public {
        vm.prank(owner);
        vm.expectRevert(TokenVesting.InvalidDuration.selector);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, 0, true);
    }

    function test_RevertOnZeroBeneficiary() public {
        vm.prank(owner);
        vm.expectRevert(TokenVesting.InvalidAmount.selector);
        vesting.createSchedule(address(0), AMOUNT, START_TIME, CLIFF, DURATION, true);
    }

    function test_NonOwnerCannotCreateSchedule() public {
        vm.prank(stranger);
        vm.expectRevert();
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);
    }

    // ── Vesting Calculation ────────────────────────────────────

    function test_VestedZeroBeforeCliff() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        // Still within cliff
        vm.warp(START_TIME + CLIFF - 1);
        assertEq(vesting.vestedAmount(0), 0);
    }

    function test_VestedAtCliffEnd() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        // Exactly at cliff end
        vm.warp(START_TIME + CLIFF);
        uint256 vested = vesting.vestedAmount(0);
        // Should be ~ (AMOUNT * CLIFF / DURATION)
        uint256 expected = (AMOUNT * CLIFF) / DURATION;
        assertEq(vested, expected);
        assertGt(vested, 0);
    }

    function test_VestedHalfway() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, 0, DURATION, true);

        // 50% through duration
        vm.warp(START_TIME + DURATION / 2);
        uint256 vested = vesting.vestedAmount(0);
        // Allow 1 wei tolerance for integer division
        uint256 expected = AMOUNT / 2;
        assertApproxEqAbs(vested, expected, 1);
    }

    function test_VestedFullyAtDuration() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        // After full duration
        vm.warp(START_TIME + DURATION);
        assertEq(vesting.vestedAmount(0), AMOUNT);
    }

    function test_VestedBeyondDuration() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        // Far beyond duration
        vm.warp(START_TIME + DURATION + 365 days);
        assertEq(vesting.vestedAmount(0), AMOUNT);
    }

    function test_VestedAfterRevoke() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        // Advance to halfway, then revoke
        vm.warp(START_TIME + DURATION / 2);
        vm.prank(owner);
        vesting.revoke(0);

        // Vested should be capped at time of revoke
        uint256 vestedAtRevoke = (AMOUNT * (DURATION / 2)) / DURATION;
        // After revoke, advancing time shouldn't increase vested
        vm.warp(START_TIME + DURATION);
        assertEq(vesting.vestedAmount(0), vestedAtRevoke);
    }

    // ── Claiming ───────────────────────────────────────────────

    function test_ClaimAfterCliff() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        // Advance to cliff
        vm.warp(START_TIME + CLIFF);
        uint256 claimable = vesting.claimableAmount(0);
        assertGt(claimable, 0);

        uint256 balBefore = token.balanceOf(beneficiary1);
        vesting.claim(0);
        uint256 balAfter = token.balanceOf(beneficiary1);

        assertEq(balAfter - balBefore, claimable);
        assertEq(vesting.totalClaimed(), claimable);
    }

    function test_ClaimEmitsEvent() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        vm.warp(START_TIME + CLIFF);
        uint256 amount = vesting.claimableAmount(0);

        vm.expectEmit(true, true, false, true);
        emit TokensClaimed(0, beneficiary1, amount);
        vesting.claim(0);
    }

    function test_ClaimMultipleTimes() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, 0, DURATION, true);

        // Claim at 25%
        vm.warp(START_TIME + DURATION / 4);
        vesting.claim(0);
        uint256 claimed1 = token.balanceOf(beneficiary1);

        // Claim at 75%
        vm.warp(START_TIME + (DURATION * 3) / 4);
        vesting.claim(0);
        uint256 claimed2 = token.balanceOf(beneficiary1) - claimed1;

        // Total should be close to 75% (allow 1 wei)
        uint256 totalClaimed = claimed1 + claimed2;
        uint256 expected = (AMOUNT * 3) / 4;
        assertApproxEqAbs(totalClaimed, expected, 1);
    }

    function test_ClaimFullAmount() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, 0, DURATION, true);

        vm.warp(START_TIME + DURATION);
        vesting.claim(0);
        assertEq(token.balanceOf(beneficiary1), AMOUNT);
        assertEq(vesting.claimableAmount(0), 0);
        assertEq(vesting.totalClaimed(), AMOUNT);
    }

    function test_RevertOnNothingToClaim() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        // Before cliff — no tokens available
        vm.warp(START_TIME + 1);
        vm.expectRevert(TokenVesting.NothingToClaim.selector);
        vesting.claim(0);
    }

    function test_RevertOnClaimAfterClaimed() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, 0, DURATION, true);

        vm.warp(START_TIME + DURATION);
        vesting.claim(0);

        // No more to claim
        vm.expectRevert(TokenVesting.NothingToClaim.selector);
        vesting.claim(0);
    }

    function test_RevertOnClaimRevoked() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        vm.prank(owner);
        vesting.revoke(0);

        vm.expectRevert(abi.encodeWithSelector(TokenVesting.ScheduleRevokedError.selector, 0));
        vesting.claim(0);
    }

    function test_AnyoneCanClaim() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        vm.warp(START_TIME + CLIFF);

        // Stranger triggers claim, beneficiary still receives tokens
        uint256 balBefore = token.balanceOf(beneficiary1);
        vm.prank(stranger);
        vesting.claim(0);
        uint256 balAfter = token.balanceOf(beneficiary1);
        assertGt(balAfter, balBefore);
    }

    // ── Revocation ─────────────────────────────────────────────

    function test_RevokeReturnsUnvestedTokens() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        // Advance to 50%
        vm.warp(START_TIME + DURATION / 2);

        uint256 ownerBalBefore = token.balanceOf(owner);
        vm.prank(owner);
        vesting.revoke(0);
        uint256 ownerBalAfter = token.balanceOf(owner);

        assertGt(ownerBalAfter, ownerBalBefore);
        assertEq(vesting.totalAllocated() + ownerBalAfter - ownerBalBefore, AMOUNT);
    }

    function test_RevokeEmitsEvent() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        vm.warp(START_TIME + DURATION / 2);

        uint256 unvested = AMOUNT - vesting.vestedAmount(0);
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ScheduleRevoked(0, unvested);
        vesting.revoke(0);
    }

    function test_RevokeSetsRevokedFlag() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        vm.prank(owner);
        vesting.revoke(0);

        (,,,,,,,bool revoked,) = vesting.schedules(0);
        assertTrue(revoked);
    }

    function test_CannotRevokeNonRevocable() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, false);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TokenVesting.NotRevocable.selector, 0));
        vesting.revoke(0);
    }

    function test_CannotRevokeTwice() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        vm.prank(owner);
        vesting.revoke(0);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TokenVesting.ScheduleRevokedError.selector, 0));
        vesting.revoke(0);
    }

    function test_NonOwnerCannotRevoke() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        vm.prank(stranger);
        vm.expectRevert();
        vesting.revoke(0);
    }

    // ── Beneficiary Schedule Tracking ──────────────────────────

    function test_BeneficiarySchedules() public {
        vm.warp(START_TIME);
        vm.startPrank(owner);

        vesting.createSchedule(beneficiary1, 1000 ether, START_TIME, CLIFF, DURATION, true);
        vesting.createSchedule(beneficiary1, 2000 ether, START_TIME, CLIFF, DURATION, true);
        vesting.createSchedule(beneficiary2, 3000 ether, START_TIME, CLIFF, DURATION, true);
        vm.stopPrank();

        assertEq(vesting.beneficiaryScheduleCount(beneficiary1), 2);
        assertEq(vesting.beneficiaryScheduleCount(beneficiary2), 1);

        uint256[] memory b1Schedules = vesting.getBeneficiarySchedules(beneficiary1);
        assertEq(b1Schedules[0], 0);
        assertEq(b1Schedules[1], 1);

        uint256[] memory b2Schedules = vesting.getBeneficiarySchedules(beneficiary2);
        assertEq(b2Schedules[0], 2);
    }

    function test_BeneficiaryWithNoSchedules() public {
        assertEq(vesting.beneficiaryScheduleCount(stranger), 0);
        assertEq(vesting.getBeneficiarySchedules(stranger).length, 0);
    }

    // ── Edge Cases ─────────────────────────────────────────────

    function test_ImmediateFullVesting() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        // 0 cliff, 1 second duration — fully vests immediately
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, 0, 1, true);

        vm.warp(START_TIME + 1);
        vesting.claim(0);
        assertEq(token.balanceOf(beneficiary1), AMOUNT);
    }

    function test_RevokeBeforeCliffReturnsAll() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, CLIFF, DURATION, true);

        uint256 vestingBalBefore = token.balanceOf(address(vesting));
        vm.prank(owner);
        vesting.revoke(0);

        // All tokens should return to owner — vesting contract empty
        assertEq(token.balanceOf(address(vesting)), 0);
        assertEq(vesting.totalAllocated(), 0);
        assertEq(vestingBalBefore, AMOUNT); // sanity: vesting held the full amount
    }

    function test_ClaimBetweenPartialClaims() public {
        vm.warp(START_TIME);
        vm.prank(owner);
        vesting.createSchedule(beneficiary1, AMOUNT, START_TIME, 0, DURATION, true);

        // 25% claim
        vm.warp(START_TIME + DURATION / 4);
        vesting.claim(0);
        uint256 firstClaim = token.balanceOf(beneficiary1);

        // 50% claim (should only get the delta)
        vm.warp(START_TIME + DURATION / 2);
        vesting.claim(0);
        uint256 secondClaim = token.balanceOf(beneficiary1) - firstClaim;

        uint256 expected = (AMOUNT / 2) - (AMOUNT / 4);
        assertApproxEqAbs(secondClaim, expected, 1);
    }

    function test_Gas_ManySchedules() public {
        vm.warp(START_TIME);
        vm.startPrank(owner);
        for (uint256 i = 0; i < 20; i++) {
            vesting.createSchedule(address(uint160(i + 10)), 100 ether, START_TIME, 0, DURATION, true);
        }
        vm.stopPrank();
        assertEq(vesting.scheduleCount(), 20);
    }
}