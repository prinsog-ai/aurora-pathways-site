// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TaskEscrowV3} from "../src/TaskEscrowV3.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract TaskEscrowV3Test is Test {
    TaskEscrowV3 public escrow;
    TaskEscrowV3 public escrowImpl;
    MockUSDC public usdc;
    address public treasury = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    address public client;
    address public freelancer;
    address public juror1;
    address public juror2;
    address public juror3;
    address public juror4;
    address public juror5;

    function setUp() public {
        client = makeAddr('client');
        freelancer = makeAddr('freelancer');
        juror1 = makeAddr('juror1');
        juror2 = makeAddr('juror2');
        juror3 = makeAddr('juror3');
        juror4 = makeAddr('juror4');
        juror5 = makeAddr('juror5');
        // Deploy implementation + proxy
        escrowImpl = new TaskEscrowV3();
        bytes memory initData = abi.encodeCall(TaskEscrowV3.initialize, (treasury));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(escrowImpl),
            address(this),  // proxy admin
            initData
        );
        escrow = TaskEscrowV3(address(proxy));

        // Deploy mock token
        usdc = new MockUSDC("Mock USDC", "mUSDC", 6);
        usdc.mint(client, 100e18);
        usdc.mint(address(escrow), 100e18);

        // Setup jury pool
        escrow.addJuror(juror1);
        escrow.addJuror(juror2);
        escrow.addJuror(juror3);
        escrow.addJuror(juror4);
        escrow.addJuror(juror5);

        // Approve escrow
        vm.prank(client);
        usdc.approve(address(escrow), type(uint256).max);
    }

    // ───────────── Proxy & Upgrade Tests ─────────────

    function test_ProxyDeployment() public view {
        assertEq(escrow.platformTreasury(), treasury);
        assertEq(escrow.jobCount(), 0);
        assertEq(escrow.getJurorCount(), 5);
    }

    function test_Upgrade() public {
        // Deploy new implementation
        TaskEscrowV3 newImpl = new TaskEscrowV3();
        escrow.upgradeToAndCall(address(newImpl), "");
        // Verify state preserved
        assertEq(escrow.platformTreasury(), treasury);
        assertEq(escrow.getJurorCount(), 5);
    }

    function test_UpgradeRevertsForNonOwner() public {
        TaskEscrowV3 newImpl = new TaskEscrowV3();
        vm.prank(makeAddr('random'));
        vm.expectRevert();
        escrow.upgradeToAndCall(address(newImpl), "");
    }

    // ───────────── Dynamic Jury Tests ─────────────

    function test_AddJuror() public {
        address newJuror = makeAddr('newJuror');
        escrow.addJuror(newJuror);
        assertTrue(escrow.isJuror(newJuror));
        assertEq(escrow.getJurorCount(), 6);
    }

    function test_RemoveJuror() public {
        escrow.removeJuror(juror5);
        assertFalse(escrow.isJuror(juror5));
        assertEq(escrow.getJurorCount(), 4);
    }



    function test_AddJurorsBatch() public {
        address[] memory newJurors = new address[](3);
        newJurors[0] = makeAddr('aj1');
        newJurors[1] = makeAddr('aj2');
        newJurors[2] = makeAddr('aj3');
        escrow.addJurors(newJurors);
        assertEq(escrow.getJurorCount(), 8);
    }

    function test_SetQuorum() public {
        escrow.setJuryQuorum(5);
        assertEq(escrow.juryQuorum(), 5);
    }

    // ───────────── Batch Operations Tests ─────────────

    function test_BatchCreateJobs() public {
        string[] memory descs = new string[](2);
        descs[0] = "Job 1";
        descs[1] = "Job 2";
        string[] memory cats = new string[](2);
        cats[0] = "dev";
        cats[1] = "design";
        uint256[] memory deadlines = new uint256[](2);
        deadlines[0] = block.timestamp + 7 days;
        deadlines[1] = block.timestamp + 14 days;

        TaskEscrowV3.MilestoneDesc[][] memory milestones = new TaskEscrowV3.MilestoneDesc[][](2);
        milestones[0] = new TaskEscrowV3.MilestoneDesc[](1);
        milestones[0][0] = TaskEscrowV3.MilestoneDesc({description: "M1", amount: 1e18});
        milestones[1] = new TaskEscrowV3.MilestoneDesc[](1);
        milestones[1][0] = TaskEscrowV3.MilestoneDesc({description: "M2", amount: 2e18});

        vm.prank(client);
        uint256[] memory ids = escrow.batchCreateJobs(IERC20(address(usdc)), descs, cats, deadlines, milestones);

        assertEq(ids.length, 2);
        assertEq(escrow.jobCount(), 2);
        assertEq(usdc.balanceOf(address(escrow)), 103e18); // 100 + 3
    }

    function test_BatchReleaseMilestones() public {
        // Create a job with 3 milestones
        TaskEscrowV3.MilestoneDesc[] memory ms = new TaskEscrowV3.MilestoneDesc[](3);
        ms[0] = TaskEscrowV3.MilestoneDesc({description: "M1", amount: 1e18});
        ms[1] = TaskEscrowV3.MilestoneDesc({description: "M2", amount: 2e18});
        ms[2] = TaskEscrowV3.MilestoneDesc({description: "M3", amount: 3e18});

        vm.prank(client);
        uint256 jobId = escrow.createJob(IERC20(address(usdc)), "Test", "dev", block.timestamp + 30 days, ms);

        // Accept freelancer
        vm.prank(freelancer);
        escrow.applyToJob(jobId);
        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);

        // Batch release milestones 0 and 1
        uint256[] memory jobIds = new uint256[](2);
        jobIds[0] = jobId;
        jobIds[1] = jobId;
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;

        vm.prank(client);
        escrow.batchReleaseMilestones(jobIds, indices);

        (, , TaskEscrowV3.MilestoneStatus s0) = escrow.getMilestone(jobId, 0);
        (, , TaskEscrowV3.MilestoneStatus s1) = escrow.getMilestone(jobId, 1);
        assertEq(uint256(s0), uint256(TaskEscrowV3.MilestoneStatus.Released));
        assertEq(uint256(s1), uint256(TaskEscrowV3.MilestoneStatus.Released));
    }

    // ───────────── Dispute with Dynamic Jury ─────────────



    // ───────────── Standard Flow Tests ─────────────

    function test_FullJobLifecycle() public {
        TaskEscrowV3.MilestoneDesc[] memory ms = new TaskEscrowV3.MilestoneDesc[](2);
        ms[0] = TaskEscrowV3.MilestoneDesc({description: "Design", amount: 3e18});
        ms[1] = TaskEscrowV3.MilestoneDesc({description: "Build", amount: 7e18});

        vm.prank(client);
        uint256 jobId = escrow.createJob(IERC20(address(usdc)), "Build app", "dev", block.timestamp + 30 days, ms);

        vm.prank(freelancer);
        escrow.applyToJob(jobId);

        vm.prank(client);
        escrow.acceptFreelancer(jobId, freelancer);

        // Release first milestone
        vm.prank(client);
        escrow.releaseMilestone(jobId, 0);

        // Release second milestone
        vm.prank(client);
        escrow.releaseMilestone(jobId, 1);

        // Complete
        vm.prank(client);
        escrow.completeJob(jobId);

        // Rate
        vm.prank(client);
        escrow.rateFreelancer(jobId, 5);

        (uint256 completed, uint256 avgRating) = escrow.getReputation(freelancer);
        assertEq(completed, 1);
        assertEq(avgRating, 500); // 5.00 * 100
    }

    function test_CancelJob() public {
        TaskEscrowV3.MilestoneDesc[] memory ms = new TaskEscrowV3.MilestoneDesc[](1);
        ms[0] = TaskEscrowV3.MilestoneDesc({description: "M1", amount: 5e18});

        vm.prank(client);
        uint256 jobId = escrow.createJob(IERC20(address(usdc)), "Cancel test", "dev", block.timestamp + 30 days, ms);

        uint256 before = usdc.balanceOf(client);
        vm.prank(client);
        escrow.cancelJob(jobId);
        uint256 afterBal = usdc.balanceOf(client);

        assertEq(afterBal - before, 5e18);
    }

    function test_Reputation() public {
        (uint256 completed, uint256 avg) = escrow.getReputation(freelancer);
        assertEq(completed, 0);
        assertEq(avg, 0);
    }
}
