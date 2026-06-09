// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AuroraAirdrop} from "../src/AuroraAirdrop.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract AuroraAirdropTest is Test {
    AuroraAirdrop public airdrop;
    MockERC20 public token;

    // Actors
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");
    address public nonEligible = makeAddr("nonEligible");

    // Airdrop amounts
    uint256 constant ALICE_AMOUNT = 1000e18;
    uint256 constant BOB_AMOUNT = 2000e18;
    uint256 constant CAROL_AMOUNT = 3000e18;
    uint256 constant TOTAL_AMOUNT = 6000e18;

    // Merkle tree data
    bytes32 public merkleRoot;
    bytes32[] public proofAlice;
    bytes32[] public proofBob;
    bytes32[] public proofCarol;

    // Leaf hashes
    bytes32 public leafAlice;
    bytes32 public leafBob;
    bytes32 public leafCarol;

    // ─── Merkle Tree Builder ───

    function _buildMerkleTree() internal {
        // Leaves: keccak256(abi.encodePacked(address, amount))
        leafAlice = keccak256(abi.encodePacked(alice, ALICE_AMOUNT));
        leafBob = keccak256(abi.encodePacked(bob, BOB_AMOUNT));
        leafCarol = keccak256(abi.encodePacked(carol, CAROL_AMOUNT));

        // Sort leaves for consistent tree
        bytes32[3] memory leaves;
        leaves[0] = leafAlice;
        leaves[1] = leafBob;
        leaves[2] = leafCarol;

        // Sort
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                if (leaves[i] > leaves[j]) {
                    (leaves[i], leaves[j]) = (leaves[j], leaves[i]);
                }
            }
        }

        // Build tree with padding (duplicate last leaf if odd)
        bytes32 l01 = _hashPair(leaves[0], leaves[1]);
        bytes32 l23 = _hashPair(leaves[2], leaves[2]); // padded

        merkleRoot = _hashPair(l01, l23);

        // Build proofs for each leaf
        _buildProof(leafAlice, leaves, l01, l23);
        _buildProof(leafBob, leaves, l01, l23);
        _buildProof(leafCarol, leaves, l01, l23);
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _buildProof(
        bytes32 leaf,
        bytes32[3] memory leaves,
        bytes32 l01,
        bytes32 l23
    ) internal {
        // Find leaf index
        uint256 idx;
        for (uint256 i = 0; i < 3; i++) {
            if (leaves[i] == leaf) {
                idx = i;
                break;
            }
        }

        // Level 0 proof: sibling leaf
        bytes32 sibling0;
        if (idx == 0) sibling0 = leaves[1];
        else if (idx == 1) sibling0 = leaves[0];
        else sibling0 = leaves[2]; // idx == 2, sibling is padded duplicate

        // Level 1 proof: sibling hash
        bytes32 sibling1;
        if (idx < 2) sibling1 = l23; // left side, sibling is right
        else sibling1 = l01; // right side, sibling is left

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = sibling0;
        proof[1] = sibling1;

        if (leaf == leafAlice) {
            proofAlice = proof;
        } else if (leaf == leafBob) {
            proofBob = proof;
        } else {
            proofCarol = proof;
        }
    }

    // ─── Setup ───

    function setUp() public {
        _buildMerkleTree();

        // Deploy token
        token = new MockERC20("Aurora Token", "AURA");

        // Deploy airdrop
        vm.prank(owner);
        airdrop = new AuroraAirdrop(
            address(token),
            merkleRoot,
            block.timestamp + 30 days, // 30-day claim window
            TOTAL_AMOUNT,
            owner
        );

        // Fund the airdrop contract
        token.mint(address(airdrop), TOTAL_AMOUNT);
    }

    // ═══════════════════════════════════════════════════════
    // DEPLOYMENT
    // ═══════════════════════════════════════════════════════

    function test_DeployOwner() public view {
        assertEq(airdrop.owner(), owner);
    }

    function test_DeployToken() public view {
        assertEq(address(airdrop.token()), address(token));
    }

    function test_DeployMerkleRoot() public view {
        assertEq(airdrop.merkleRoot(), merkleRoot);
    }

    function test_DeployTotalAllocated() public view {
        assertEq(airdrop.totalAllocated(), TOTAL_AMOUNT);
    }

    function test_DeployBalance() public view {
        assertEq(token.balanceOf(address(airdrop)), TOTAL_AMOUNT);
    }

    function test_DeployZeroMerkleRoot() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSignature("InvalidMerkleRoot(bytes32)", bytes32(0))
        );
        new AuroraAirdrop(address(token), bytes32(0), 0, 100, owner);
    }

    // ═══════════════════════════════════════════════════════
    // CLAIM
    // ═══════════════════════════════════════════════════════

    function test_ClaimAlice() public {
        vm.prank(alice);
        airdrop.claim(ALICE_AMOUNT, proofAlice);

        assertTrue(airdrop.hasClaimed(alice));
        assertEq(token.balanceOf(alice), ALICE_AMOUNT);
        assertEq(airdrop.totalClaimed(), ALICE_AMOUNT);
    }

    function test_ClaimBob() public {
        vm.prank(bob);
        airdrop.claim(BOB_AMOUNT, proofBob);

        assertTrue(airdrop.hasClaimed(bob));
        assertEq(token.balanceOf(bob), BOB_AMOUNT);
    }

    function test_ClaimCarol() public {
        vm.prank(carol);
        airdrop.claim(CAROL_AMOUNT, proofCarol);

        assertTrue(airdrop.hasClaimed(carol));
        assertEq(token.balanceOf(carol), CAROL_AMOUNT);
    }

    function test_ClaimAll() public {
        vm.prank(alice);
        airdrop.claim(ALICE_AMOUNT, proofAlice);

        vm.prank(bob);
        airdrop.claim(BOB_AMOUNT, proofBob);

        vm.prank(carol);
        airdrop.claim(CAROL_AMOUNT, proofCarol);

        assertEq(airdrop.totalClaimed(), TOTAL_AMOUNT);
        assertEq(token.balanceOf(address(airdrop)), 0);
    }

    function test_ClaimAlreadyClaimed() public {
        vm.prank(alice);
        airdrop.claim(ALICE_AMOUNT, proofAlice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSignature("AlreadyClaimed(address)", alice)
        );
        airdrop.claim(ALICE_AMOUNT, proofAlice);
    }

    function test_ClaimInvalidProof() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        airdrop.claim(ALICE_AMOUNT, proofBob); // wrong proof
    }

    function test_ClaimInvalidAmount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        airdrop.claim(9999e18, proofAlice); // wrong amount
    }

    function test_ClaimNonEligible() public {
        vm.prank(nonEligible);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        airdrop.claim(1000e18, proofAlice);
    }

    function test_ClaimEmptyProof() public {
        bytes32[] memory empty;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        airdrop.claim(ALICE_AMOUNT, empty);
    }

    // ═══════════════════════════════════════════════════════
    // DEADLINE
    // ═══════════════════════════════════════════════════════

    function test_ClaimAfterDeadline() public {
        // Warp past deadline
        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSignature("ClaimPeriodEnded(uint256)", airdrop.claimDeadline())
        );
        airdrop.claim(ALICE_AMOUNT, proofAlice);
    }

    function test_ClaimJustBeforeDeadline() public {
        // Warp to just before deadline
        vm.warp(block.timestamp + 30 days - 1);

        vm.prank(alice);
        airdrop.claim(ALICE_AMOUNT, proofAlice);

        assertTrue(airdrop.hasClaimed(alice));
    }

    function test_IsClaimActive() public view {
        assertTrue(airdrop.isClaimActive());
    }

    function test_IsClaimActiveExpired() public {
        vm.warp(block.timestamp + 31 days);
        assertFalse(airdrop.isClaimActive());
    }

    function test_NoDeadline() public {
        // Deploy with no deadline (0)
        vm.prank(owner);
        AuroraAirdrop noDeadline = new AuroraAirdrop(
            address(token),
            merkleRoot,
            0, // no deadline
            TOTAL_AMOUNT,
            owner
        );

        // Should be claimable at any time
        token.mint(address(noDeadline), TOTAL_AMOUNT);

        vm.warp(block.timestamp + 365 days);
        assertTrue(noDeadline.isClaimActive());
    }

    // ═══════════════════════════════════════════════════════
    // RECOVER UNCLAIMED
    // ═══════════════════════════════════════════════════════

    function test_RecoverUnclaimed() public {
        // Alice claims, Bob and Carol don't
        vm.prank(alice);
        airdrop.claim(ALICE_AMOUNT, proofAlice);

        // Warp past deadline
        vm.warp(block.timestamp + 31 days);

        uint256 remaining = TOTAL_AMOUNT - ALICE_AMOUNT;
        uint256 ownerBalBefore = token.balanceOf(owner);

        vm.prank(owner);
        airdrop.recoverUnclaimed(owner);

        assertEq(token.balanceOf(owner), ownerBalBefore + remaining);
        assertEq(token.balanceOf(address(airdrop)), 0);
    }

    function test_RecoverUnclaimedBeforeDeadline() public {
        vm.prank(owner);
        vm.expectRevert(); // ClaimPeriodNotEnded
        airdrop.recoverUnclaimed(owner);
    }

    function test_RecoverUnclaimedNoDeadline() public {
        vm.prank(owner);
        AuroraAirdrop noDeadline = new AuroraAirdrop(
            address(token),
            merkleRoot,
            0,
            TOTAL_AMOUNT,
            owner
        );

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSignature("ClaimPeriodNotEnded(uint256)", 0)
        );
        noDeadline.recoverUnclaimed(owner);
    }

    function test_RecoverUnclaimedNothingLeft() public {
        // Everyone claims
        vm.prank(alice);
        airdrop.claim(ALICE_AMOUNT, proofAlice);
        vm.prank(bob);
        airdrop.claim(BOB_AMOUNT, proofBob);
        vm.prank(carol);
        airdrop.claim(CAROL_AMOUNT, proofCarol);

        vm.warp(block.timestamp + 31 days);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("NothingToRecover()"));
        airdrop.recoverUnclaimed(owner);
    }

    function test_RecoverUnclaimedOnlyOwner() public {
        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        vm.expectRevert();
        airdrop.recoverUnclaimed(alice);
    }

    // ═══════════════════════════════════════════════════════
    // OWNER CONFIGURATION
    // ═══════════════════════════════════════════════════════

    function test_SetMerkleRoot() public {
        bytes32 newRoot = keccak256(abi.encodePacked("new root"));
        vm.prank(owner);
        airdrop.setMerkleRoot(newRoot);

        assertEq(airdrop.merkleRoot(), newRoot);
    }

    function test_SetMerkleRootZero() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSignature("InvalidMerkleRoot(bytes32)", bytes32(0))
        );
        airdrop.setMerkleRoot(bytes32(0));
    }

    function test_SetMerkleRootOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        airdrop.setMerkleRoot(bytes32(uint256(1)));
    }

    function test_SetClaimDeadline() public {
        uint256 newDeadline = block.timestamp + 60 days;
        vm.prank(owner);
        airdrop.setClaimDeadline(newDeadline);

        assertEq(airdrop.claimDeadline(), newDeadline);
    }

    function test_SetClaimDeadlineOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        airdrop.setClaimDeadline(block.timestamp + 60 days);
    }

    function test_SetTotalAllocated() public {
        vm.prank(owner);
        airdrop.setTotalAllocated(10000e18);

        assertEq(airdrop.totalAllocated(), 10000e18);
    }

    function test_SetTotalAllocatedOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        airdrop.setTotalAllocated(10000e18);
    }

    // ═══════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════

    function test_RemainingTokens() public view {
        assertEq(airdrop.remainingTokens(), TOTAL_AMOUNT);
    }

    function test_RemainingTokensAfterClaim() public {
        vm.prank(alice);
        airdrop.claim(ALICE_AMOUNT, proofAlice);

        assertEq(airdrop.remainingTokens(), TOTAL_AMOUNT - ALICE_AMOUNT);
    }
}
