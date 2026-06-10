// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TaskEscrowV2} from "../src/TaskEscrowV2.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TaskEscrowV2Test is Test {
    TaskEscrowV2 public escrow;
    MockUSDC public usdc;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public client = makeAddr("client");
    address public freelancer = makeAddr("freelancer");
    address public freelancer2 = makeAddr("freelancer2");
    address public stranger = makeAddr("stranger");

    // Jury members (5 slots)
    address public juror1 = makeAddr("juror1");
    address public juror2 = makeAddr("juror2");
    address public juror3 = makeAddr("juror3");
    address public juror4 = makeAddr("juror4");
    address public juror5 = makeAddr("juror5");

    uint256 constant MS_AMOUNT_1 = 400 * 1e6;
    uint256 constant MS_AMOUNT_2 = 600 * 1e6;
    uint256 constant JOB_AMOUNT = MS_AMOUNT_1 + MS_AMOUNT_2; // 1000 USDC
    uint256 constant FEE_BPS = 300;
    uint256 constant DEADLINE = 30 days;

    function setUp() public {
        vm.startPrank(owner);
        usdc = new MockUSDC("USD Coin", "USDC", 6);
        escrow = new TaskEscrowV2(treasury);
        // Set up jury
        address[5] memory jurors;
        jurors[0] = juror1;
        jurors[1] = juror2;
        jurors[2] = juror3;
        jurors[3] = juror4;
        jurors[4] = juror5;
        escrow.setJury(jurors);
        vm.stopPrank();

        usdc.mint(client, JOB_AMOUNT * 100);
        usdc.mint(freelancer, JOB_AMOUNT * 100);
        usdc.mint(freelancer2, JOB_AMOUNT * 100);

        vm.deal(client, 10 ether);
        vm.deal(freelancer, 10 ether);
        vm.deal(freelancer2, 10 ether);
        vm.deal(stranger, 10 ether);
    }

    // ═══════════════════════════════════════════════════════════
    // 1. JOB CREATION WITH DEADLINES
    // ═══════════════════════════════════════════════════════════

    function test_CreateJob() public {
        uint256 deadline = block.timestamp + DEADLINE;
        TaskEscrowV2.MilestoneDesc[] memory mss = _makeMilestones();

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        uint256 balBefore = usdc.balanceOf(client);
        uint256 jobId = escrow.createJob(
            IERC20(address(usdc)),
            "Build landing page",
            "Development",
            deadline,
            mss
        );
        vm.stopPrank();

        assertEq(jobId, 0);
        assertEq(usdc.balanceOf(client), balBefore - JOB_AMOUNT);
        assertEq(usdc.balanceOf(address(escrow)), JOB_AMOUNT);

        (
            address c,
            address fl,
            ,
            uint256 amt,
            string memory desc,
            string memory cat,
            TaskEscrowV2.Status s,
            ,
            uint256 dl,
            uint256 msCount
        ) = escrow.getJob(0);
        assertEq(c, client);
        assertEq(fl, address(0));
        assertEq(amt, JOB_AMOUNT);
        assertEq(desc, "Build landing page");
        assertEq(cat, "Development");
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Open));
        assertEq(dl, deadline);
        assertEq(msCount, 2);
    }

    function test_CreateJob_EmitsEvent() public {
        uint256 deadline = block.timestamp + DEADLINE;
        TaskEscrowV2.MilestoneDesc[] memory mss = _makeMilestones();

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        vm.expectEmit(true, true, false, true);
        emit TaskEscrowV2.JobCreated(0, client, JOB_AMOUNT, "Build landing page", "Development", deadline);
        escrow.createJob(
            IERC20(address(usdc)),
            "Build landing page",
            "Development",
            deadline,
            mss
        );
        vm.stopPrank();
    }

    function test_RevertsIf_ZeroAmount() public {
        uint256 deadline = block.timestamp + DEADLINE;
        TaskEscrowV2.MilestoneDesc[] memory mss = new TaskEscrowV2.MilestoneDesc[](1);
        mss[0] = TaskEscrowV2.MilestoneDesc({description: "Zero", amount: 0});

        vm.startPrank(client);
        vm.expectRevert(TaskEscrowV2.AmountMustBePositive.selector);
        escrow.createJob(
            IERC20(address(usdc)),
            "Build landing page",
            "Development",
            deadline,
            mss
        );
        vm.stopPrank();
    }

    function test_RevertsIf_EmptyDescription() public {
        uint256 deadline = block.timestamp + DEADLINE;
        TaskEscrowV2.MilestoneDesc[] memory mss = _makeMilestones();

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        vm.expectRevert(TaskEscrowV2.DescriptionRequired.selector);
        escrow.createJob(
            IERC20(address(usdc)),
            "",
            "Development",
            deadline,
            mss
        );
        vm.stopPrank();
    }

    function test_RevertsIf_PastDeadline() public {
        TaskEscrowV2.MilestoneDesc[] memory mss = _makeMilestones();

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        vm.expectRevert(TaskEscrowV2.DeadlineMustBeFuture.selector);
        escrow.createJob(
            IERC20(address(usdc)),
            "Build landing page",
            "Development",
            block.timestamp,
            mss
        );
        vm.stopPrank();
    }

    function test_RevertsIf_NoMilestones() public {
        uint256 deadline = block.timestamp + DEADLINE;
        TaskEscrowV2.MilestoneDesc[] memory mss = new TaskEscrowV2.MilestoneDesc[](0);

        vm.startPrank(client);
        vm.expectRevert(TaskEscrowV2.MilestonesRequired.selector);
        escrow.createJob(
            IERC20(address(usdc)),
            "Build landing page",
            "Development",
            deadline,
            mss
        );
        vm.stopPrank();
    }

    function test_RevertsIf_NoApproval() public {
        uint256 deadline = block.timestamp + DEADLINE;
        TaskEscrowV2.MilestoneDesc[] memory mss = _makeMilestones();

        vm.startPrank(client);
        vm.expectRevert();
        escrow.createJob(
            IERC20(address(usdc)),
            "Build landing page",
            "Development",
            deadline,
            mss
        );
        vm.stopPrank();
    }

    function test_MultipleJobs() public {
        uint256 deadline = block.timestamp + DEADLINE;
        TaskEscrowV2.MilestoneDesc[] memory mss = _makeMilestones();

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT * 3);
        escrow.createJob(IERC20(address(usdc)), "Job 1", "Development", deadline, mss);
        escrow.createJob(IERC20(address(usdc)), "Job 2", "Design", deadline, mss);
        escrow.createJob(IERC20(address(usdc)), "Job 3", "Writing", deadline, mss);
        assertEq(escrow.jobCount(), 3);
        assertEq(usdc.balanceOf(address(escrow)), JOB_AMOUNT * 3);
        vm.stopPrank();
    }

    function test_CreateJob_SingleMilestone() public {
        uint256 deadline = block.timestamp + DEADLINE;
        TaskEscrowV2.MilestoneDesc[] memory mss = new TaskEscrowV2.MilestoneDesc[](1);
        mss[0] = TaskEscrowV2.MilestoneDesc({description: "All work", amount: JOB_AMOUNT});

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        uint256 jobId = escrow.createJob(
            IERC20(address(usdc)),
            "Simple job",
            "Consulting",
            deadline,
            mss
        );
        vm.stopPrank();

        assertEq(jobId, 0);
        (, , , , , , , , , uint256 msCount) = escrow.getJob(0);
        assertEq(msCount, 1);
    }

    // ═══════════════════════════════════════════════════════════
    // 2. MILESTONE CREATION AND PAYMENT RELEASE
    // ═══════════════════════════════════════════════════════════

    function test_GetMilestone() public {
        uint256 jobId = _createJob();

        (string memory desc, uint256 amt, TaskEscrowV2.MilestoneStatus ms) = escrow.getMilestone(jobId, 0);
        assertEq(desc, "Design mockups");
        assertEq(amt, MS_AMOUNT_1);
        assertEq(uint256(ms), uint256(TaskEscrowV2.MilestoneStatus.Pending));

        (desc, amt, ms) = escrow.getMilestone(jobId, 1);
        assertEq(desc, "Build frontend");
        assertEq(amt, MS_AMOUNT_2);
        assertEq(uint256(ms), uint256(TaskEscrowV2.MilestoneStatus.Pending));
    }

    function test_ReleaseMilestone() public {
        uint256 jobId = _createAndAcceptJob();

        uint256 flBefore = usdc.balanceOf(freelancer);
        uint256 tBefore = usdc.balanceOf(treasury);

        uint256 msFee = (MS_AMOUNT_1 * FEE_BPS) / 10000;
        uint256 msPayout = MS_AMOUNT_1 - msFee;

        vm.expectEmit(true, true, true, true);
        emit TaskEscrowV2.MilestoneReleased(jobId, 0, freelancer, msPayout, msFee);
        vm.prank(client);
        escrow.releaseMilestone(jobId, 0);

        assertEq(usdc.balanceOf(freelancer), flBefore + msPayout);
        assertEq(usdc.balanceOf(treasury), tBefore + msFee);

        (, , TaskEscrowV2.MilestoneStatus ms) = escrow.getMilestone(jobId, 0);
        assertEq(uint256(ms), uint256(TaskEscrowV2.MilestoneStatus.Released));
    }

    function test_ReleaseAllMilestones_ThenCompleteJob() public {
        uint256 jobId = _createAndAcceptJob();

        vm.startPrank(client);
        escrow.releaseMilestone(jobId, 0);
        escrow.releaseMilestone(jobId, 1);
        escrow.completeJob(jobId);
        vm.stopPrank();

        (, , , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Completed));
    }

    function test_RevertsIf_CompleteJobWithPendingMilestones() public {
        uint256 jobId = _createAndAcceptJob();
        vm.startPrank(client);
        escrow.releaseMilestone(jobId, 0);
        vm.expectRevert("Milestone not released");
        escrow.completeJob(jobId);
        vm.stopPrank();
    }

    function test_RevertsIf_ReleaseMilestoneNotClient() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(stranger);
        vm.expectRevert(TaskEscrowV2.NotClient.selector);
        escrow.releaseMilestone(jobId, 0);
    }

    function test_RevertsIf_ReleaseMilestoneNotInProgress() public {
        uint256 jobId = _createJob();
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrowV2.InvalidStatus.selector, TaskEscrowV2.Status.Open));
        escrow.releaseMilestone(jobId, 0);
    }

    function test_RevertsIf_ReleaseNonexistentMilestone() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(client);
        vm.expectRevert(TaskEscrowV2.InvalidMilestoneIndex.selector);
        escrow.releaseMilestone(jobId, 99);
    }

    function test_RevertsIf_ReleaseMilestoneTwice() public {
        uint256 jobId = _createAndAcceptJob();
        vm.startPrank(client);
        escrow.releaseMilestone(jobId, 0);
        vm.expectRevert(TaskEscrowV2.MilestoneAlreadyProcessed.selector);
        escrow.releaseMilestone(jobId, 0);
        vm.stopPrank();
    }

    function test_MilestoneFeeCalculation_CustomFee() public {
        uint256 jobId = _createAndAcceptJob();

        // Set custom 5% fee
        vm.prank(owner);
        escrow.setPlatformFee(500);

        uint256 flBefore = usdc.balanceOf(freelancer);
        uint256 tBefore = usdc.balanceOf(treasury);

        // Release milestone 1
        uint256 ms1Fee = (MS_AMOUNT_1 * 500) / 10000;
        uint256 ms1Payout = MS_AMOUNT_1 - ms1Fee;
        vm.prank(client);
        escrow.releaseMilestone(jobId, 0);

        assertEq(usdc.balanceOf(freelancer), flBefore + ms1Payout);
        assertEq(usdc.balanceOf(treasury), tBefore + ms1Fee);

        // Release milestone 2
        uint256 ms2Fee = (MS_AMOUNT_2 * 500) / 10000;
        uint256 ms2Payout = MS_AMOUNT_2 - ms2Fee;
        vm.prank(client);
        escrow.releaseMilestone(jobId, 1);

        assertEq(usdc.balanceOf(freelancer), flBefore + ms1Payout + ms2Payout);
        assertEq(usdc.balanceOf(treasury), tBefore + ms1Fee + ms2Fee);
    }

    // ═══════════════════════════════════════════════════════════
    // 3. FREELANCER APPLICATION AND ACCEPTANCE
    // ═══════════════════════════════════════════════════════════

    function test_ApplyToJob() public {
        uint256 jobId = _createJob();
        vm.prank(freelancer);
        escrow.applyToJob(jobId);
        address[] memory apps = escrow.getApplicants(jobId);
        assertEq(apps.length, 1);
        assertEq(apps[0], freelancer);
    }

    function test_ApplyToJob_EmitsEvent() public {
        uint256 jobId = _createJob();
        vm.expectEmit(true, true, false, false);
        emit TaskEscrowV2.ApplicantAdded(jobId, freelancer);
        vm.prank(freelancer);
        escrow.applyToJob(jobId);
    }

    function test_MultipleApplicants() public {
        uint256 jobId = _createJob();
        vm.prank(freelancer);
        escrow.applyToJob(jobId);
        vm.prank(freelancer2);
        escrow.applyToJob(jobId);
        assertEq(escrow.getApplicants(jobId).length, 2);
    }

    function test_AcceptFreelancer() public {
        uint256 jobId = _applyJob();
        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);

        (, address fl, , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(fl, freelancer);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.InProgress));
    }

    function test_AcceptFreelancer_EmitsEvent() public {
        uint256 jobId = _applyJob();
        vm.expectEmit(true, true, false, false);
        emit TaskEscrowV2.FreelancerAccepted(jobId, freelancer);
        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);
    }

    // ═══════════════════════════════════════════════════════════
    // 4. JOB COMPLETION AND REPUTATION TRACKING
    // ═══════════════════════════════════════════════════════════

    function test_CompleteJob() public {
        uint256 jobId = _createAndAcceptJob();
        vm.startPrank(client);
        escrow.releaseMilestone(jobId, 0);
        escrow.releaseMilestone(jobId, 1);
        vm.stopPrank();

        vm.prank(client);
        escrow.completeJob(jobId);

        (, , , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Completed));
    }

    function test_CompleteJob_EmitsEvent() public {
        uint256 jobId = _createAndAcceptJob();
        vm.startPrank(client);
        escrow.releaseMilestone(jobId, 0);
        escrow.releaseMilestone(jobId, 1);
        vm.stopPrank();

        vm.expectEmit(true, true, false, false);
        emit TaskEscrowV2.JobCompleted(jobId, freelancer);
        vm.prank(client);
        escrow.completeJob(jobId);
    }

    function test_CompleteJob_UpdatesReputation() public {
        uint256 jobId = _createAndAcceptJob();
        vm.startPrank(client);
        escrow.releaseMilestone(jobId, 0);
        escrow.releaseMilestone(jobId, 1);
        escrow.completeJob(jobId);
        vm.stopPrank();

        (uint256 completed, uint256 avgRating) = escrow.getReputation(freelancer);
        assertEq(completed, 1);
        assertEq(avgRating, 0); // no rating yet
    }

    function test_ReputationAccumulates() public {
        // Complete job 1
        uint256 jobId1 = _createAndAcceptJob();
        vm.startPrank(client);
        escrow.releaseMilestone(jobId1, 0);
        escrow.releaseMilestone(jobId1, 1);
        escrow.completeJob(jobId1);
        vm.stopPrank();

        // Complete job 2
        uint256 jobId2 = _createJob();
        vm.startPrank(freelancer);
        escrow.applyToJob(jobId2);
        vm.stopPrank();
        vm.startPrank(client);
        escrow.acceptFreelancer(jobId2, freelancer);
        escrow.releaseMilestone(jobId2, 0);
        escrow.releaseMilestone(jobId2, 1);
        escrow.completeJob(jobId2);
        vm.stopPrank();

        (uint256 completed, ) = escrow.getReputation(freelancer);
        assertEq(completed, 2);
    }

    function test_RateFreelancer() public {
        uint256 jobId = _completeJob();

        vm.expectEmit(true, true, false, false);
        emit TaskEscrowV2.FreelancerRated(jobId, freelancer, 5);
        vm.prank(client);
        escrow.rateFreelancer(jobId, 5);

        (, uint256 avgRating) = escrow.getReputation(freelancer);
        // 5 * 100 / 1 = 500
        assertEq(avgRating, 500);
    }

    function test_RateFreelancer_Multiple() public {
        // Job 1
        uint256 jobId1 = _completeJob();
        vm.prank(client);
        escrow.rateFreelancer(jobId1, 4);

        // Job 2
        uint256 jobId2 = _createJob();
        vm.startPrank(freelancer);
        escrow.applyToJob(jobId2);
        vm.stopPrank();
        vm.startPrank(client);
        escrow.acceptFreelancer(jobId2, freelancer);
        escrow.releaseMilestone(jobId2, 0);
        escrow.releaseMilestone(jobId2, 1);
        escrow.completeJob(jobId2);
        escrow.rateFreelancer(jobId2, 5);
        vm.stopPrank();

        (, uint256 avgRating) = escrow.getReputation(freelancer);
        // (4+5) * 100 / 2 = 450
        assertEq(avgRating, 450);
    }

    function test_GetAverageRating_NoRatings() public {
        (, uint256 avgRating) = escrow.getReputation(freelancer);
        assertEq(avgRating, 0);
    }

    function test_RevertsIf_RatingInvalidRange() public {
        uint256 jobId = _completeJob();

        vm.prank(client);
        vm.expectRevert(TaskEscrowV2.InvalidRating.selector);
        escrow.rateFreelancer(jobId, 0);

        vm.prank(client);
        vm.expectRevert(TaskEscrowV2.InvalidRating.selector);
        escrow.rateFreelancer(jobId, 6);
    }

    function test_RevertsIf_RatingJobNotCompleted() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrowV2.InvalidStatus.selector, TaskEscrowV2.Status.InProgress));
        escrow.rateFreelancer(jobId, 5);
    }

    function test_RevertsIf_RatingNotClient() public {
        uint256 jobId = _completeJob();
        vm.prank(stranger);
        vm.expectRevert(TaskEscrowV2.NotClient.selector);
        escrow.rateFreelancer(jobId, 5);
    }

    function test_RevertsIf_DoubleRating() public {
        uint256 jobId = _completeJob();
        vm.startPrank(client);
        escrow.rateFreelancer(jobId, 5);
        vm.expectRevert(TaskEscrowV2.AlreadyRated.selector);
        escrow.rateFreelancer(jobId, 4);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════
    // 5. DEADLINE EXPIRY AND REFUND CLAIMS
    // ═══════════════════════════════════════════════════════════

    function test_ClaimRefund() public {
        uint256 deadline = block.timestamp + 1 days;
        TaskEscrowV2.MilestoneDesc[] memory mss = new TaskEscrowV2.MilestoneDesc[](2);
        mss[0] = TaskEscrowV2.MilestoneDesc({description: "Phase 1", amount: 400 * 1e6});
        mss[1] = TaskEscrowV2.MilestoneDesc({description: "Phase 2", amount: 600 * 1e6});

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        uint256 jobId = escrow.createJob(
            IERC20(address(usdc)),
            "Quick job",
            "Development",
            deadline,
            mss
        );
        vm.stopPrank();

        // Apply and accept
        vm.prank(freelancer);
        escrow.applyToJob(jobId);
        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);

        // Release milestone 1 (partial payment)
        vm.prank(client);
        escrow.releaseMilestone(jobId, 0);

        // Warp past deadline
        vm.warp(deadline + 1);

        uint256 clientBefore = usdc.balanceOf(client);
        vm.prank(client);
        escrow.claimRefund(jobId);

        // Only un-released milestone amount refunded (milestone 1 was already released)
        assertEq(usdc.balanceOf(client), clientBefore + 600 * 1e6);

        (, , , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Cancelled));
    }

    function test_ClaimRefund_EmitsEvent() public {
        uint256 deadline = block.timestamp + 1 days;
        TaskEscrowV2.MilestoneDesc[] memory mss = new TaskEscrowV2.MilestoneDesc[](1);
        mss[0] = TaskEscrowV2.MilestoneDesc({description: "All", amount: JOB_AMOUNT});

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        uint256 jobId = escrow.createJob(
            IERC20(address(usdc)),
            "Quick job",
            "Development",
            deadline,
            mss
        );
        vm.stopPrank();

        vm.prank(freelancer);
        escrow.applyToJob(jobId);
        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);

        vm.warp(deadline + 1);

        vm.expectEmit(true, true, false, false);
        emit TaskEscrowV2.DeadlineRefund(jobId, client, JOB_AMOUNT);
        vm.prank(client);
        escrow.claimRefund(jobId);
    }

    function test_RevertsIf_ClaimRefundBeforeDeadline() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(client);
        vm.expectRevert(TaskEscrowV2.DeadlineNotPassed.selector);
        escrow.claimRefund(jobId);
    }

    function test_RevertsIf_ClaimRefundNotInProgress() public {
        uint256 deadline = block.timestamp + 1 days;
        TaskEscrowV2.MilestoneDesc[] memory mss = new TaskEscrowV2.MilestoneDesc[](1);
        mss[0] = TaskEscrowV2.MilestoneDesc({description: "All", amount: JOB_AMOUNT});

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        uint256 jobId = escrow.createJob(
            IERC20(address(usdc)),
            "Quick job",
            "Development",
            deadline,
            mss
        );
        vm.stopPrank();

        // Job is still Open (no freelancer accepted)
        vm.warp(deadline + 1);
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrowV2.InvalidStatus.selector, TaskEscrowV2.Status.Open));
        escrow.claimRefund(jobId);
    }

    function test_ClaimRefund_AllMilestonesReleased_NoRefund() public {
        uint256 deadline = block.timestamp + 1 days;
        TaskEscrowV2.MilestoneDesc[] memory mss = new TaskEscrowV2.MilestoneDesc[](1);
        mss[0] = TaskEscrowV2.MilestoneDesc({description: "All", amount: JOB_AMOUNT});

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        uint256 jobId = escrow.createJob(
            IERC20(address(usdc)),
            "Quick job",
            "Development",
            deadline,
            mss
        );
        vm.stopPrank();

        vm.prank(freelancer);
        escrow.applyToJob(jobId);
        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);

        // Release the only milestone
        vm.prank(client);
        escrow.releaseMilestone(jobId, 0);

        vm.warp(deadline + 1);

        uint256 clientBefore = usdc.balanceOf(client);
        vm.prank(client);
        escrow.claimRefund(jobId);
        // No refund since all milestones were released
        assertEq(usdc.balanceOf(client), clientBefore);
    }

    // ═══════════════════════════════════════════════════════════
    // 6. MULTI-SIG DISPUTE RESOLUTION (3-of-5)
    // ═══════════════════════════════════════════════════════════

    function test_DisputeByClient() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(client);
        escrow.disputeJob(jobId);
        (, , , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Disputed));
    }

    function test_DisputeByFreelancer() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(freelancer);
        escrow.disputeJob(jobId);
        (, , , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Disputed));
    }

    function test_DisputeJob_EmitsEvent() public {
        uint256 jobId = _createAndAcceptJob();
        vm.expectEmit(true, true, false, false);
        emit TaskEscrowV2.JobDisputed(jobId, client);
        vm.prank(client);
        escrow.disputeJob(jobId);
    }

    function test_RevertsIf_DisputeStranger() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(stranger);
        vm.expectRevert(TaskEscrowV2.NotClientOrFreelancer.selector);
        escrow.disputeJob(jobId);
    }

    function test_RevertsIf_DisputeNotInProgress() public {
        uint256 jobId = _createJob();
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrowV2.InvalidStatus.selector, TaskEscrowV2.Status.Open));
        escrow.disputeJob(jobId);
    }

    function test_VoteDispute_PayFreelancer() public {
        uint256 jobId = _disputeJob();
        uint256 flBefore = usdc.balanceOf(freelancer);

        // 3 jurors vote to pay freelancer
        vm.prank(juror1);
        escrow.voteDispute(jobId, true);
        vm.prank(juror2);
        escrow.voteDispute(jobId, true);

        // Check vote count
        (uint256 forF, uint256 forC) = escrow.getDisputeVotes(jobId);
        assertEq(forF, 2);
        assertEq(forC, 0);

        // Third vote triggers resolution
        vm.prank(juror3);
        escrow.voteDispute(jobId, true);

        (, , , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Completed));

        // Freelancer should have been paid for pending milestones
        uint256 expectedPayout = JOB_AMOUNT - (JOB_AMOUNT * FEE_BPS) / 10000;
        assertEq(usdc.balanceOf(freelancer), flBefore + expectedPayout);
    }

    function test_VoteDispute_RefundClient() public {
        uint256 jobId = _disputeJob();
        uint256 clientBefore = usdc.balanceOf(client);

        vm.prank(juror1);
        escrow.voteDispute(jobId, false);
        vm.prank(juror2);
        escrow.voteDispute(jobId, false);
        vm.prank(juror3);
        escrow.voteDispute(jobId, false);

        (, , , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Cancelled));
        assertEq(usdc.balanceOf(client), clientBefore + JOB_AMOUNT);
    }

    function test_VoteDispute_MixedVotes_FreelancerWins() public {
        uint256 jobId = _disputeJob();

        vm.prank(juror1);
        escrow.voteDispute(jobId, false); // client
        vm.prank(juror2);
        escrow.voteDispute(jobId, true);  // freelancer
        vm.prank(juror3);
        escrow.voteDispute(jobId, true);  // freelancer
        vm.prank(juror4);
        escrow.voteDispute(jobId, true);  // freelancer → triggers

        (, , , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Completed));
    }

    function test_VoteDispute_MixedVotes_ClientWins() public {
        uint256 jobId = _disputeJob();

        vm.prank(juror1);
        escrow.voteDispute(jobId, true);   // freelancer
        vm.prank(juror2);
        escrow.voteDispute(jobId, false);  // client
        vm.prank(juror3);
        escrow.voteDispute(jobId, false);  // client
        vm.prank(juror4);
        escrow.voteDispute(jobId, false);  // client → triggers

        (, , , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Cancelled));
    }

    function test_VoteDispute_EmitsEvents() public {
        uint256 jobId = _disputeJob();

        vm.expectEmit(true, true, false, false);
        emit TaskEscrowV2.DisputeVoteCast(jobId, juror1, true);
        vm.prank(juror1);
        escrow.voteDispute(jobId, true);
    }

    function test_VoteDispute_ResolutionEmitsEvent() public {
        uint256 jobId = _disputeJob();

        vm.prank(juror1);
        escrow.voteDispute(jobId, true);
        vm.prank(juror2);
        escrow.voteDispute(jobId, true);

        vm.expectEmit(true, false, false, false);
        emit TaskEscrowV2.DisputeResolved(jobId, true);
        vm.prank(juror3);
        escrow.voteDispute(jobId, true);
    }

    function test_RevertsIf_VoteNotJuror() public {
        uint256 jobId = _disputeJob();
        vm.prank(stranger);
        vm.expectRevert(TaskEscrowV2.NotJuror.selector);
        escrow.voteDispute(jobId, true);
    }

    function test_RevertsIf_DoubleVote() public {
        uint256 jobId = _disputeJob();
        vm.startPrank(juror1);
        escrow.voteDispute(jobId, true);
        vm.expectRevert(TaskEscrowV2.AlreadyVoted.selector);
        escrow.voteDispute(jobId, true);
        vm.stopPrank();
    }

    function test_RevertsIf_VoteOnNonDisputedJob() public {
        uint256 jobId = _createJob();
        vm.prank(juror1);
        vm.expectRevert(TaskEscrowV2.NotDisputed.selector);
        escrow.voteDispute(jobId, true);
    }

    function test_HasVoted_Mapping() public {
        uint256 jobId = _disputeJob();
        assertFalse(escrow.hasVoted(jobId, juror1));
        vm.prank(juror1);
        escrow.voteDispute(jobId, true);
        assertTrue(escrow.hasVoted(jobId, juror1));
    }

    function test_DisputeFreelancerGetsPaid_ReputationUpdated() public {
        uint256 jobId = _disputeJob();

        vm.prank(juror1);
        escrow.voteDispute(jobId, true);
        vm.prank(juror2);
        escrow.voteDispute(jobId, true);
        vm.prank(juror3);
        escrow.voteDispute(jobId, true);

        (uint256 completed, ) = escrow.getReputation(freelancer);
        assertEq(completed, 1);
    }

    function test_VoteAfterResolution_Reverts() public {
        uint256 jobId = _disputeJob();

        vm.prank(juror1);
        escrow.voteDispute(jobId, true);
        vm.prank(juror2);
        escrow.voteDispute(jobId, true);
        vm.prank(juror3);
        escrow.voteDispute(jobId, true); // resolves

        // 4th juror tries to vote on resolved dispute
        vm.prank(juror4);
        vm.expectRevert(TaskEscrowV2.NotDisputed.selector);
        escrow.voteDispute(jobId, true);
    }

    function test_DisputePartialMilestoneRelease() public {
        // Release one milestone, then dispute
        uint256 jobId = _createAndAcceptJob();
        vm.prank(client);
        escrow.releaseMilestone(jobId, 0);

        vm.prank(client);
        escrow.disputeJob(jobId);

        uint256 flBefore = usdc.balanceOf(freelancer);

        // Freelancer wins → gets remaining milestone(s) paid
        vm.prank(juror1);
        escrow.voteDispute(jobId, true);
        vm.prank(juror2);
        escrow.voteDispute(jobId, true);
        vm.prank(juror3);
        escrow.voteDispute(jobId, true);

        // Only milestone 2 (600 USDC) was pending
        uint256 ms2Fee = (MS_AMOUNT_2 * FEE_BPS) / 10000;
        uint256 ms2Payout = MS_AMOUNT_2 - ms2Fee;
        assertEq(usdc.balanceOf(freelancer), flBefore + ms2Payout);
    }

    function test_DisputePartialMilestoneRelease_ClientWins() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(client);
        escrow.releaseMilestone(jobId, 0); // 400 USDC released

        vm.prank(client);
        escrow.disputeJob(jobId);

        uint256 clientBefore = usdc.balanceOf(client);

        // Client wins → gets remaining milestone(s) refunded
        vm.prank(juror1);
        escrow.voteDispute(jobId, false);
        vm.prank(juror2);
        escrow.voteDispute(jobId, false);
        vm.prank(juror3);
        escrow.voteDispute(jobId, false);

        // Only milestone 2 (600 USDC) was pending → refunded
        assertEq(usdc.balanceOf(client), clientBefore + MS_AMOUNT_2);
    }

    // ═══════════════════════════════════════════════════════════
    // 7. PLATFORM FEE CALCULATIONS
    // ═══════════════════════════════════════════════════════════

    function test_PlatformFeeDefault() public {
        assertEq(escrow.platformFee(), 300);
    }

    function test_SetPlatformFee() public {
        vm.prank(owner);
        escrow.setPlatformFee(500);
        assertEq(escrow.platformFee(), 500);
    }

    function test_SetPlatformFee_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit TaskEscrowV2.PlatformFeeUpdated(500);
        vm.prank(owner);
        escrow.setPlatformFee(500);
    }

    function test_RevertsIf_SetFeeNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        escrow.setPlatformFee(500);
    }

    function test_RevertsIf_FeeTooHigh() public {
        vm.prank(owner);
        vm.expectRevert("Fee too high");
        escrow.setPlatformFee(1001);
    }

    function test_FeeEdgeCases_ZeroFee() public {
        vm.prank(owner);
        escrow.setPlatformFee(0);

        uint256 jobId = _createAndAcceptJob();
        uint256 flBefore = usdc.balanceOf(freelancer);
        uint256 tBefore = usdc.balanceOf(treasury);

        vm.prank(client);
        escrow.releaseMilestone(jobId, 0);

        assertEq(usdc.balanceOf(freelancer), flBefore + MS_AMOUNT_1);
        assertEq(usdc.balanceOf(treasury), tBefore);
    }

    function test_FeeEdgeCases_MaxFee() public {
        vm.prank(owner);
        escrow.setPlatformFee(1000); // 10%

        uint256 jobId = _createAndAcceptJob();
        uint256 expFee = (MS_AMOUNT_1 * 1000) / 10000;
        uint256 expPayout = MS_AMOUNT_1 - expFee;

        uint256 flBefore = usdc.balanceOf(freelancer);
        uint256 tBefore = usdc.balanceOf(treasury);

        vm.prank(client);
        escrow.releaseMilestone(jobId, 0);

        assertEq(usdc.balanceOf(freelancer), flBefore + expPayout);
        assertEq(usdc.balanceOf(treasury), tBefore + expFee);
    }

    // ═══════════════════════════════════════════════════════════
    // 8. CATEGORY-BASED FILTERING
    // ═══════════════════════════════════════════════════════════

    function test_GetJobsByCategory() public {
        uint256 deadline = block.timestamp + DEADLINE;
        TaskEscrowV2.MilestoneDesc[] memory mss = _makeMilestones();

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT * 4);
        escrow.createJob(IERC20(address(usdc)), "Dev 1", "Development", deadline, mss);
        escrow.createJob(IERC20(address(usdc)), "Dev 2", "Development", deadline, mss);
        escrow.createJob(IERC20(address(usdc)), "Design 1", "Design", deadline, mss);
        escrow.createJob(IERC20(address(usdc)), "Write 1", "Writing", deadline, mss);
        vm.stopPrank();

        // Use getJobs pagination and filter by category
        (
            uint256[] memory ids,
            ,
            ,
            ,
            ,
            ,
            string[] memory categories,
            ,
            ,
        ) = escrow.getJobs(0, 4);

        // Count by category
        uint256 devCount = 0;
        uint256 designCount = 0;
        uint256 writeCount = 0;
        for (uint256 i = 0; i < ids.length; i++) {
            if (keccak256(bytes(categories[i])) == keccak256(bytes("Development"))) devCount++;
            if (keccak256(bytes(categories[i])) == keccak256(bytes("Design"))) designCount++;
            if (keccak256(bytes(categories[i])) == keccak256(bytes("Writing"))) writeCount++;
        }
        assertEq(devCount, 2);
        assertEq(designCount, 1);
        assertEq(writeCount, 1);
    }

    // ═══════════════════════════════════════════════════════════
    // 9. PAGINATION
    // ═══════════════════════════════════════════════════════════

    function test_GetJobsPaginated() public {
        uint256 deadline = block.timestamp + DEADLINE;
        TaskEscrowV2.MilestoneDesc[] memory mss = _makeMilestones();

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT * 5);
        for (uint256 i = 0; i < 5; i++) {
            escrow.createJob(
                IERC20(address(usdc)),
                "Job",
                "Development",
                deadline,
                mss
            );
        }
        vm.stopPrank();

        // Get first 2
        (uint256[] memory ids, , , , , , , , , ) = escrow.getJobs(0, 2);
        assertEq(ids.length, 2);
        assertEq(ids[0], 0);
        assertEq(ids[1], 1);

        // Get next 2
        (ids, , , , , , , , , ) = escrow.getJobs(2, 2);
        assertEq(ids.length, 2);
        assertEq(ids[0], 2);
        assertEq(ids[1], 3);

        // Get last 2 (overflows bounds, should clamp)
        (ids, , , , , , , , , ) = escrow.getJobs(4, 2);
        assertEq(ids.length, 1);
        assertEq(ids[0], 4);
    }

    function test_GetJobsPaginated_Empty() public {
        (uint256[] memory ids, , , , , , , , , ) = escrow.getJobs(0, 10);
        assertEq(ids.length, 0);
    }

    function test_GetJobsPaginated_OffsetBeyondLength() public {
        _createJob();
        (uint256[] memory ids, , , , , , , , , ) = escrow.getJobs(5, 10);
        assertEq(ids.length, 0);
    }

    function test_GetJobsPaginated_ZeroLimit() public {
        _createJob();
        (uint256[] memory ids, , , , , , , , , ) = escrow.getJobs(0, 0);
        assertEq(ids.length, 0);
    }

    function test_GetJobsPaginated_FullData() public {
        uint256 deadline = block.timestamp + DEADLINE;
        TaskEscrowV2.MilestoneDesc[] memory mss = _makeMilestones();

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        escrow.createJob(IERC20(address(usdc)), "Test", "Design", deadline, mss);
        vm.stopPrank();

        (
            uint256[] memory ids,
            address[] memory clients,
            address[] memory freelancers,
            IERC20[] memory tokens,
            uint256[] memory amounts,
            string[] memory descriptions,
            string[] memory categories,
            TaskEscrowV2.Status[] memory statuses,
            uint256[] memory createdAts,
            uint256[] memory deadlines
        ) = escrow.getJobs(0, 1);

        assertEq(ids.length, 1);
        assertEq(ids[0], 0);
        assertEq(clients[0], client);
        assertEq(freelancers[0], address(0));
        assertEq(address(tokens[0]), address(usdc));
        assertEq(amounts[0], JOB_AMOUNT);
        assertEq(descriptions[0], "Test");
        assertEq(categories[0], "Design");
        assertEq(uint256(statuses[0]), uint256(TaskEscrowV2.Status.Open));
        assertEq(createdAts[0], block.timestamp);
        assertEq(deadlines[0], deadline);
    }

    function test_GetApplicantsPaginated() public {
        uint256 jobId = _createJob();
        vm.prank(freelancer);
        escrow.applyToJob(jobId);
        vm.prank(freelancer2);
        escrow.applyToJob(jobId);

        address[] memory apps = escrow.getApplicants(jobId);
        assertEq(apps.length, 2);
        assertEq(apps[0], freelancer);
        assertEq(apps[1], freelancer2);
    }

    function test_GetApplicantsPaginated_Empty() public {
        uint256 jobId = _createJob();
        address[] memory apps = escrow.getApplicants(jobId);
        assertEq(apps.length, 0);
    }

    // ═══════════════════════════════════════════════════════════
    // 10. EDGE CASES & AUTHORIZATION
    // ═══════════════════════════════════════════════════════════

    function test_RevertsIf_DoubleApply() public {
        uint256 jobId = _createJob();
        vm.startPrank(freelancer);
        escrow.applyToJob(jobId);
        vm.expectRevert(TaskEscrowV2.AlreadyApplied.selector);
        escrow.applyToJob(jobId);
        vm.stopPrank();
    }

    function test_RevertsIf_ClientApplies() public {
        uint256 jobId = _createJob();
        vm.prank(client);
        vm.expectRevert(TaskEscrowV2.AlreadyApplied.selector);
        escrow.applyToJob(jobId);
    }

    function test_RevertsIf_ApplyNotOpen() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(freelancer2);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrowV2.InvalidStatus.selector, TaskEscrowV2.Status.InProgress));
        escrow.applyToJob(jobId);
    }

    function test_RevertsIf_AcceptNotClient() public {
        uint256 jobId = _applyJob();
        vm.prank(stranger);
        vm.expectRevert(TaskEscrowV2.NotClient.selector);
        escrow.acceptFreelancer(jobId, freelancer);
    }

    function test_RevertsIf_AcceptNotOpen() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrowV2.InvalidStatus.selector, TaskEscrowV2.Status.InProgress));
        escrow.acceptFreelancer(jobId, freelancer2);
    }

    function test_RevertsIf_NotInApplicants() public {
        uint256 jobId = _createJob();
        vm.prank(client);
        vm.expectRevert("Freelancer not in applicants");
        escrow.acceptFreelancer(jobId, freelancer);
    }

    function test_RevertsIf_CompleteNotClient() public {
        uint256 jobId = _createAndAcceptJob();
        vm.startPrank(client);
        escrow.releaseMilestone(jobId, 0);
        escrow.releaseMilestone(jobId, 1);
        vm.stopPrank();

        vm.prank(stranger);
        vm.expectRevert(TaskEscrowV2.NotClient.selector);
        escrow.completeJob(jobId);
    }

    function test_RevertsIf_CompleteNotInProgress() public {
        uint256 jobId = _completeJob();
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrowV2.InvalidStatus.selector, TaskEscrowV2.Status.Completed));
        escrow.completeJob(jobId);
    }

    function test_RevertsIf_CancelNotClient() public {
        uint256 jobId = _createJob();
        vm.prank(stranger);
        vm.expectRevert(TaskEscrowV2.NotClient.selector);
        escrow.cancelJob(jobId);
    }

    function test_RevertsIf_CancelInProgress() public {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrowV2.InvalidStatus.selector, TaskEscrowV2.Status.InProgress));
        escrow.cancelJob(jobId);
    }

    function test_CancelJob() public {
        uint256 clientBefore = usdc.balanceOf(client);
        uint256 jobId = _createJob();

        vm.prank(client);
        escrow.cancelJob(jobId);

        assertEq(usdc.balanceOf(client), clientBefore);
        assertEq(usdc.balanceOf(address(escrow)), 0);

        (, , , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Cancelled));
    }

    function test_CancelJob_EmitsEvent() public {
        uint256 jobId = _createJob();
        vm.expectEmit(true, true, false, false);
        emit TaskEscrowV2.JobCancelled(jobId, client);
        vm.prank(client);
        escrow.cancelJob(jobId);
    }

    function test_JobCount() public {
        assertEq(escrow.jobCount(), 0);
        _createJob();
        assertEq(escrow.jobCount(), 1);
        _createJob();
        assertEq(escrow.jobCount(), 2);
    }

    function test_GetApplicants_Empty() public {
        uint256 jobId = _createJob();
        assertEq(escrow.getApplicants(jobId).length, 0);
    }

    function test_SetTreasury() public {
        vm.prank(owner);
        escrow.setPlatformTreasury(stranger);

        uint256 jobId = _createAndAcceptJob();
        uint256 strangerBefore = usdc.balanceOf(stranger);

        vm.prank(client);
        escrow.releaseMilestone(jobId, 0);

        uint256 msFee = (MS_AMOUNT_1 * FEE_BPS) / 10000;
        assertEq(usdc.balanceOf(stranger), strangerBefore + msFee);
    }

    function test_SetTreasury_RevertsIf_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TaskEscrowV2.ZeroAddress.selector);
        escrow.setPlatformTreasury(address(0));
    }

    // ═══════════════════════════════════════════════════════════
    // JURY MANAGEMENT
    // ═══════════════════════════════════════════════════════════

    function test_IsJuror() public {
        assertTrue(escrow.isJuror(juror1));
        assertTrue(escrow.isJuror(juror5));
        assertFalse(escrow.isJuror(stranger));
    }

    function test_SetJuror() public {
        address newJuror = makeAddr("newJuror");
        vm.prank(owner);
        escrow.setJuror(2, newJuror);
        assertTrue(escrow.isJuror(newJuror));
        assertFalse(escrow.isJuror(juror3)); // replaced
    }

    function test_SetJuror_EmitsEvent() public {
        address newJuror = makeAddr("newJuror");
        vm.expectEmit(true, false, false, false);
        emit TaskEscrowV2.JuryUpdated(2, newJuror);
        vm.prank(owner);
        escrow.setJuror(2, newJuror);
    }

    function test_RevertsIf_SetJurorNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        escrow.setJuror(0, makeAddr("x"));
    }

    function test_RevertsIf_SetJurorZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TaskEscrowV2.ZeroAddress.selector);
        escrow.setJuror(0, address(0));
    }

    function test_RevertsIf_SetJurorSlotOutOfRange() public {
        vm.prank(owner);
        vm.expectRevert("Slot out of range");
        escrow.setJuror(5, makeAddr("x"));
    }

    function test_RevertsIf_SetJurorDuplicate() public {
        vm.prank(owner);
        vm.expectRevert("Duplicate juror");
        escrow.setJuror(0, juror2); // juror2 is already at slot 1
    }

    function test_SetJury() public {
        address[5] memory newJurors;
        newJurors[0] = makeAddr("n1");
        newJurors[1] = makeAddr("n2");
        newJurors[2] = makeAddr("n3");
        newJurors[3] = makeAddr("n4");
        newJurors[4] = makeAddr("n5");

        vm.prank(owner);
        escrow.setJury(newJurors);

        for (uint256 i = 0; i < 5; i++) {
            assertTrue(escrow.isJuror(newJurors[i]));
        }
    }

    function test_RevertsIf_SetJuryZeroAddress() public {
        address[5] memory newJurors;
        newJurors[0] = makeAddr("n1");
        newJurors[1] = makeAddr("n2");
        newJurors[2] = address(0);
        newJurors[3] = makeAddr("n4");
        newJurors[4] = makeAddr("n5");

        vm.prank(owner);
        vm.expectRevert(TaskEscrowV2.ZeroAddress.selector);
        escrow.setJury(newJurors);
    }

    function test_RevertsIf_SetJuryDuplicate() public {
        address dup = makeAddr("dup");
        address[5] memory newJurors;
        newJurors[0] = dup;
        newJurors[1] = makeAddr("n2");
        newJurors[2] = makeAddr("n3");
        newJurors[3] = makeAddr("n4");
        newJurors[4] = dup; // duplicate

        vm.prank(owner);
        vm.expectRevert("Duplicate juror");
        escrow.setJury(newJurors);
    }

    // ═══════════════════════════════════════════════════════════
    // GETJOB VIEW
    // ═══════════════════════════════════════════════════════════

    function test_GetJob() public {
        uint256 deadline = block.timestamp + DEADLINE;
        TaskEscrowV2.MilestoneDesc[] memory mss = _makeMilestones();

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        uint256 jobId = escrow.createJob(
            IERC20(address(usdc)),
            "Test job",
            "Design",
            deadline,
            mss
        );
        vm.stopPrank();

        (
            address c,
            address fl,
            ,
            uint256 amt,
            string memory desc,
            string memory cat,
            TaskEscrowV2.Status s,
            ,
            uint256 dl,
            uint256 msCount
        ) = escrow.getJob(jobId);

        assertEq(c, client);
        assertEq(fl, address(0));
        assertEq(amt, JOB_AMOUNT);
        assertEq(desc, "Test job");
        assertEq(cat, "Design");
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Open));
        assertEq(dl, deadline);
        assertEq(msCount, 2);
    }

    // ═══════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════

    function test_Constructor_RevertsIf_ZeroTreasury() public {
        vm.expectRevert(TaskEscrowV2.ZeroAddress.selector);
        new TaskEscrowV2(address(0));
    }

    // ═══════════════════════════════════════════════════════════
    // INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════

    function test_FullFlow_MilestonesAndCompletion() public {
        uint256 deadline = block.timestamp + DEADLINE;

        // 1. Client creates job with milestones
        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        uint256 jobId = escrow.createJob(
            IERC20(address(usdc)),
            "Website redesign",
            "Design",
            deadline,
            _makeMilestones()
        );
        vm.stopPrank();

        // 2. Freelancer applies and gets accepted
        vm.prank(freelancer);
        escrow.applyToJob(jobId);
        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);

        // 3. Release milestones
        vm.prank(client);
        escrow.releaseMilestone(jobId, 0);
        vm.prank(client);
        escrow.releaseMilestone(jobId, 1);

        // 4. Complete job
        vm.prank(client);
        escrow.completeJob(jobId);

        (, , , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Completed));

        // 5. Rate freelancer
        vm.prank(client);
        escrow.rateFreelancer(jobId, 5);

        (uint256 completed, uint256 avgRating) = escrow.getReputation(freelancer);
        assertEq(completed, 1);
        assertEq(avgRating, 500);
    }

    function test_FullFlow_DisputeAndResolution() public {
        uint256 jobId = _createAndAcceptJob();
        uint256 flBefore = usdc.balanceOf(freelancer);

        // Client disputes
        vm.prank(client);
        escrow.disputeJob(jobId);

        // Jurors vote with mixed outcome
        vm.prank(juror1);
        escrow.voteDispute(jobId, true);
        vm.prank(juror2);
        escrow.voteDispute(jobId, false);
        vm.prank(juror3);
        escrow.voteDispute(jobId, true);
        vm.prank(juror4);
        escrow.voteDispute(jobId, true); // 3rd for freelancer → resolves

        (, , , , , , TaskEscrowV2.Status s, , , ) = escrow.getJob(jobId);
        assertEq(uint256(s), uint256(TaskEscrowV2.Status.Completed));

        uint256 expectedPayout = JOB_AMOUNT - (JOB_AMOUNT * FEE_BPS) / 10000;
        assertEq(usdc.balanceOf(freelancer), flBefore + expectedPayout);
    }

    function test_FullFlow_DeadlineRefund() public {
        uint256 deadline = block.timestamp + 1 days;
        TaskEscrowV2.MilestoneDesc[] memory mss = _makeMilestones();

        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        uint256 jobId = escrow.createJob(
            IERC20(address(usdc)),
            "Rush job",
            "Development",
            deadline,
            mss
        );
        vm.stopPrank();

        vm.prank(freelancer);
        escrow.applyToJob(jobId);
        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);

        // Release one milestone before deadline
        vm.prank(client);
        escrow.releaseMilestone(jobId, 0);

        // Warp past deadline
        vm.warp(deadline + 1);

        uint256 clientBefore = usdc.balanceOf(client);
        vm.prank(client);
        escrow.claimRefund(jobId);

        // Only un-released milestones refunded
        assertEq(usdc.balanceOf(client), clientBefore + MS_AMOUNT_2);
    }

    // ═══════════════ HELPERS ═══════════════

    function _makeMilestones() internal pure returns (TaskEscrowV2.MilestoneDesc[] memory mss) {
        mss = new TaskEscrowV2.MilestoneDesc[](2);
        mss[0] = TaskEscrowV2.MilestoneDesc({description: "Design mockups", amount: MS_AMOUNT_1});
        mss[1] = TaskEscrowV2.MilestoneDesc({description: "Build frontend", amount: MS_AMOUNT_2});
    }

    function _createJob() internal returns (uint256) {
        uint256 deadline = block.timestamp + DEADLINE;
        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        uint256 jobId = escrow.createJob(
            IERC20(address(usdc)),
            "Build landing page",
            "Development",
            deadline,
            _makeMilestones()
        );
        vm.stopPrank();
        return jobId;
    }

    function _applyJob() internal returns (uint256) {
        uint256 jobId = _createJob();
        vm.prank(freelancer);
        escrow.applyToJob(jobId);
        return jobId;
    }

    function _createAndAcceptJob() internal returns (uint256) {
        uint256 jobId = _applyJob();
        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);
        return jobId;
    }

    function _completeJob() internal returns (uint256) {
        uint256 jobId = _createAndAcceptJob();
        vm.startPrank(client);
        escrow.releaseMilestone(jobId, 0);
        escrow.releaseMilestone(jobId, 1);
        escrow.completeJob(jobId);
        vm.stopPrank();
        return jobId;
    }

    function _disputeJob() internal returns (uint256) {
        uint256 jobId = _createAndAcceptJob();
        vm.prank(client);
        escrow.disputeJob(jobId);
        return jobId;
    }
}
