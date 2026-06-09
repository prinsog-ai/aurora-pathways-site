// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Pledgly — Decentralised Charity Donation Platform
 * @notice Allows anyone to create fundraising campaigns denominated in USDC.
 *         Donors contribute USDC; if the goal is met the creator can withdraw
 *         (minus a 2 % platform fee) after milestone approval. If the goal is
 *         NOT met by the deadline, donors may claim full refunds.
 *
 * @dev Deployed on Polygon Amoy.  Uses OpenZeppelin v5.
 */
contract Pledgly is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Enums ──────────────────────────────────────────────────────────

    enum Category {
        Emergency,
        Education,
        Healthcare,
        Environment,
        Community,
        Other
    }

    enum CampaignStatus {
        Active,       // open for donations
        Successful,   // goal met, withdrawals allowed
        Failed,       // deadline passed without goal — refunds enabled
        Completed     // all milestones approved & funds released
    }

    // ─── Structs ────────────────────────────────────────────────────────

    struct Milestone {
        string  description;
        string  proofURI;       // IPFS / Arweave link to proof of work
        uint256 amount;         // USDC amount to release on approval
        uint256 votesFor;
        uint256 votesAgainst;
        bool    approved;
        bool    exists;
    }

    struct Campaign {
        uint256     id;
        address     creator;
        string      title;
        string      description;
        uint256     goalAmount;       // in USDC (6 decimals)
        uint256     raisedAmount;
        uint256     deadline;         // unix timestamp
        Category    category;
        CampaignStatus status;
        uint256     milestoneCount;
        uint256     releasedAmount;   // total USDC released via milestones
    }

    // ─── State ──────────────────────────────────────────────────────────

    IERC20 public immutable usdc;
    IERC20 public immutable governanceToken;   // used for milestone votes

    uint256 public platformFeeBps = 200;        // 2 %
    address public feeRecipient;

    uint256 public campaignCount;
    uint256[] public allCampaignIds;            // for pagination

    /// @dev campaignId ⇒ Campaign
    mapping(uint256 => Campaign) public campaigns;

    /// @dev campaignId ⇒ donor ⇒ donated amount
    mapping(uint256 => mapping(address => uint256)) public donations;

    /// @dev campaignId ⇒ list of unique donor addresses
    mapping(uint256 => address[]) internal campaignDonors;

    /// @dev campaignId ⇒ milestoneIndex ⇒ Milestone
    mapping(uint256 => mapping(uint256 => Milestone)) public milestones;

    /// @dev campaignId ⇒ milestoneIndex ⇒ voter ⇒ has voted
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public hasVoted;

    // ─── Events ─────────────────────────────────────────────────────────

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        string  title,
        uint256 goalAmount,
        uint256 deadline,
        Category category
    );

    event DonationReceived(
        uint256 indexed campaignId,
        address indexed donor,
        uint256 amount
    );

    event RefundClaimed(
        uint256 indexed campaignId,
        address indexed donor,
        uint256 amount
    );

    event CampaignUpdate(
        uint256 indexed campaignId,
        string  updateText
    );

    event MilestoneSubmitted(
        uint256 indexed campaignId,
        uint256 indexed milestoneIndex,
        string  description,
        uint256 amount
    );

    event MilestoneApproved(
        uint256 indexed campaignId,
        uint256 indexed milestoneIndex,
        uint256 amount
    );

    event CampaignCompleted(
        uint256 indexed campaignId,
        uint256 totalReleased
    );

    // ─── Constructor ────────────────────────────────────────────────────

    /**
     * @param _usdc            Address of the USDC ERC-20 token
     * @param _governanceToken Address of the governance ERC-20 token
     * @param _feeRecipient    Address to receive the 2 % platform fee
     */
    constructor(
        address _usdc,
        address _governanceToken,
        address _feeRecipient
    ) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC");
        require(_governanceToken != address(0), "Invalid governance token");
        require(_feeRecipient != address(0), "Invalid fee recipient");

        usdc            = IERC20(_usdc);
        governanceToken = IERC20(_governanceToken);
        feeRecipient    = _feeRecipient;
    }

    // ─── Admin ──────────────────────────────────────────────────────────

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid address");
        feeRecipient = _feeRecipient;
    }

    function setPlatformFeeBps(uint256 _bps) external onlyOwner {
        require(_bps <= 1000, "Fee too high"); // max 10 %
        platformFeeBps = _bps;
    }

    // ─── Campaign Creation ──────────────────────────────────────────────

    /**
     * @notice Create a new fundraising campaign.
     * @param _title       Human-readable title
     * @param _description Longer description
     * @param _goalAmount  Target amount in USDC (6 decimals)
     * @param _deadline    Unix timestamp after which the campaign expires
     * @param _category    Category enum value
     * @return campaignId  The id of the newly created campaign
     */
    function createCampaign(
        string calldata _title,
        string calldata _description,
        uint256 _goalAmount,
        uint256 _deadline,
        Category _category
    ) external returns (uint256 campaignId) {
        require(bytes(_title).length > 0, "Empty title");
        require(_goalAmount > 0, "Goal must be > 0");
        require(_deadline > block.timestamp, "Deadline must be in the future");

        campaignId = ++campaignCount;

        Campaign storage c = campaigns[campaignId];
        c.id           = campaignId;
        c.creator      = msg.sender;
        c.title        = _title;
        c.description  = _description;
        c.goalAmount   = _goalAmount;
        c.deadline     = _deadline;
        c.category     = _category;
        c.status       = CampaignStatus.Active;

        allCampaignIds.push(campaignId);

        emit CampaignCreated(campaignId, msg.sender, _title, _goalAmount, _deadline, _category);
    }

    // ─── Donations ──────────────────────────────────────────────────────

    /**
     * @notice Donate USDC to a campaign.
     * @param _campaignId Target campaign id
     * @param _amount     Amount of USDC to donate
     */
    function donate(uint256 _campaignId, uint256 _amount) external nonReentrant {
        Campaign storage c = campaigns[_campaignId];
        require(c.id != 0, "Campaign does not exist");
        require(c.status == CampaignStatus.Active, "Campaign not active");
        require(block.timestamp <= c.deadline, "Campaign has ended");
        require(_amount > 0, "Amount must be > 0");

        // Record first-time donor for this campaign
        if (donations[_campaignId][msg.sender] == 0) {
            campaignDonors[_campaignId].push(msg.sender);
        }

        // Transfer USDC from donor → contract
        usdc.safeTransferFrom(msg.sender, address(this), _amount);

        donations[_campaignId][msg.sender] += _amount;
        c.raisedAmount += _amount;

        emit DonationReceived(_campaignId, msg.sender, _amount);
    }

    // ─── Finalise / Activate refund window ──────────────────────────────

    /**
     * @notice Finalise a campaign after its deadline.
     *         If goal was met → status becomes Successful.
     *         If goal was NOT met → status becomes Failed (refunds enabled).
     *         Can be called by anyone.
     */
    function finaliseCampaign(uint256 _campaignId) external {
        Campaign storage c = campaigns[_campaignId];
        require(c.id != 0, "Campaign does not exist");
        require(c.status == CampaignStatus.Active, "Not active");
        require(block.timestamp > c.deadline, "Deadline not passed");

        if (c.raisedAmount >= c.goalAmount) {
            c.status = CampaignStatus.Successful;
        } else {
            c.status = CampaignStatus.Failed;
        }
    }

    // ─── Refunds ────────────────────────────────────────────────────────

    /**
     * @notice Claim a full refund if the campaign failed to reach its goal.
     */
    function claimRefund(uint256 _campaignId) external nonReentrant {
        Campaign storage c = campaigns[_campaignId];
        require(c.status == CampaignStatus.Failed, "Campaign did not fail");

        uint256 donated = donations[_campaignId][msg.sender];
        require(donated > 0, "Nothing to refund");

        donations[_campaignId][msg.sender] = 0;
        c.raisedAmount -= donated;

        usdc.safeTransfer(msg.sender, donated);

        emit RefundClaimed(_campaignId, msg.sender, donated);
    }

    // ─── Milestones ─────────────────────────────────────────────────────

    /**
     * @notice Creator submits a milestone for community voting.
     * @param _campaignId    Campaign id
     * @param _description   Human-readable milestone description
     * @param _proofURI      IPFS / Arweave URI for proof of work
     * @param _amount        USDC amount to release if approved
     */
    function submitMilestone(
        uint256 _campaignId,
        string calldata _description,
        string calldata _proofURI,
        uint256 _amount
    ) external {
        Campaign storage c = campaigns[_campaignId];
        require(c.creator == msg.sender, "Not campaign creator");
        require(
            c.status == CampaignStatus.Successful || c.status == CampaignStatus.Active,
            "Invalid campaign status"
        );
        require(_amount > 0, "Amount must be > 0");

        // Total released + new milestone must not exceed raised (minus fee buffer)
        uint256 totalReleasable = c.raisedAmount - ((c.raisedAmount * platformFeeBps) / 10_000);
        require(c.releasedAmount + _amount <= totalReleasable, "Exceeds available funds");

        uint256 idx = c.milestoneCount++;

        Milestone storage m = milestones[_campaignId][idx];
        m.description = _description;
        m.proofURI    = _proofURI;
        m.amount      = _amount;
        m.exists      = true;

        emit MilestoneSubmitted(_campaignId, idx, _description, _amount);
    }

    /**
     * @notice Vote on a milestone using governance token holdings.
     *         1 token = 1 vote (weight checked at vote time).
     * @param _campaignId      Campaign id
     * @param _milestoneIndex  Index of the milestone
     * @param _inFavour        true = For, false = Against
     */
    function voteMilestone(
        uint256 _campaignId,
        uint256 _milestoneIndex,
        bool _inFavour
    ) external {
        Milestone storage m = milestones[_campaignId][_milestoneIndex];
        require(m.exists, "Milestone does not exist");
        require(!hasVoted[_campaignId][_milestoneIndex][msg.sender], "Already voted");

        hasVoted[_campaignId][_milestoneIndex][msg.sender] = true;

        uint256 weight = governanceToken.balanceOf(msg.sender);
        require(weight > 0, "No governance tokens");

        if (_inFavour) {
            m.votesFor += weight;
        } else {
            m.votesAgainst += weight;
        }
    }

    /**
     * @notice Approve & release funds for a milestone.
     *         Requires votesFor > votesAgainst.  Can be called by anyone.
     */
    function approveMilestone(
        uint256 _campaignId,
        uint256 _milestoneIndex
    ) external nonReentrant {
        Campaign storage c = campaigns[_campaignId];
        Milestone storage m = milestones[_campaignId][_milestoneIndex];
        require(m.exists, "Milestone does not exist");
        require(!m.approved, "Already approved");
        require(m.votesFor > m.votesAgainst, "Not approved by vote");

        m.approved = true;
        c.releasedAmount += m.amount;

        // Calculate fee portion for this milestone release
        uint256 fee = (m.amount * platformFeeBps) / 10_000;
        uint256 creatorAmount = m.amount - fee;

        // Transfer fee
        if (fee > 0) {
            usdc.safeTransfer(feeRecipient, fee);
        }
        // Transfer remaining to creator
        usdc.safeTransfer(c.creator, creatorAmount);

        emit MilestoneApproved(_campaignId, _milestoneIndex, m.amount);

        // Check if all raised funds have been released → complete campaign
        uint256 totalReleasable = c.raisedAmount - ((c.raisedAmount * platformFeeBps) / 10_000);
        if (c.releasedAmount >= totalReleasable) {
            c.status = CampaignStatus.Completed;
            emit CampaignCompleted(_campaignId, c.releasedAmount);
        }
    }

    // ─── Campaign Updates (events only) ─────────────────────────────────

    /**
     * @notice Post a text update for a campaign.  Stored as an event only.
     */
    function postUpdate(uint256 _campaignId, string calldata _updateText) external {
        Campaign storage c = campaigns[_campaignId];
        require(c.creator == msg.sender, "Not campaign creator");
        require(c.id != 0, "Campaign does not exist");

        emit CampaignUpdate(_campaignId, _updateText);
    }

    // ─── Read helpers ───────────────────────────────────────────────────

    /**
     * @notice Paginated list of all campaign ids.
     * @param _offset Start index
     * @param _limit  Max number of ids to return
     * @return ids    Array of campaign ids
     */
    function getCampaigns(uint256 _offset, uint256 _limit)
        external
        view
        returns (uint256[] memory ids)
    {
        uint256 total = allCampaignIds.length;
        if (_offset >= total) {
            return new uint256[](0);
        }

        uint256 end = _offset + _limit;
        if (end > total) {
            end = total;
        }

        uint256 size = end - _offset;
        ids = new uint256[](size);
        for (uint256 i = 0; i < size; ) {
            ids[i] = allCampaignIds[_offset + i];
            unchecked { ++i; }
        }
    }

    /**
     * @notice Get full details of a single campaign.
     */
    function getCampaign(uint256 _campaignId)
        external
        view
        returns (Campaign memory)
    {
        return campaigns[_campaignId];
    }

    /**
     * @notice Get a milestone for a campaign.
     */
    function getMilestone(uint256 _campaignId, uint256 _milestoneIndex)
        external
        view
        returns (Milestone memory)
    {
        return milestones[_campaignId][_milestoneIndex];
    }

    /**
     * @notice Get unique donors for a campaign.
     */
    function getDonors(uint256 _campaignId)
        external
        view
        returns (address[] memory)
    {
        return campaignDonors[_campaignId];
    }

    /**
     * @notice Get the number of milestones for a campaign.
     */
    function getMilestoneCount(uint256 _campaignId) external view returns (uint256) {
        return campaigns[_campaignId].milestoneCount;
    }
}
