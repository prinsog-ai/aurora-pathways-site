// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {GovernorBase} from "../src/GovernorBase.sol";
import {TaskEscrowGovernor} from "../src/TaskEscrowGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract GovernorBaseTest is Test {
    GovernanceToken public token;
    TimelockController public timelock;
    TaskEscrowGovernor public governor;

    address public owner = address(this);
    address public voter1 = address(0x1);
    address public voter2 = address(0x2);
    address public voter3 = address(0x3);
    address public taskEscrow = address(0xBBBB);

    uint256 public constant MAX_SUPPLY = 1_000_000e18;
    uint256 public constant QUORUM_PERCENT = 4;
    uint256 public constant VOTING_DELAY = 1;
    uint256 public constant VOTING_PERIOD = 10;
    uint256 public constant TIMELOCK_DELAY = 3600;

    function setUp() public {
        // Deploy governance token
        token = new GovernanceToken("TaskEscrow Token", "TET", MAX_SUPPLY, owner);
        token.mint(voter1, 300_000e18);
        token.mint(voter2, 300_000e18);
        token.mint(voter3, 200_000e18);

        // Self-delegate (required for ERC20Votes)
        vm.prank(voter1);
        token.delegate(voter1);
        vm.prank(voter2);
        token.delegate(voter2);
        vm.prank(voter3);
        token.delegate(voter3);

        // Deploy timelock (admin = address(0) means no extra admin)
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, owner);

        // Deploy governor
        governor = new TaskEscrowGovernor(
            "TaskEscrow Governor",
            token,
            timelock,
            QUORUM_PERCENT,
            VOTING_DELAY,
            VOTING_PERIOD,
            taskEscrow
        );

        // Grant proposer + executor roles to governor
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
    }

    function test_TokenDeployment() public view {
        assertEq(token.name(), "TaskEscrow Token");
        assertEq(token.symbol(), "TET");
        assertEq(token.totalSupply(), 800_000e18);
        assertEq(token.maxSupply(), MAX_SUPPLY);
    }

    function test_VotingPower() public view {
        assertEq(token.getVotes(voter1), 300_000e18);
        assertEq(token.getVotes(voter2), 300_000e18);
        assertEq(token.getVotes(voter3), 200_000e18);
    }

    function test_GovernorDeployment() public view {
        assertEq(governor.name(), "TaskEscrow Governor");
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
    }

    function test_ProposeVoteQueueExecute() public {
        // Create proposal
        address[] memory targets = new address[](1);
        targets[0] = taskEscrow;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("setPlatformFee(uint256)", 500);
        string memory description = "Increase platform fee to 5%";

        // Propose
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        assertGt(proposalId, 0);

        // Advance past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote FOR
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        // Advance past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Should be Succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // Queue in timelock
        governor.queue(targets, values, calldatas, keccak256(bytes(description)));

        // Advance past timelock
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // Execute
        governor.execute(targets, values, calldatas, keccak256(bytes(description)));

        // Should be Executed
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }

    function test_MintExceedsMaxSupply() public {
        vm.expectRevert(GovernanceToken.GovernanceToken__ExceedsMaxSupply.selector);
        token.mint(address(0x99), MAX_SUPPLY);
    }

    function test_MintZeroAmount() public {
        vm.expectRevert(GovernanceToken.GovernanceToken__ZeroAmount.selector);
        token.mint(address(0x99), 0);
    }
}
