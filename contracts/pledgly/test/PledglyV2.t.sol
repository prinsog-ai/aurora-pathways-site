// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PledglyV2.sol";
import "../src/MockUSDC.sol";

contract PledglyV2Test is Test {
    PledglyV2 pledgly;
    MockUSDC usdc;

    address creator = address(0x1);
    address subscriber = address(0x2);
    address platformOwner = address(0x3);

    uint256 constant SUBSCRIPTION_AMOUNT = 10 * 1e6; // 10 USDC
    uint256 constant SMALL_AMOUNT = 5 * 1e6;         // 5 USDC

    function setUp() public {
        usdc = new MockUSDC("Mock USDC", "mUSDC", 6);
        vm.startPrank(platformOwner);
        pledgly = new PledglyV2(address(usdc));
        vm.stopPrank();

        // Mint USDC to subscriber
        usdc.mint(subscriber, 1000 * 1e6);

        // Approve pledgly to spend subscriber's USDC
        vm.startPrank(subscriber);
        usdc.approve(address(pledgly), type(uint256).max);
        vm.stopPrank();
    }

    // ─── Creator Registration ──────────────────────────────────────────

    function test_registerCreator() public {
        vm.startPrank(creator);
        pledgly.registerCreator("TestCreator", "I make cool stuff", "ipfs://avatar");

        (string memory name, string memory bio, string memory avatarURI, bool registered, address wallet, uint256 totalEarned, uint256 subscriberCount) = pledgly.creators(1);

        assertEq(name, "TestCreator");
        assertEq(bio, "I make cool stuff");
        assertEq(avatarURI, "ipfs://avatar");
        assertTrue(registered);
        assertEq(wallet, creator);
        assertEq(totalEarned, 0);
        assertEq(subscriberCount, 0);
        assertEq(pledgly.addressToCreator(creator), 1);
        vm.stopPrank();
    }

    function test_registerCreator_revertsIfAlreadyRegistered() public {
        vm.startPrank(creator);
        pledgly.registerCreator("TestCreator", "Bio", "ipfs://avatar");

        vm.expectRevert(PledglyV2.AlreadyRegistered.selector);
        pledgly.registerCreator("TestCreator2", "Bio2", "ipfs://avatar2");
        vm.stopPrank();
    }

    // ─── Tier Creation ─────────────────────────────────────────────────

    function test_createTier() public {
        vm.startPrank(creator);
        pledgly.registerCreator("TestCreator", "Bio", "ipfs://avatar");

        uint256 tierId = pledgly.createTier("Basic", "Access to posts", SUBSCRIPTION_AMOUNT);
        assertEq(tierId, 1);

        (string memory name, string memory description, uint256 price, bool active) = pledgly.tiers(1, 1);
        assertEq(name, "Basic");
        assertEq(description, "Access to posts");
        assertEq(price, SUBSCRIPTION_AMOUNT);
        assertTrue(active);
        vm.stopPrank();
    }

    function test_createTier_revertsIfNotRegistered() public {
        vm.startPrank(creator);
        vm.expectRevert(PledglyV2.NotRegistered.selector);
        pledgly.createTier("Basic", "Access", SUBSCRIPTION_AMOUNT);
        vm.stopPrank();
    }

    function test_createTier_revertsIfZeroPrice() public {
        vm.startPrank(creator);
        pledgly.registerCreator("TestCreator", "Bio", "ipfs://avatar");

        vm.expectRevert(PledglyV2.InvalidPrice.selector);
        pledgly.createTier("Free", "Free tier", 0);
        vm.stopPrank();
    }

    // ─── Subscribing ───────────────────────────────────────────────────

    function test_subscribe() public {
        _setupCreatorWithTier();

        uint256 creatorBalBefore = usdc.balanceOf(creator);
        uint256 platformBalBefore = usdc.balanceOf(platformOwner);

        vm.startPrank(subscriber);
        uint256 tokenId = pledgly.subscribe(1, 1);

        // Check NFT minted
        assertEq(pledgly.ownerOf(tokenId), subscriber);
        assertEq(pledgly.balanceOf(subscriber), 1);

        // Check subscription state
        (uint256 cId, uint256 tId, uint256 startTime, uint256 expiry, bool active) = pledgly.subscriptions(tokenId);
        assertEq(cId, 1);
        assertEq(tId, 1);
        assertEq(expiry, block.timestamp + 30 days);
        assertTrue(active);

        // Check USDC split (97% creator, 3% platform)
        uint256 expectedCreatorAmount = (SUBSCRIPTION_AMOUNT * 9700) / 10000;
        uint256 expectedFee = SUBSCRIPTION_AMOUNT - expectedCreatorAmount;

        assertEq(usdc.balanceOf(creator) - creatorBalBefore, expectedCreatorAmount);
        assertEq(usdc.balanceOf(platformOwner) - platformBalBefore, expectedFee);

        // Check creator stats
        (,,,,,,uint256 subscriberCount) = pledgly.creators(1);
        assertEq(subscriberCount, 1);

        assertTrue(pledgly.isSubscribedTo(subscriber, 1));
        vm.stopPrank();
    }

    function test_subscribe_revertsIfTierInactive() public {
        _setupCreatorWithTier();

        vm.startPrank(creator);
        pledgly.updateTier(1, false);
        vm.stopPrank();

        vm.startPrank(subscriber);
        vm.expectRevert(PledglyV2.TierInactive.selector);
        pledgly.subscribe(1, 1);
        vm.stopPrank();
    }

    function test_subscribe_revertsIfCreatorNotRegistered() public {
        vm.startPrank(subscriber);
        vm.expectRevert(PledglyV2.NotRegistered.selector);
        pledgly.subscribe(99, 1);
        vm.stopPrank();
    }

    // ─── Renewing ──────────────────────────────────────────────────────

    function test_renew_beforeExpiry() public {
        _setupCreatorWithTier();

        vm.startPrank(subscriber);
        uint256 tokenId = pledgly.subscribe(1, 1);

        uint256 oldExpiry = pledgly.getSubscriptionExpiry(tokenId);

        // Renew before expiry
        pledgly.renew(tokenId);

        uint256 newExpiry = pledgly.getSubscriptionExpiry(tokenId);
        assertEq(newExpiry, oldExpiry + 30 days);
        vm.stopPrank();
    }

    function test_renew_afterExpiry() public {
        _setupCreatorWithTier();

        vm.startPrank(subscriber);
        uint256 tokenId = pledgly.subscribe(1, 1);

        // Fast forward past expiry
        vm.warp(block.timestamp + 31 days);

        assertFalse(pledgly.isSubscriptionActive(tokenId));

        // Renew after expiry
        pledgly.renew(tokenId);

        assertTrue(pledgly.isSubscriptionActive(tokenId));
        assertTrue(pledgly.isSubscribedTo(subscriber, 1));
        vm.stopPrank();
    }

    // ─── Cancel ────────────────────────────────────────────────────────

    function test_cancelSubscription() public {
        _setupCreatorWithTier();

        vm.startPrank(subscriber);
        uint256 tokenId = pledgly.subscribe(1, 1);
        assertTrue(pledgly.isSubscriptionActive(tokenId));

        pledgly.cancelSubscription(tokenId);

        assertFalse(pledgly.isSubscriptionActive(tokenId));
        assertFalse(pledgly.isSubscribedTo(subscriber, 1));

        (,,, uint256 expiry, bool active) = pledgly.subscriptions(tokenId);
        assertFalse(active);

        (,,,,,, uint256 subscriberCount) = pledgly.creators(1);
        assertEq(subscriberCount, 0);
        vm.stopPrank();
    }

    // ─── Content + Token Gating ────────────────────────────────────────

    function test_postContent() public {
        _setupCreatorWithTier();

        vm.startPrank(creator);
        uint256 contentId = pledgly.postContent("Exclusive Post", "ipfs://content123", 1);

        (uint256 cId,, string memory contentURI, uint256 minTierId,, bool exists) = pledgly.contents(contentId);
        assertEq(cId, 1);
        assertEq(contentURI, "ipfs://content123");
        assertEq(minTierId, 1);
        assertTrue(exists);
        vm.stopPrank();
    }

    function test_canAccessContent_withCorrectTier() public {
        _setupCreatorWithTier();

        vm.startPrank(creator);
        uint256 contentId = pledgly.postContent("Exclusive Post", "ipfs://content123", 1);
        vm.stopPrank();

        vm.startPrank(subscriber);
        uint256 tokenId = pledgly.subscribe(1, 1);

        assertTrue(pledgly.canAccessContent(subscriber, contentId));

        string memory uri = pledgly.getContentURI(subscriber, contentId);
        assertEq(uri, "ipfs://content123");
        vm.stopPrank();
    }

    function test_cannotAccessContent_withInsufficientTier() public {
        _setupCreatorWithTier();

        // Create a higher tier
        vm.startPrank(creator);
        pledgly.createTier("Premium", "All access", 50 * 1e6);
        uint256 contentId = pledgly.postContent("Premium Only", "ipfs://premium", 2); // requires tier 2
        vm.stopPrank();

        vm.startPrank(subscriber);
        pledgly.subscribe(1, 1); // subscribed to tier 1

        assertFalse(pledgly.canAccessContent(subscriber, contentId));

        vm.expectRevert(PledglyV2.NotSubscriber.selector);
        pledgly.getContentURI(subscriber, contentId);
        vm.stopPrank();
    }

    function test_cannotAccessContent_afterExpiry() public {
        _setupCreatorWithTier();

        vm.startPrank(creator);
        uint256 contentId = pledgly.postContent("Exclusive", "ipfs://content", 1);
        vm.stopPrank();

        vm.startPrank(subscriber);
        pledgly.subscribe(1, 1);

        // Fast forward past expiry
        vm.warp(block.timestamp + 31 days);

        assertFalse(pledgly.canAccessContent(subscriber, contentId));
        vm.stopPrank();
    }

    function test_cannotAccessContent_noSubscription() public {
        _setupCreatorWithTier();

        vm.startPrank(creator);
        uint256 contentId = pledgly.postContent("Exclusive", "ipfs://content", 1);
        vm.stopPrank();

        assertFalse(pledgly.canAccessContent(subscriber, contentId));
    }

    // ─── View Functions ────────────────────────────────────────────────

    function test_getCreatorContent() public {
        _setupCreatorWithTier();

        vm.startPrank(creator);
        pledgly.postContent("Post 1", "ipfs://1", 0);
        pledgly.postContent("Post 2", "ipfs://2", 1);
        pledgly.postContent("Post 3", "ipfs://3", 1);
        vm.stopPrank();

        uint256[] memory contentIds = pledgly.getCreatorContent(1);
        assertEq(contentIds.length, 3);
        assertEq(contentIds[0], 1);
        assertEq(contentIds[1], 2);
        assertEq(contentIds[2], 3);
    }

    function test_getCreatorTiers() public {
        _setupCreatorWithTier();

        vm.startPrank(creator);
        pledgly.createTier("Premium", "All access", 50 * 1e6);
        vm.stopPrank();

        PledglyV2.Tier[] memory tierList = pledgly.getCreatorTiers(1);
        assertEq(tierList.length, 2);
        assertEq(tierList[0].name, "Basic");
        assertEq(tierList[1].name, "Premium");
    }

    function test_getUserSubscriptions() public {
        _setupCreatorWithTier();

        vm.startPrank(subscriber);
        pledgly.subscribe(1, 1);

        uint256[] memory tokenIds = pledgly.getUserSubscriptions(subscriber);
        assertEq(tokenIds.length, 1);
        assertEq(tokenIds[0], 1);
        vm.stopPrank();
    }

    // ─── Platform Fees ─────────────────────────────────────────────────

    function test_withdrawPlatformFees() public {
        _setupCreatorWithTier();

        vm.startPrank(subscriber);
        pledgly.subscribe(1, 1);
        vm.stopPrank();

        uint256 expectedFee = (SUBSCRIPTION_AMOUNT * 300) / 10000; // 3%

        vm.startPrank(platformOwner);
        uint256 balBefore = usdc.balanceOf(platformOwner);
        pledgly.withdrawPlatformFees();

        // Fees already sent to platformOwner during subscribe, so this drains any held balance
        // The contract itself shouldn't hold fees (they go directly to owner in subscribe)
        assertEq(usdc.balanceOf(address(pledgly)), 0);
        vm.stopPrank();
    }

    // ─── Edge Cases ────────────────────────────────────────────────────

    function test_multipleSubscribers() public {
        _setupCreatorWithTier();

        address sub2 = address(0x4);
        usdc.mint(sub2, 1000 * 1e6);
        vm.startPrank(sub2);
        usdc.approve(address(pledgly), type(uint256).max);
        pledgly.subscribe(1, 1);
        vm.stopPrank();

        vm.startPrank(subscriber);
        pledgly.subscribe(1, 1);
        vm.stopPrank();

        (,,,,,, uint256 subscriberCount) = pledgly.creators(1);
        assertEq(subscriberCount, 2);
    }

    function test_contentWithTier0_accessibleToAll() public {
        _setupCreatorWithTier();

        vm.startPrank(creator);
        uint256 contentId = pledgly.postContent("Public Post", "ipfs://public", 0);
        vm.stopPrank();

        // Tier 1 subscriber can access tier 0 content
        vm.startPrank(subscriber);
        pledgly.subscribe(1, 1);
        assertTrue(pledgly.canAccessContent(subscriber, contentId));
        vm.stopPrank();
    }

    function test_updateTier() public {
        _setupCreatorWithTier();

        vm.startPrank(creator);
        pledgly.updateTier(1, false);

        (,,, bool active) = pledgly.tiers(1, 1);
        assertFalse(active);

        // Re-activate
        pledgly.updateTier(1, true);
        (,,, active) = pledgly.tiers(1, 1);
        assertTrue(active);
        vm.stopPrank();
    }

    // ─── Helpers ────────────────────────────────────────────────────────

    function _setupCreatorWithTier() internal {
        vm.startPrank(creator);
        pledgly.registerCreator("TestCreator", "Bio", "ipfs://avatar");
        pledgly.createTier("Basic", "Access to posts", SUBSCRIPTION_AMOUNT);
        vm.stopPrank();
    }
}
