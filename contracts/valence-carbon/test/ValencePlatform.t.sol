// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ValenceCarbonCredit} from "../src/ValenceCarbonCredit.sol";
import {ValencePlatform} from "../src/ValencePlatform.sol";

contract ValencePlatformTest is Test {
    ValenceCarbonCredit public token;
    ValencePlatform public platform;

    address public admin = address(0xA);
    address public siteOwner1 = address(0x1);
    address public siteOwner2 = address(0x2);
    address public submitter = address(0x3);
    address public nobody = address(0x4);

    uint256 constant CO2_FACTOR = 360; // 3.6% basis points
    uint256 constant ONE_CREDIT = 1e18;

    // Events
    event SiteRegistered(uint256 indexed siteId, string name, address siteOwner, uint256 valenceShareBps);
    event SiteUpdated(uint256 indexed siteId, bool active, uint256 valenceShareBps);
    event MRVSubmitted(uint256 indexed mrvId, uint256 indexed siteId, address submittedBy, uint256 gasVolumeMCF, uint256 co2ReducedTons, uint256 creditsIssued);
    event CreditsDistributed(uint256 indexed mrvId, address valence, uint256 valenceCredits, address siteOwner, uint256 siteOwnerCredits);
    event DataSubmitterUpdated(address indexed submitter, bool allowed);
    event Co2FactorUpdated(uint256 oldFactor, uint256 newFactor);
    event TokensWithdrawn(address indexed to, uint256 amount);

    function setUp() public {
        vm.startPrank(admin);
        token = new ValenceCarbonCredit(admin);
        platform = new ValencePlatform(admin, address(token), CO2_FACTOR);
        token.transferOwnership(address(platform));
        platform.setDataSubmitter(submitter, true);
        vm.stopPrank();
    }

    // ─── Token Tests ────────────────────────────────────────────

    function test_TokenName() public view {
        assertEq(token.name(), "Valence Carbon Credit");
    }

    function test_TokenSymbol() public view {
        assertEq(token.symbol(), "VCC");
    }

    function test_TokenDecimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_TokenMaxSupply() public view {
        assertEq(token.MAX_SUPPLY(), 500_000_000 * 1e18);
    }

    function test_TokenInitialSupplyIsZero() public view {
        assertEq(token.totalSupply(), 0);
    }

    function test_TokenOwnerIsPlatform() public view {
        assertEq(token.owner(), address(platform));
    }

    // ─── Platform Deployment ────────────────────────────────────

    function test_PlatformOwner() public view {
        assertEq(platform.owner(), admin);
    }

    function test_PlatformCreditToken() public view {
        assertEq(address(platform.creditToken()), address(token));
    }

    function test_PlatformCo2Factor() public view {
        assertEq(platform.co2Factor(), CO2_FACTOR);
    }

    function test_AdminIsDataSubmitter() public view {
        assertTrue(platform.dataSubmitters(admin));
    }

    function test_SubmitterIsDataSubmitter() public view {
        assertTrue(platform.dataSubmitters(submitter));
    }

    function test_NobodyIsNotDataSubmitter() public view {
        assertFalse(platform.dataSubmitters(nobody));
    }

    // ─── Site Registration ──────────────────────────────────────

    function test_RegisterSite() public {
        vm.prank(admin);
        uint256 siteId = platform.registerSite("Bakken Basin A", "North Dakota", siteOwner1, 6000);

        assertEq(siteId, 1);
        assertEq(platform.siteCount(), 1);

        ValencePlatform.Site memory s = platform.getSite(1);
        assertEq(s.name, "Bakken Basin A");
        assertEq(s.location, "North Dakota");
        assertEq(s.siteOwner, siteOwner1);
        assertEq(s.valenceShareBps, 6000);
        assertTrue(s.active);
        assertEq(s.totalGasMCF, 0);
        assertEq(s.totalCredits, 0);
    }

    function test_RegisterSiteEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit SiteRegistered(1, "Permian Basin B", siteOwner2, 5000);
        platform.registerSite("Permian Basin B", "Texas", siteOwner2, 5000);
    }

    function test_RegisterMultipleSites() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        platform.registerSite("Site B", "TX", siteOwner2, 5000);
        platform.registerSite("Site C", "PA", siteOwner1, 5500);
        vm.stopPrank();

        assertEq(platform.siteCount(), 3);
        assertEq(platform.getSite(1).name, "Site A");
        assertEq(platform.getSite(2).name, "Site B");
        assertEq(platform.getSite(3).name, "Site C");
    }

    function test_NonOwnerCannotRegisterSite() public {
        vm.prank(nobody);
        vm.expectRevert();
        platform.registerSite("Bad", "Bad", nobody, 5000);
    }

    function test_CannotRegisterSiteWithInvalidShare() public {
        vm.prank(admin);
        vm.expectRevert();
        platform.registerSite("Bad", "Bad", siteOwner1, 10001);
    }

    function test_RegisterSiteWithZeroShare() public {
        vm.prank(admin);
        uint256 siteId = platform.registerSite("Free Site", "Nowhere", siteOwner1, 0);
        assertEq(siteId, 1);
        assertEq(platform.getSite(1).valenceShareBps, 0);
    }

    function test_RegisterSiteWith100PercentToValence() public {
        vm.prank(admin);
        uint256 siteId = platform.registerSite("Full Valence", "Everywhere", siteOwner1, 10000);
        assertEq(siteId, 1);
        assertEq(platform.getSite(1).valenceShareBps, 10000);
    }

    // ─── Site Updates ───────────────────────────────────────────

    function test_UpdateSite() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        platform.updateSite(1, true, 5500, siteOwner2);
        vm.stopPrank();

        ValencePlatform.Site memory s = platform.getSite(1);
        assertTrue(s.active);
        assertEq(s.valenceShareBps, 5500);
        assertEq(s.siteOwner, siteOwner2);
    }

    function test_DeactivateSite() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        platform.updateSite(1, false, 6000, address(0));
        vm.stopPrank();

        assertFalse(platform.getSite(1).active);
    }

    function test_UpdateSiteEmitsEvent() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        vm.expectEmit(true, true, false, true);
        emit SiteUpdated(1, true, 5000);
        platform.updateSite(1, true, 5000, address(0));
        vm.stopPrank();
    }

    function test_UpdateInvalidSiteReverts() public {
        vm.prank(admin);
        vm.expectRevert();
        platform.updateSite(99, true, 5000, address(0));
    }

    function test_UpdateSiteInvalidShareReverts() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        vm.expectRevert();
        platform.updateSite(1, true, 10001, address(0));
        vm.stopPrank();
    }

    // ─── MRV Submission ─────────────────────────────────────────

    function test_SubmitMRV() public {
        vm.startPrank(admin);
        platform.registerSite("Bakken A", "ND", siteOwner1, 6000);
        vm.stopPrank();

        vm.prank(submitter);
        uint256 mrvId = platform.submitMRV(1, 15200);

        assertEq(mrvId, 1);
        assertEq(platform.mrvCount(), 1);

        // 15200 * 360 / 10000 = 547
        ValencePlatform.MRVEntry memory mrv = platform.getMRV(1);
        assertEq(mrv.siteId, 1);
        assertEq(mrv.submittedBy, submitter);
        assertEq(mrv.gasVolumeMCF, 15200);
        assertEq(mrv.co2ReducedTons, 547);
        assertEq(mrv.creditsIssued, 547);
        assertTrue(mrv.verified);

        // 60% to Valence: 547 * 6000 / 10000 = 328
        assertEq(mrv.valenceCredits, 328);
        // 40% to site owner: 547 - 328 = 219
        assertEq(mrv.siteOwnerCredits, 219);
    }

    function test_SubmitMRVDistributesCredits() public {
        vm.startPrank(admin);
        platform.registerSite("Bakken A", "ND", siteOwner1, 6000);
        vm.stopPrank();

        vm.prank(submitter);
        platform.submitMRV(1, 15200);

        // Site owner gets their share
        assertEq(token.balanceOf(siteOwner1), 219 * ONE_CREDIT);
        // Platform (Valence) gets its share
        assertEq(token.balanceOf(address(platform)), 328 * ONE_CREDIT);
        // Total supply = full credits
        assertEq(token.totalSupply(), 547 * ONE_CREDIT);
    }

    function test_SubmitMRVEmitsEvents() public {
        vm.startPrank(admin);
        platform.registerSite("Bakken A", "ND", siteOwner1, 6000);
        vm.stopPrank();

        vm.prank(submitter);
        vm.expectEmit(true, true, true, true);
        emit MRVSubmitted(1, 1, submitter, 15200, 547, 547);
        platform.submitMRV(1, 15200);
    }

    function test_SubmitMRVCreditsDistributedEvent() public {
        vm.startPrank(admin);
        platform.registerSite("Bakken A", "ND", siteOwner1, 6000);
        vm.stopPrank();

        vm.prank(submitter);
        vm.expectEmit(true, true, false, true);
        emit CreditsDistributed(1, address(platform), 328, siteOwner1, 219);
        platform.submitMRV(1, 15200);
    }

    function test_SubmitMultipleMRVs() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        vm.stopPrank();

        vm.startPrank(submitter);
        platform.submitMRV(1, 15200);
        platform.submitMRV(1, 20000);
        vm.stopPrank();

        assertEq(platform.mrvCount(), 2);

        // 20000 * 360 / 10000 = 720
        // Total credits: 547 + 720 = 1267
        ValencePlatform.Site memory s = platform.getSite(1);
        assertEq(s.totalGasMCF, 35200);
        assertEq(s.totalCredits, 1267);

        // Site owner balance: 219 + 288 = 507
        assertEq(token.balanceOf(siteOwner1), 507 * ONE_CREDIT);
    }

    function test_SubmitMRVToInvalidSiteReverts() public {
        vm.prank(submitter);
        vm.expectRevert();
        platform.submitMRV(99, 1000);
    }

    function test_SubmitMRVToSiteZeroReverts() public {
        vm.prank(submitter);
        vm.expectRevert();
        platform.submitMRV(0, 1000);
    }

    function test_SubmitMRVZeroVolumeReverts() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        vm.stopPrank();

        vm.prank(submitter);
        vm.expectRevert();
        platform.submitMRV(1, 0);
    }

    function test_SubmitMRVToInactiveSiteReverts() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        platform.updateSite(1, false, 6000, address(0));
        vm.stopPrank();

        vm.prank(submitter);
        vm.expectRevert();
        platform.submitMRV(1, 10000);
    }

    function test_UnauthorizedSubmitterReverts() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        vm.stopPrank();

        vm.prank(nobody);
        vm.expectRevert();
        platform.submitMRV(1, 10000);
    }

    // ─── Admin can submit MRV too ──────────────────────────────

    function test_AdminCanSubmitMRV() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        platform.submitMRV(1, 80000);
        vm.stopPrank();

        // 80000 * 360 / 10000 = 2880
        assertEq(platform.getMRV(1).creditsIssued, 2880);
        // 60% to Valence: 2880 * 60% = 1728
        assertEq(platform.getMRV(1).valenceCredits, 1728);
        // 40% to site owner: 2880 * 40% = 1152
        assertEq(platform.getMRV(1).siteOwnerCredits, 1152);
    }

    // ─── Revenue splits ─────────────────────────────────────────

    function test_50_50Split() public {
        vm.startPrank(admin);
        platform.registerSite("Equal Site", "TX", siteOwner1, 5000);
        platform.submitMRV(1, 10000);
        vm.stopPrank();

        // 10000 * 360 / 10000 = 360
        uint256 totalCredits = 360;
        uint256 valenceShare = totalCredits / 2;
        uint256 ownerShare = totalCredits - valenceShare;

        assertEq(token.balanceOf(address(platform)), valenceShare * ONE_CREDIT);
        assertEq(token.balanceOf(siteOwner1), ownerShare * ONE_CREDIT);
    }

    function test_70_30Split() public {
        vm.startPrank(admin);
        platform.registerSite("High Split", "LA", siteOwner2, 7000);
        platform.submitMRV(1, 10000);
        vm.stopPrank();

        // 10000 * 360 / 10000 = 360
        uint256 totalCredits = 360;
        uint256 valenceShare = (totalCredits * 7000) / 10000; // 252
        uint256 ownerShare = totalCredits - valenceShare; // 108

        assertEq(token.balanceOf(address(platform)), valenceShare * ONE_CREDIT);
        assertEq(token.balanceOf(siteOwner2), ownerShare * ONE_CREDIT);
    }

    function test_100PercentToValence() public {
        vm.startPrank(admin);
        platform.registerSite("Full Valence", "WY", siteOwner1, 10000);
        platform.submitMRV(1, 10000);
        vm.stopPrank();

        uint256 totalCredits = 360;
        assertEq(token.balanceOf(address(platform)), totalCredits * ONE_CREDIT);
        assertEq(token.balanceOf(siteOwner1), 0);
    }

    function test_0PercentToValence() public {
        vm.startPrank(admin);
        platform.registerSite("Full Owner", "CO", siteOwner1, 0);
        platform.submitMRV(1, 10000);
        vm.stopPrank();

        uint256 totalCredits = 360;
        assertEq(token.balanceOf(address(platform)), 0);
        assertEq(token.balanceOf(siteOwner1), totalCredits * ONE_CREDIT);
    }

    // ─── View helpers ───────────────────────────────────────────

    function test_EstimateCredits() public view {
        // 80000 MCF * 360 / 10000 = 2880
        assertEq(platform.estimateCredits(80000), 2880);
        assertEq(platform.estimateCredits(15200), 547);
        assertEq(platform.estimateCredits(10000), 360);
    }

    function test_PlatformCreditBalance() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        platform.submitMRV(1, 15200);
        vm.stopPrank();

        assertEq(platform.platformCreditBalance(), 328 * ONE_CREDIT);
    }

    // ─── Data submitter management ──────────────────────────────

    function test_SetDataSubmitter() public {
        vm.prank(admin);
        platform.setDataSubmitter(nobody, true);
        assertTrue(platform.dataSubmitters(nobody));
    }

    function test_RevokeDataSubmitter() public {
        vm.prank(admin);
        platform.setDataSubmitter(submitter, false);
        assertFalse(platform.dataSubmitters(submitter));
    }

    function test_SetDataSubmitterEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit DataSubmitterUpdated(nobody, true);
        platform.setDataSubmitter(nobody, true);
    }

    function test_NonOwnerCannotSetSubmitter() public {
        vm.prank(nobody);
        vm.expectRevert();
        platform.setDataSubmitter(nobody, true);
    }

    // ─── CO2 factor management ──────────────────────────────────

    function test_SetCo2Factor() public {
        vm.prank(admin);
        platform.setCo2Factor(500);
        assertEq(platform.co2Factor(), 500);
    }

    function test_SetCo2FactorEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit Co2FactorUpdated(360, 500);
        platform.setCo2Factor(500);
    }

    function test_NonOwnerCannotSetCo2Factor() public {
        vm.prank(nobody);
        vm.expectRevert();
        platform.setCo2Factor(500);
    }

    // ─── Valence credit withdrawal ──────────────────────────────

    function test_WithdrawValenceCredits() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        platform.submitMRV(1, 15200);
        platform.withdrawValenceCredits(admin, 100 * ONE_CREDIT);
        vm.stopPrank();

        assertEq(token.balanceOf(admin), 100 * ONE_CREDIT);
        assertEq(token.balanceOf(address(platform)), (328 - 100) * ONE_CREDIT);
    }

    function test_WithdrawValenceCreditsEmitsEvent() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        platform.submitMRV(1, 15200);
        vm.expectEmit(true, true, false, true);
        emit TokensWithdrawn(admin, 50 * ONE_CREDIT);
        platform.withdrawValenceCredits(admin, 50 * ONE_CREDIT);
        vm.stopPrank();
    }

    function test_WithdrawMoreThanBalanceReverts() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        platform.submitMRV(1, 15200);
        vm.expectRevert();
        platform.withdrawValenceCredits(admin, 999 * ONE_CREDIT);
        vm.stopPrank();
    }

    function test_NonOwnerCannotWithdraw() public {
        vm.prank(nobody);
        vm.expectRevert();
        platform.withdrawValenceCredits(nobody, 1);
    }

    // ─── Integration scenario ───────────────────────────────────

    function test_FullWorkflow() public {
        // Register 3 sites
        vm.startPrank(admin);
        platform.registerSite("Bakken Basin A", "North Dakota", siteOwner1, 6000);
        platform.registerSite("Permian Basin B", "Texas", siteOwner2, 5000);
        platform.registerSite("Marcellus C", "Pennsylvania", siteOwner1, 5500);
        platform.setDataSubmitter(submitter, true);
        vm.stopPrank();

        // Submit MRV data for each site
        vm.startPrank(submitter);
        platform.submitMRV(1, 80000);  // 2880 credits
        platform.submitMRV(2, 60000);  // 2160 credits
        platform.submitMRV(3, 45000);  // 1620 credits
        platform.submitMRV(1, 90000);  // 3240 credits (second month)
        vm.stopPrank();

        // Check site totals
        ValencePlatform.Site memory s1 = platform.getSite(1);
        assertEq(s1.totalGasMCF, 170000);
        assertEq(s1.totalCredits, 6120); // 2880 + 3240

        ValencePlatform.Site memory s2 = platform.getSite(2);
        assertEq(s2.totalGasMCF, 60000);
        assertEq(s2.totalCredits, 2160);

        ValencePlatform.Site memory s3 = platform.getSite(3);
        assertEq(s3.totalGasMCF, 45000);
        assertEq(s3.totalCredits, 1620);

        // Site owner 1 credits: (2880*40%) + (3240*40%) + (1620*45%) = 1152 + 1296 + 729 = 3177
        assertEq(token.balanceOf(siteOwner1), 3177 * ONE_CREDIT);

        // Site owner 2 credits: 2160*50% = 1080
        assertEq(token.balanceOf(siteOwner2), 1080 * ONE_CREDIT);

        // Platform (Valence) credits: (2880*60%) + (2160*50%) + (1620*55%) + (3240*60%) = 1728 + 1080 + 891 + 1944 = 5643
        assertEq(token.balanceOf(address(platform)), 5643 * ONE_CREDIT);

        // Total supply
        assertEq(token.totalSupply(), (6120 + 2160 + 1620) * ONE_CREDIT);

        // Valence withdraws to their wallet
        vm.prank(admin);
        platform.withdrawValenceCredits(admin, 2000 * ONE_CREDIT);
        assertEq(token.balanceOf(admin), 2000 * ONE_CREDIT);
        assertEq(platform.platformCreditBalance(), (5643 - 2000) * ONE_CREDIT);
    }

    // ─── Token burn (retirement) ────────────────────────────────

    function test_SiteOwnerCanBurnCredits() public {
        vm.startPrank(admin);
        platform.registerSite("Site A", "ND", siteOwner1, 6000);
        platform.submitMRV(1, 15200);
        vm.stopPrank();

        // Site owner retires some credits
        vm.prank(siteOwner1);
        token.burn(100 * ONE_CREDIT);

        assertEq(token.balanceOf(siteOwner1), (219 - 100) * ONE_CREDIT);
        assertEq(token.totalSupply(), (547 - 100) * ONE_CREDIT);
    }

    // ─── Edge case: very small volume ───────────────────────────

    function test_SubmitMRVSmallVolume() public {
        vm.startPrank(admin);
        platform.registerSite("Small Site", "ND", siteOwner1, 6000);
        vm.stopPrank();

        // 1 MCF * 360 / 10000 = 0 → should revert
        vm.prank(submitter);
        vm.expectRevert();
        platform.submitMRV(1, 1);
    }

    function test_SubmitMRVMinimumViableVolume() public {
        vm.startPrank(admin);
        platform.registerSite("Min Site", "ND", siteOwner1, 6000);
        vm.stopPrank();

        // 28 MCF * 360 / 10000 = 1.008 → 1 credit
        vm.prank(submitter);
        platform.submitMRV(1, 28);

        assertEq(platform.getMRV(1).creditsIssued, 1);
    }

    function test_GetInvalidSiteReverts() public {
        vm.expectRevert();
        platform.getSite(0);
        vm.expectRevert();
        platform.getSite(99);
    }

    function test_GetInvalidMRVReverts() public {
        vm.expectRevert();
        platform.getMRV(0);
        vm.expectRevert();
        platform.getMRV(99);
    }

    // ─── Rounding ───────────────────────────────────────────────

    function test_CreditsRoundedDown() public {
        vm.startPrank(admin);
        platform.registerSite("Rounding", "ND", siteOwner1, 6000);
        vm.stopPrank();

        // 100 * 360 / 10000 = 3.6 → rounds to 3
        vm.prank(submitter);
        platform.submitMRV(1, 100);
        assertEq(platform.getMRV(1).creditsIssued, 3);
    }
}
