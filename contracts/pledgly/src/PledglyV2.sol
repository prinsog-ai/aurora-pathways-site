// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PledglyV2 — Decentralised Creator Subscription Platform
 * @notice Patreon alternative: creators earn USDC from subscribers.
 *         Subscribers get an NFT proving their subscription (token-gating).
 *         3% platform fee, instant payouts, no middleman.
 */
contract PledglyV2 is ERC721, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Constants ──────────────────────────────────────────────────────

    IERC20 public immutable usdc;
    uint256 public constant PLATFORM_FEE_BPS = 300; // 3%
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant SUBSCRIPTION_DURATION = 30 days;

    // ─── Structs ────────────────────────────────────────────────────────

    struct Creator {
        string name;
        string bio;
        string avatarURI;
        bool registered;
        address wallet;
        uint256 totalEarned;
        uint256 subscriberCount;
    }

    struct Tier {
        string name;
        string description;
        uint256 priceUSDC;
        bool active;
    }

    struct Subscription {
        uint256 creatorId;
        uint256 tierId;
        uint256 startTime;
        uint256 expiry;
        bool active;
    }

    struct Content {
        uint256 creatorId;
        string title;
        string contentURI;
        uint256 minTierId;
        uint256 timestamp;
        bool exists;
    }

    // ─── State ──────────────────────────────────────────────────────────

    uint256 public nextCreatorId = 1;
    uint256 public nextContentId = 1;
    uint256 public nextTokenId = 1;
    uint256 public totalPlatformFees;

    mapping(uint256 => Creator) public creators;
    mapping(uint256 => mapping(uint256 => Tier)) public tiers;
    mapping(uint256 => uint256) public nextTierId;
    mapping(uint256 => Subscription) public subscriptions;
    mapping(uint256 => Content) public contents;
    mapping(uint256 => uint256[]) public creatorContent;
    mapping(address => uint256) public addressToCreator;
    mapping(address => mapping(uint256 => uint256)) public activeSubCount;

    // User => list of their subscription token IDs
    mapping(address => uint256[]) public userTokens;

    // ─── Events ─────────────────────────────────────────────────────────

    event CreatorRegistered(uint256 indexed creatorId, address indexed wallet, string name);
    event TierCreated(uint256 indexed creatorId, uint256 indexed tierId, string name, uint256 price);
    event TierUpdated(uint256 indexed creatorId, uint256 indexed tierId, bool active);
    event Subscribed(uint256 indexed tokenId, address indexed subscriber, uint256 indexed creatorId, uint256 tierId, uint256 expiry);
    event Renewed(uint256 indexed tokenId, address indexed subscriber, uint256 indexed creatorId, uint256 newExpiry);
    event ContentPosted(uint256 indexed contentId, uint256 indexed creatorId, uint256 minTierId);
    event Unsubscribed(uint256 indexed tokenId, address indexed subscriber, uint256 indexed creatorId);
    event PlatformFeesWithdrawn(address indexed to, uint256 amount);

    // ─── Errors ─────────────────────────────────────────────────────────

    error AlreadyRegistered();
    error NotRegistered();
    error TierInactive();
    error NotSubscriber();
    error ContentNotFound();
    error InvalidPrice();
    error NotOwner();

    // ─── Constructor ────────────────────────────────────────────────────

    constructor(address _usdc)
        ERC721("Pledgly Subscriber", "PLEDGLY")
        Ownable(msg.sender)
    {
        usdc = IERC20(_usdc);
    }

    // ─── Creator Functions ──────────────────────────────────────────────

    function registerCreator(
        string calldata _name,
        string calldata _bio,
        string calldata _avatarURI
    ) external {
        if (addressToCreator[msg.sender] != 0) revert AlreadyRegistered();

        uint256 creatorId = nextCreatorId++;
        creators[creatorId] = Creator({
            name: _name,
            bio: _bio,
            avatarURI: _avatarURI,
            registered: true,
            wallet: msg.sender,
            totalEarned: 0,
            subscriberCount: 0
        });
        addressToCreator[msg.sender] = creatorId;
        nextTierId[creatorId] = 1;

        emit CreatorRegistered(creatorId, msg.sender, _name);
    }

    function createTier(
        string calldata _name,
        string calldata _description,
        uint256 _priceUSDC
    ) external returns (uint256) {
        uint256 creatorId = addressToCreator[msg.sender];
        if (creatorId == 0) revert NotRegistered();
        if (_priceUSDC == 0) revert InvalidPrice();

        uint256 tierId = nextTierId[creatorId]++;
        tiers[creatorId][tierId] = Tier({
            name: _name,
            description: _description,
            priceUSDC: _priceUSDC,
            active: true
        });

        emit TierCreated(creatorId, tierId, _name, _priceUSDC);
        return tierId;
    }

    function updateTier(uint256 _tierId, bool _active) external {
        uint256 creatorId = addressToCreator[msg.sender];
        if (creatorId == 0) revert NotRegistered();

        tiers[creatorId][_tierId].active = _active;
        emit TierUpdated(creatorId, _tierId, _active);
    }

    function updateCreatorProfile(
        string calldata _bio,
        string calldata _avatarURI
    ) external {
        uint256 creatorId = addressToCreator[msg.sender];
        if (creatorId == 0) revert NotRegistered();

        creators[creatorId].bio = _bio;
        creators[creatorId].avatarURI = _avatarURI;
    }

    // ─── Subscriber Functions ───────────────────────────────────────────

    function subscribe(uint256 _creatorId, uint256 _tierId) external nonReentrant returns (uint256) {
        Creator storage creator = creators[_creatorId];
        if (!creator.registered) revert NotRegistered();

        Tier storage tier = tiers[_creatorId][_tierId];
        if (!tier.active) revert TierInactive();

        uint256 creatorAmount = (tier.priceUSDC * (BPS_DENOMINATOR - PLATFORM_FEE_BPS)) / BPS_DENOMINATOR;
        uint256 feeAmount = tier.priceUSDC - creatorAmount;

        usdc.safeTransferFrom(msg.sender, creator.wallet, creatorAmount);
        usdc.safeTransferFrom(msg.sender, owner(), feeAmount);
        totalPlatformFees += feeAmount;
        creator.totalEarned += creatorAmount;

        uint256 tokenId = nextTokenId++;
        _safeMint(msg.sender, tokenId);

        uint256 expiry = block.timestamp + SUBSCRIPTION_DURATION;
        subscriptions[tokenId] = Subscription({
            creatorId: _creatorId,
            tierId: _tierId,
            startTime: block.timestamp,
            expiry: expiry,
            active: true
        });

        activeSubCount[msg.sender][_creatorId] += 1;
        userTokens[msg.sender].push(tokenId);
        creator.subscriberCount++;

        emit Subscribed(tokenId, msg.sender, _creatorId, _tierId, expiry);
        return tokenId;
    }

    function renew(uint256 _tokenId) external nonReentrant {
        Subscription storage sub = subscriptions[_tokenId];
        if (!sub.active) revert NotRegistered();
        if (ownerOf(_tokenId) != msg.sender) revert NotOwner();

        Creator storage creator = creators[sub.creatorId];
        Tier storage tier = tiers[sub.creatorId][sub.tierId];

        uint256 creatorAmount = (tier.priceUSDC * (BPS_DENOMINATOR - PLATFORM_FEE_BPS)) / BPS_DENOMINATOR;
        uint256 feeAmount = tier.priceUSDC - creatorAmount;

        usdc.safeTransferFrom(msg.sender, creator.wallet, creatorAmount);
        usdc.safeTransferFrom(msg.sender, owner(), feeAmount);
        totalPlatformFees += feeAmount;
        creator.totalEarned += creatorAmount;

        if (sub.expiry > block.timestamp) {
            sub.expiry += SUBSCRIPTION_DURATION;
        } else {
            sub.expiry = block.timestamp + SUBSCRIPTION_DURATION;
            activeSubCount[msg.sender][sub.creatorId] += 1;
        }

        emit Renewed(_tokenId, msg.sender, sub.creatorId, sub.expiry);
    }

    function cancelSubscription(uint256 _tokenId) external {
        Subscription storage sub = subscriptions[_tokenId];
        if (ownerOf(_tokenId) != msg.sender) revert NotOwner();
        if (!sub.active) revert NotRegistered();

        sub.active = false;
        sub.expiry = block.timestamp;
        activeSubCount[msg.sender][sub.creatorId] -= 1;
        creators[sub.creatorId].subscriberCount--;

        emit Unsubscribed(_tokenId, msg.sender, sub.creatorId);
    }

    // ─── Content Functions ──────────────────────────────────────────────

    function postContent(
        string calldata _title,
        string calldata _contentURI,
        uint256 _minTierId
    ) external returns (uint256) {
        uint256 creatorId = addressToCreator[msg.sender];
        if (creatorId == 0) revert NotRegistered();

        uint256 contentId = nextContentId++;
        contents[contentId] = Content({
            creatorId: creatorId,
            title: _title,
            contentURI: _contentURI,
            minTierId: _minTierId,
            timestamp: block.timestamp,
            exists: true
        });

        creatorContent[creatorId].push(contentId);

        emit ContentPosted(contentId, creatorId, _minTierId);
        return contentId;
    }

    // ─── View Functions ─────────────────────────────────────────────────

    function isSubscribedTo(address _user, uint256 _creatorId) external view returns (bool) {
        return activeSubCount[_user][_creatorId] > 0;
    }

    function isSubscriptionActive(uint256 _tokenId) external view returns (bool) {
        Subscription storage sub = subscriptions[_tokenId];
        return sub.active && sub.expiry > block.timestamp;
    }

    function getSubscriptionExpiry(uint256 _tokenId) external view returns (uint256) {
        return subscriptions[_tokenId].expiry;
    }

    function canAccessContent(address _user, uint256 _contentId) external view returns (bool) {
        Content storage content = contents[_contentId];
        if (!content.exists) return false;

        uint256[] storage tokens = userTokens[_user];
        for (uint256 i = 0; i < tokens.length; i++) {
            Subscription storage sub = subscriptions[tokens[i]];
            if (sub.creatorId == content.creatorId && sub.active && sub.expiry > block.timestamp) {
                if (sub.tierId >= content.minTierId) {
                    return true;
                }
            }
        }
        return false;
    }

    function getContentURI(address _user, uint256 _contentId) external view returns (string memory) {
        Content storage content = contents[_contentId];
        if (!content.exists) revert ContentNotFound();

        uint256[] storage tokens = userTokens[_user];
        for (uint256 i = 0; i < tokens.length; i++) {
            Subscription storage sub = subscriptions[tokens[i]];
            if (sub.creatorId == content.creatorId && sub.active && sub.expiry > block.timestamp) {
                if (sub.tierId >= content.minTierId) {
                    return content.contentURI;
                }
            }
        }
        revert NotSubscriber();
    }

    function getCreatorContent(uint256 _creatorId) external view returns (uint256[] memory) {
        return creatorContent[_creatorId];
    }

    function getCreatorTiers(uint256 _creatorId) external view returns (Tier[] memory) {
        uint256 count = nextTierId[_creatorId] - 1;
        Tier[] memory result = new Tier[](count);
        for (uint256 i = 1; i <= count; i++) {
            result[i - 1] = tiers[_creatorId][i];
        }
        return result;
    }

    function getUserSubscriptions(address _user) external view returns (uint256[] memory) {
        return userTokens[_user];
    }

    // ─── Admin Functions ────────────────────────────────────────────────

    function withdrawPlatformFees() external onlyOwner nonReentrant {
        uint256 balance = usdc.balanceOf(address(this));
        if (balance == 0) return;

        totalPlatformFees = 0;
        usdc.safeTransfer(owner(), balance);
        emit PlatformFeesWithdrawn(owner(), balance);
    }
}
