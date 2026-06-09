// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TaskEscrow} from "../src/TaskEscrow.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TaskEscrowTest is Test {
    TaskEscrow public escrow;
    MockUSDC public usdc;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public client = makeAddr("client");
    address public freelancer = makeAddr("freelancer");
    address public freelancer2 = makeAddr("freelancer2");
    address public stranger = makeAddr("stranger");

    uint256 constant JOB_AMOUNT = 1000 * 1e6;
    uint256 constant FEE_BPS = 300;
    uint256 constant EXPECTED_FEE = (JOB_AMOUNT * FEE_BPS) / 10000;
    uint256 constant EXPECTED_PAYOUT = JOB_AMOUNT - EXPECTED_FEE;

    function setUp() public {
        vm.startPrank(owner);
        usdc = new MockUSDC();
        escrow = new TaskEscrow(treasury);
        vm.stopPrank();

        usdc.mint(client, JOB_AMOUNT * 10);
        vm.deal(client, 10 ether);
        vm.deal(freelancer, 10 ether);
        vm.deal(freelancer2, 10 ether);
    }

    function test_CreateJob() public {
        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        uint256 balBefore = usdc.balanceOf(client);
        uint256 jobId = escrow.createJob(IERC20(address(usdc)), JOB_AMOUNT, "Build landing page");

        assertEq(jobId, 0);
        assertEq(usdc.balanceOf(client), balBefore - JOB_AMOUNT);
        assertEq(usdc.balanceOf(address(escrow)), JOB_AMOUNT);

        (address c, address fl, IERC20 t, uint256 amt, string memory desc, TaskEscrow.Status s, uint256 ts) = escrow.jobs(0);
        assertEq(c, client);
        assertEq(amt, JOB_AMOUNT);
        assertEq(desc, "Build landing page");
        assertEq(uint256(s), uint256(TaskEscrow.Status.Open));
        vm.stopPrank();
    }

    function test_CreateJob_EmitsEvent() public {
        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        vm.expectEmit(true, true, false, true);
        emit TaskEscrow.JobCreated(0, client, JOB_AMOUNT, "Build landing page");
        escrow.createJob(IERC20(address(usdc)), JOB_AMOUNT, "Build landing page");
        vm.stopPrank();
    }

    function test_RevertsIf_ZeroAmount() public {
        vm.startPrank(client);
        usdc.approve(address(escrow), 0);
        vm.expectRevert("Amount must be > 0");
        escrow.createJob(IERC20(address(usdc)), 0, "Build landing page");
        vm.stopPrank();
    }

    function test_RevertsIf_EmptyDescription() public {
        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        vm.expectRevert("Description required");
        escrow.createJob(IERC20(address(usdc)), JOB_AMOUNT, "");
        vm.stopPrank();
    }

    function test_RevertsIf_NoApproval() public {
        vm.startPrank(client);
        vm.expectRevert();
        escrow.createJob(IERC20(address(usdc)), JOB_AMOUNT, "Build landing page");
        vm.stopPrank();
    }

    function test_MultipleJobs() public {
        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT * 3);
        escrow.createJob(IERC20(address(usdc)), JOB_AMOUNT, "Job 1");
        escrow.createJob(IERC20(address(usdc)), JOB_AMOUNT, "Job 2");
        escrow.createJob(IERC20(address(usdc)), JOB_AMOUNT, "Job 3");
        assertEq(escrow.jobCount(), 3);
        assertEq(usdc.balanceOf(address(escrow)), JOB_AMOUNT * 3);
        vm.stopPrank();
    }

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
        emit TaskEscrow.JobApplied(jobId, freelancer);
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

    function test_RevertsIf_ApplyNotOpen() public {
        uint256 jobId = _acceptJob();
        vm.prank(freelancer2);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrow.InvalidStatus.selector, TaskEscrow.Status.InProgress));
        escrow.applyToJob(jobId);
    }

    function test_RevertsIf_DoubleApply() public {
        uint256 jobId = _createJob();
        vm.startPrank(freelancer);
        escrow.applyToJob(jobId);
        vm.expectRevert(TaskEscrow.AlreadyApplied.selector);
        escrow.applyToJob(jobId);
        vm.stopPrank();
    }

    function test_RevertsIf_ClientApplies() public {
        uint256 jobId = _createJob();
        vm.prank(client);
        vm.expectRevert(TaskEscrow.AlreadyApplied.selector);
        escrow.applyToJob(jobId);
    }

    function test_AcceptFreelancer() public {
        uint256 jobId = _applyJob();
        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);
        (address c, address fl, IERC20 t, uint256 amt, string memory desc, TaskEscrow.Status s, uint256 ts) = escrow.jobs(jobId);
        assertEq(fl, freelancer);
        assertEq(uint256(s), uint256(TaskEscrow.Status.InProgress));
    }

    function test_AcceptFreelancer_EmitsEvent() public {
        uint256 jobId = _applyJob();
        vm.expectEmit(true, true, false, false);
        emit TaskEscrow.FreelancerAccepted(jobId, freelancer);
        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);
    }

    function test_RevertsIf_AcceptNotClient() public {
        uint256 jobId = _applyJob();
        vm.prank(stranger);
        vm.expectRevert(TaskEscrow.NotClient.selector);
        escrow.acceptFreelancer(jobId, freelancer);
    }

    function test_RevertsIf_AcceptNotOpen() public {
        uint256 jobId = _acceptJob();
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrow.InvalidStatus.selector, TaskEscrow.Status.InProgress));
        escrow.acceptFreelancer(jobId, freelancer2);
    }

    function test_RevertsIf_NotInApplicants() public {
        uint256 jobId = _createJob();
        vm.prank(client);
        vm.expectRevert("Freelancer not in applicants");
        escrow.acceptFreelancer(jobId, freelancer);
    }

    function test_CompleteJob() public {
        uint256 jobId = _acceptJob();
        uint256 flBefore = usdc.balanceOf(freelancer);
        uint256 tBefore = usdc.balanceOf(treasury);

        vm.prank(client);
        escrow.completeJob(jobId);

        assertEq(usdc.balanceOf(freelancer), flBefore + EXPECTED_PAYOUT);
        assertEq(usdc.balanceOf(treasury), tBefore + EXPECTED_FEE);
        assertEq(usdc.balanceOf(address(escrow)), 0);

        (address c, address fl, IERC20 t, uint256 amt, string memory desc, TaskEscrow.Status s, uint256 ts) = escrow.jobs(jobId);
        assertEq(uint256(s), uint256(TaskEscrow.Status.Completed));
    }

    function test_CompleteJob_EmitsEvent() public {
        uint256 jobId = _acceptJob();
        vm.expectEmit(true, true, false, true);
        emit TaskEscrow.JobCompleted(jobId, freelancer, EXPECTED_PAYOUT, EXPECTED_FEE);
        vm.prank(client);
        escrow.completeJob(jobId);
    }

    function test_RevertsIf_CompleteNotClient() public {
        uint256 jobId = _acceptJob();
        vm.prank(stranger);
        vm.expectRevert(TaskEscrow.NotClient.selector);
        escrow.completeJob(jobId);
    }

    function test_RevertsIf_CompleteNotInProgress() public {
        uint256 jobId = _completeJob();
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrow.InvalidStatus.selector, TaskEscrow.Status.Completed));
        escrow.completeJob(jobId);
    }

    function test_CancelJob() public {
        uint256 clientBefore = usdc.balanceOf(client);
        uint256 jobId = _createJob();

        vm.prank(client);
        escrow.cancelJob(jobId);

        assertEq(usdc.balanceOf(client), clientBefore);
        assertEq(usdc.balanceOf(address(escrow)), 0);

        (address c, address fl, IERC20 t, uint256 amt, string memory desc, TaskEscrow.Status s, uint256 ts) = escrow.jobs(jobId);
        assertEq(uint256(s), uint256(TaskEscrow.Status.Cancelled));
    }

    function test_CancelJob_EmitsEvent() public {
        uint256 jobId = _createJob();
        vm.expectEmit(true, true, false, false);
        emit TaskEscrow.JobCancelled(jobId, client);
        vm.prank(client);
        escrow.cancelJob(jobId);
    }

    function test_RevertsIf_CancelNotClient() public {
        uint256 jobId = _createJob();
        vm.prank(stranger);
        vm.expectRevert(TaskEscrow.NotClient.selector);
        escrow.cancelJob(jobId);
    }

    function test_RevertsIf_CancelInProgress() public {
        uint256 jobId = _acceptJob();
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrow.InvalidStatus.selector, TaskEscrow.Status.InProgress));
        escrow.cancelJob(jobId);
    }

    function test_DisputeByClient() public {
        uint256 jobId = _acceptJob();
        vm.prank(client);
        escrow.disputeJob(jobId);
        (address c, address fl, IERC20 t, uint256 amt, string memory desc, TaskEscrow.Status s, uint256 ts) = escrow.jobs(jobId);
        assertEq(uint256(s), uint256(TaskEscrow.Status.Disputed));
    }

    function test_DisputeByFreelancer() public {
        uint256 jobId = _acceptJob();
        vm.prank(freelancer);
        escrow.disputeJob(jobId);
        (address c, address fl, IERC20 t, uint256 amt, string memory desc, TaskEscrow.Status s, uint256 ts) = escrow.jobs(jobId);
        assertEq(uint256(s), uint256(TaskEscrow.Status.Disputed));
    }

    function test_RevertsIf_DisputeStranger() public {
        uint256 jobId = _acceptJob();
        vm.prank(stranger);
        vm.expectRevert(TaskEscrow.NotClientOrFreelancer.selector);
        escrow.disputeJob(jobId);
    }

    function test_RevertsIf_DisputeNotInProgress() public {
        uint256 jobId = _createJob();
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(TaskEscrow.InvalidStatus.selector, TaskEscrow.Status.Open));
        escrow.disputeJob(jobId);
    }

    function test_ResolveDispute_PayFreelancer() public {
        uint256 jobId = _disputeJob();
        uint256 flBefore = usdc.balanceOf(freelancer);
        vm.prank(owner);
        escrow.resolveDispute(jobId, true);
        assertEq(usdc.balanceOf(freelancer), flBefore + EXPECTED_PAYOUT);
        assertEq(usdc.balanceOf(treasury), EXPECTED_FEE);
    }

    function test_ResolveDispute_RefundClient() public {
        uint256 jobId = _disputeJob();
        uint256 clientBefore = usdc.balanceOf(client);
        vm.prank(owner);
        escrow.resolveDispute(jobId, false);
        assertApproxEqAbs(usdc.balanceOf(client), clientBefore + JOB_AMOUNT, 1);
    }

    function test_RevertsIf_ResolveNotOwner() public {
        uint256 jobId = _disputeJob();
        vm.prank(stranger);
        vm.expectRevert();
        escrow.resolveDispute(jobId, true);
    }

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
        emit TaskEscrow.PlatformFeeUpdated(500);
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

    function test_CompleteJob_WithCustomFee() public {
        uint256 jobId = _acceptJob();
        vm.prank(owner);
        escrow.setPlatformFee(500);

        uint256 expFee = (JOB_AMOUNT * 500) / 10000;
        uint256 expPayout = JOB_AMOUNT - expFee;

        uint256 flBefore = usdc.balanceOf(freelancer);
        uint256 tBefore = usdc.balanceOf(treasury);

        vm.prank(client);
        escrow.completeJob(jobId);

        assertEq(usdc.balanceOf(freelancer), flBefore + expPayout);
        assertEq(usdc.balanceOf(treasury), tBefore + expFee);
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
        uint256 jobId = _acceptJob();
        uint256 strangerBefore = usdc.balanceOf(stranger);
        vm.prank(client);
        escrow.completeJob(jobId);
        assertEq(usdc.balanceOf(stranger), strangerBefore + EXPECTED_FEE);
    }

    // ═══════════════ HELPERS ═══════════════

    function _createJob() internal returns (uint256) {
        vm.startPrank(client);
        usdc.approve(address(escrow), JOB_AMOUNT);
        uint256 jobId = escrow.createJob(IERC20(address(usdc)), JOB_AMOUNT, "Build landing page");
        vm.stopPrank();
        return jobId;
    }

    function _applyJob() internal returns (uint256) {
        uint256 jobId = _createJob();
        vm.prank(freelancer);
        escrow.applyToJob(jobId);
        return jobId;
    }

    function _acceptJob() internal returns (uint256) {
        uint256 jobId = _applyJob();
        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);
        return jobId;
    }

    function _completeJob() internal returns (uint256) {
        uint256 jobId = _acceptJob();
        vm.prank(client);
        escrow.completeJob(jobId);
        return jobId;
    }

    function _disputeJob() internal returns (uint256) {
        uint256 jobId = _acceptJob();
        vm.prank(client);
        escrow.disputeJob(jobId);
        return jobId;
    }
}
