// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RevenueDistributor} from "../src/RevenueDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ───────────── Mock USDC ─────────────

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ───────────── Mock Governance Token with ERC20Votes ─────────────

contract MockGovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;

    error ExceedsMaxSupply(uint256 requested, uint256 max);

    constructor(address initialOwner) ERC20("Governance Token", "GOV") ERC20Permit("Governance Token") Ownable(initialOwner) {}

    function mint(address to, uint256 amount) external onlyOwner {
        if (totalSupply() + amount > MAX_SUPPLY) {
            revert ExceedsMaxSupply(totalSupply() + amount, MAX_SUPPLY);
        }
        _mint(to, amount);
    }

    function clock() public view override returns (uint48) {
        return uint48(block.number);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}

// ───────────── Revenue Distributor Tests ─────────────

contract RevenueDistributorTest is Test {
    RevenueDistributor public distributor;
    MockUSDC public usdc;
    MockGovernanceToken public govToken;

    address public owner = address(1);
    address public holder1 = address(2);
    address public holder2 = address(3);
    address public holder3 = address(4);
    address public stranger = address(5);
    address public taskEscrow = address(6);
    address public pledgly = address(7);

    uint256 public constant USDC_DECIMALS = 1e6;

    function setUp() public {
        usdc = new MockUSDC();

        vm.prank(owner);
        govToken = new MockGovernanceToken(owner);

        vm.prank(owner);
        distributor = new RevenueDistributor(address(usdc), address(govToken), owner);

        // Mint governance tokens to holders and have them self-delegate
        vm.prank(owner);
        govToken.mint(holder1, 500 * 1e18);
        vm.prank(holder1);
        govToken.delegate(holder1);

        vm.prank(owner);
        govToken.mint(holder2, 300 * 1e18);
        vm.prank(holder2);
        govToken.delegate(holder2);

        vm.prank(owner);
        govToken.mint(holder3, 200 * 1e18);
        vm.prank(holder3);
        govToken.delegate(holder3);

        // Total supply = 1000 * 1e18
        // holder1 = 50%, holder2 = 30%, holder3 = 20%
    }

    // ───────────── Helper ─────────────

    function _depositAndCreateDistribution(uint256 usdcAmount) internal returns (uint256 distId) {
        usdc.mint(owner, usdcAmount);
        vm.prank(owner);
        usdc.approve(address(distributor), usdcAmount);
        vm.prank(owner);
        distributor.deposit(usdcAmount);
        // Roll forward so getPastTotalSupply(block.number) works (must be < current block)
        vm.roll(block.number + 1);
        vm.prank(owner);
        distId = distributor.createDistribution();
    }

    // ───────────── Constructor Tests ─────────────

    function test_ConstructorSetsCorrectValues() public view {
        assertEq(address(distributor.usdc()), address(usdc));
        assertEq(address(distributor.governanceToken()), address(govToken));
        assertEq(distributor.owner(), owner);
    }

    function test_ConstructorRevertsOnZeroUSDC() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RevenueDistributor.InvalidAddress.selector));
        new RevenueDistributor(address(0), address(govToken), owner);
    }

    function test_ConstructorRevertsOnZeroGovernanceToken() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RevenueDistributor.InvalidAddress.selector));
        new RevenueDistributor(address(usdc), address(0), owner);
    }

    // ───────────── Source Authorization Tests ─────────────

    function test_AuthorizeSource() public {
        vm.prank(owner);
        distributor.authorizeSource(taskEscrow);
        assertTrue(distributor.authorizedSources(taskEscrow));
    }

    function test_DeauthorizeSource() public {
        vm.prank(owner);
        distributor.authorizeSource(taskEscrow);
        assertTrue(distributor.authorizedSources(taskEscrow));

        vm.prank(owner);
        distributor.deauthorizeSource(taskEscrow);
        assertFalse(distributor.authorizedSources(taskEscrow));
    }

    function test_NonOwnerCannotAuthorizeSource() public {
        vm.prank(stranger);
        vm.expectRevert();
        distributor.authorizeSource(taskEscrow);
    }

    function test_AuthorizeSourceRevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RevenueDistributor.InvalidAddress.selector));
        distributor.authorizeSource(address(0));
    }

    // ───────────── Deposit Tests ─────────────

    function test_DepositUSDC() public {
        uint256 amount = 1000 * USDC_DECIMALS;
        usdc.mint(stranger, amount);
        vm.prank(stranger);
        usdc.approve(address(distributor), amount);
        vm.prank(stranger);
        distributor.deposit(amount);
        assertEq(usdc.balanceOf(address(distributor)), amount);
    }

    function test_DepositRevertsOnZeroAmount() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(RevenueDistributor.ZeroAmount.selector));
        distributor.deposit(0);
    }

    function test_DepositFromAuthorizedSource() public {
        uint256 amount = 500 * USDC_DECIMALS;
        vm.prank(owner);
        distributor.authorizeSource(taskEscrow);

        usdc.mint(taskEscrow, amount);
        vm.prank(taskEscrow);
        usdc.approve(address(distributor), amount);
        vm.prank(taskEscrow);
        distributor.depositFromSource(amount);

        assertEq(usdc.balanceOf(address(distributor)), amount);
    }

    function test_DepositFromUnauthorizedSourceReverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(RevenueDistributor.NotAuthorizedSource.selector));
        distributor.depositFromSource(100);
    }

    // ───────────── Distribution Creation Tests ─────────────

    function test_CreateDistribution() public {
        uint256 amount = 1000 * USDC_DECIMALS;
        usdc.mint(owner, amount);
        vm.prank(owner);
        usdc.approve(address(distributor), amount);
        vm.prank(owner);
        distributor.deposit(amount);

        vm.roll(block.number + 1);
        vm.prank(owner);
        uint256 distId = distributor.createDistribution();

        assertEq(distId, 0);
        assertEq(distributor.distributionCount(), 1);

        (uint256 distAmount, uint256 snapshotBlock, uint256 totalSupply, uint256 totalClaimed, bool finalized) = distributor.getDistribution(distId);
        assertEq(distAmount, amount);
        assertEq(snapshotBlock, block.number - 1);
        assertEq(totalSupply, 1000 * 1e18);
        assertEq(totalClaimed, 0);
        assertFalse(finalized);
    }

    function test_CreateDistributionRevertsOnZeroBalance() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RevenueDistributor.ZeroBalance.selector));
        distributor.createDistribution();
    }

    function test_CreateDistributionAmount() public {
        uint256 amount = 2000 * USDC_DECIMALS;
        usdc.mint(owner, amount);
        vm.prank(owner);
        usdc.approve(address(distributor), amount);
        vm.prank(owner);
        distributor.deposit(amount);

        // Distribute only 500
        vm.roll(block.number + 1);
        vm.prank(owner);
        uint256 distId = distributor.createDistributionAmount(500 * USDC_DECIMALS);

        (uint256 distAmount,,,,) = distributor.getDistribution(distId);
        assertEq(distAmount, 500 * USDC_DECIMALS);
        // Balance stays at 2000 — funds are not moved until holders claim
        assertEq(usdc.balanceOf(address(distributor)), 2000 * USDC_DECIMALS);
    }

    function test_CreateDistributionAmountRevertsOnExceedsBalance() public {
        uint256 amount = 100 * USDC_DECIMALS;
        usdc.mint(owner, amount);
        vm.prank(owner);
        usdc.approve(address(distributor), amount);
        vm.prank(owner);
        distributor.deposit(amount);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RevenueDistributor.ZeroBalance.selector));
        distributor.createDistributionAmount(200 * USDC_DECIMALS);
    }

    function test_NonOwnerCannotCreateDistribution() public {
        usdc.mint(owner, 100 * USDC_DECIMALS);
        vm.prank(owner);
        usdc.approve(address(distributor), 100 * USDC_DECIMALS);
        vm.prank(owner);
        distributor.deposit(100 * USDC_DECIMALS);

        vm.prank(stranger);
        vm.expectRevert();
        distributor.createDistribution();
    }

    // ───────────── Claiming Tests ─────────────

    function test_ClaimProportionalShare() public {
        uint256 totalUSDC = 1000 * USDC_DECIMALS;
        _depositAndCreateDistribution(totalUSDC);

        uint256 distId = 0;

        // holder1 has 50% of tokens → should get 500 USDC
        uint256 expected1 = (500 * 1e18 * totalUSDC) / (1000 * 1e18);
        vm.prank(holder1);
        distributor.claim(distId);
        assertEq(usdc.balanceOf(holder1), expected1);

        // holder2 has 30% → 300 USDC
        uint256 expected2 = (300 * 1e18 * totalUSDC) / (1000 * 1e18);
        vm.prank(holder2);
        distributor.claim(distId);
        assertEq(usdc.balanceOf(holder2), expected2);

        // holder3 has 20% → 200 USDC
        uint256 expected3 = (200 * 1e18 * totalUSDC) / (1000 * 1e18);
        vm.prank(holder3);
        distributor.claim(distId);
        assertEq(usdc.balanceOf(holder3), expected3);
    }

    function test_ClaimRevertsIfAlreadyClaimed() public {
        uint256 totalUSDC = 1000 * USDC_DECIMALS;
        _depositAndCreateDistribution(totalUSDC);

        vm.prank(holder1);
        distributor.claim(0);

        vm.prank(holder1);
        vm.expectRevert(abi.encodeWithSelector(RevenueDistributor.AlreadyClaimed.selector));
        distributor.claim(0);
    }

    function test_ClaimRevertsIfNoVotes() public {
        uint256 totalUSDC = 1000 * USDC_DECIMALS;
        _depositAndCreateDistribution(totalUSDC);

        // stranger has no governance tokens
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(RevenueDistributor.NothingToClaim.selector));
        distributor.claim(0);
    }

    function test_HasClaimedAfterClaim() public {
        _depositAndCreateDistribution(1000 * USDC_DECIMALS);

        assertFalse(distributor.hasClaimed(0, holder1));
        vm.prank(holder1);
        distributor.claim(0);
        assertTrue(distributor.hasClaimed(0, holder1));
    }

    function test_FinalizationWhenFullyClaimed() public {
        uint256 totalUSDC = 1000 * USDC_DECIMALS;
        _depositAndCreateDistribution(totalUSDC);

        vm.prank(holder1);
        distributor.claim(0);
        vm.prank(holder2);
        distributor.claim(0);

        // Not finalized yet (holder3 hasn't claimed)
        (,,,, bool finalized) = distributor.getDistribution(0);
        assertFalse(finalized);

        vm.prank(holder3);
        distributor.claim(0);

        // Now finalized (all 100% claimed)
        (,,,, finalized) = distributor.getDistribution(0);
        assertTrue(finalized);
    }

    function test_ClaimAfterFinalizationReverts() public {
        uint256 totalUSDC = 1000 * USDC_DECIMALS;
        _depositAndCreateDistribution(totalUSDC);

        vm.prank(holder1);
        distributor.claim(0);
        vm.prank(holder2);
        distributor.claim(0);
        vm.prank(holder3);
        distributor.claim(0);

        // Distribution is finalized, any new claim should revert
        // Mint new tokens to stranger so they have votes
        vm.prank(owner);
        govToken.mint(stranger, 100 * 1e18);
        vm.prank(stranger);
        govToken.delegate(stranger);

        // Distribution is already finalized, so AlreadyFinalized fires first
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(RevenueDistributor.AlreadyFinalized.selector));
        distributor.claim(0);
    }

    // ───────────── Multiple Distribution Tests ─────────────

    function test_MultipleDistributions() public {
        // First distribution
        uint256 usdc1 = 500 * USDC_DECIMALS;
        _depositAndCreateDistribution(usdc1);
        assertEq(distributor.distributionCount(), 1);

        // Second distribution — use createDistributionAmount to avoid sweeping leftover
        uint256 usdc2 = 800 * USDC_DECIMALS;
        usdc.mint(owner, usdc2);
        vm.prank(owner);
        usdc.approve(address(distributor), usdc2);
        vm.prank(owner);
        distributor.deposit(usdc2);
        vm.roll(block.number + 1);
        vm.prank(owner);
        distributor.createDistributionAmount(usdc2);
        assertEq(distributor.distributionCount(), 2);

        // Claim from both
        uint256 expectedShare1 = (500 * 1e18 * usdc1) / (1000 * 1e18);
        vm.prank(holder1);
        distributor.claim(0);
        assertEq(usdc.balanceOf(holder1), expectedShare1);

        uint256 expectedShare2 = (500 * 1e18 * usdc2) / (1000 * 1e18);
        vm.prank(holder1);
        distributor.claim(1);
        assertEq(usdc.balanceOf(holder1), expectedShare1 + expectedShare2);
    }

    // ───────────── View Function Tests ─────────────

    function test_GetBalance() public {
        assertEq(distributor.getBalance(), 0);

        uint256 amount = 500 * USDC_DECIMALS;
        usdc.mint(owner, amount);
        vm.prank(owner);
        usdc.approve(address(distributor), amount);
        vm.prank(owner);
        distributor.deposit(amount);

        assertEq(distributor.getBalance(), amount);
    }

    function test_GetClaimable() public {
        uint256 totalUSDC = 1000 * USDC_DECIMALS;
        _depositAndCreateDistribution(totalUSDC);

        // holder1 (50%) should have 500 USDC claimable
        uint256 claimable = distributor.getClaimable(0, holder1);
        assertEq(claimable, 500 * USDC_DECIMALS);

        // After claiming, should be 0
        vm.prank(holder1);
        distributor.claim(0);
        claimable = distributor.getClaimable(0, holder1);
        assertEq(claimable, 0);
    }

    function test_GetClaimableReturnsZeroForNoVotes() public {
        _depositAndCreateDistribution(1000 * USDC_DECIMALS);
        assertEq(distributor.getClaimable(0, stranger), 0);
    }

    function test_GetUnclaimed() public {
        uint256 totalUSDC = 1000 * USDC_DECIMALS;
        _depositAndCreateDistribution(totalUSDC);

        assertEq(distributor.getUnclaimed(0), totalUSDC);

        vm.prank(holder1);
        distributor.claim(0);
        assertEq(distributor.getUnclaimed(0), totalUSDC - 500 * USDC_DECIMALS);
    }

    function test_GetUnclaimedReturnsZeroForInvalidDist() public {
        assertEq(distributor.getUnclaimed(999), 0);
    }

    function test_GetTotalClaimedByHolder() public {
        uint256 totalUSDC = 1000 * USDC_DECIMALS;
        _depositAndCreateDistribution(totalUSDC);

        // Second distribution — use createDistributionAmount to avoid sweeping leftover
        usdc.mint(owner, 600 * USDC_DECIMALS);
        vm.prank(owner);
        usdc.approve(address(distributor), 600 * USDC_DECIMALS);
        vm.prank(owner);
        distributor.deposit(600 * USDC_DECIMALS);
        vm.roll(block.number + 1);
        vm.prank(owner);
        distributor.createDistributionAmount(600 * USDC_DECIMALS);

        // Claim from both
        vm.prank(holder1);
        distributor.claim(0);
        vm.prank(holder1);
        distributor.claim(1);

        uint256 expectedTotal = (500 * 1e18 * totalUSDC) / (1000 * 1e18)
            + (500 * 1e18 * 600 * USDC_DECIMALS) / (1000 * 1e18);
        assertEq(distributor.getTotalClaimedByHolder(holder1), expectedTotal);
    }

    // ───────────── Snapshot Integrity Tests ─────────────

    function test_SnapshotCapturesCorrectBalances() public {
        // Transfer some tokens before distribution to change balances
        vm.prank(holder1);
        govToken.transfer(stranger, 100 * 1e18);
        // Now: holder1=400, holder2=300, holder3=200, stranger=100 (total 1000)
        // Self-delegate stranger
        vm.prank(stranger);
        govToken.delegate(stranger);

        uint256 totalUSDC = 1000 * USDC_DECIMALS;
        _depositAndCreateDistribution(totalUSDC);

        // holder1 now has 40% of supply
        uint256 claimable1 = distributor.getClaimable(0, holder1);
        assertEq(claimable1, 400 * USDC_DECIMALS);

        // stranger has 10%
        uint256 claimableStranger = distributor.getClaimable(0, stranger);
        assertEq(claimableStranger, 100 * USDC_DECIMALS);
    }

    function test_TokensTransferredAfterSnapshotNotAffectingPreviousDistribution() public {
        _depositAndCreateDistribution(1000 * USDC_DECIMALS);

        // Transfer tokens after snapshot
        vm.prank(holder1);
        govToken.transfer(stranger, 250 * 1e18);

        // holder1 still claims 50% (snapshot was before transfer)
        uint256 claimable1 = distributor.getClaimable(0, holder1);
        assertEq(claimable1, 500 * USDC_DECIMALS);
    }

    // ───────────── Edge Case Tests ─────────────

    function test_DistributionWithLargeUSDCAmount() public {
        uint256 largeAmount = 1_000_000 * USDC_DECIMALS; // 1M USDC
        _depositAndCreateDistribution(largeAmount);

        uint256 claimable = distributor.getClaimable(0, holder1);
        assertEq(claimable, 500_000 * USDC_DECIMALS);

        vm.prank(holder1);
        distributor.claim(0);
        assertEq(usdc.balanceOf(holder1), 500_000 * USDC_DECIMALS);
    }

    function test_SourceAuthorizationEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(distributor));
        emit RevenueDistributor.SourceAuthorized(taskEscrow);
        vm.prank(owner);
        distributor.authorizeSource(taskEscrow);
    }

    function test_DistributionCreatedEmitsEvent() public {
        usdc.mint(owner, 100 * USDC_DECIMALS);
        vm.prank(owner);
        usdc.approve(address(distributor), 100 * USDC_DECIMALS);
        vm.prank(owner);
        distributor.deposit(100 * USDC_DECIMALS);

        vm.roll(block.number + 1);
        vm.expectEmit(true, false, false, true, address(distributor));
        emit RevenueDistributor.DistributionCreated(0, 100 * USDC_DECIMALS, block.number - 1, 1000 * 1e18);
        vm.prank(owner);
        distributor.createDistribution();
    }

    function test_RevenueClaimedEmitsEvent() public {
        _depositAndCreateDistribution(1000 * USDC_DECIMALS);

        uint256 expectedShare = (500 * 1e18 * 1000 * USDC_DECIMALS) / (1000 * 1e18);
        vm.expectEmit(true, true, false, true, address(distributor));
        emit RevenueDistributor.RevenueClaimed(0, holder1, expectedShare);
        vm.prank(holder1);
        distributor.claim(0);
    }

    function test_TotalDistributedTracksCorrectly() public {
        uint256 usdc1 = 500 * USDC_DECIMALS;
        _depositAndCreateDistribution(usdc1);

        vm.prank(holder1);
        distributor.claim(0);

        (,,,uint256 totalClaimed,) = distributor.getDistribution(0);
        uint256 expectedClaimed = (500 * 1e18 * usdc1) / (1000 * 1e18);
        assertEq(totalClaimed, expectedClaimed);
    }

    function test_UnclaimedDistributionBalance() public {
        uint256 totalUSDC = 1000 * USDC_DECIMALS;
        _depositAndCreateDistribution(totalUSDC);

        // Only holder1 claims (50%)
        vm.prank(holder1);
        distributor.claim(0);

        uint256 unclaimed = distributor.getUnclaimed(0);
        assertEq(unclaimed, 500 * USDC_DECIMALS);
        assertEq(usdc.balanceOf(address(distributor)), 500 * USDC_DECIMALS);
    }
}
