// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Forekast is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant PLATFORM_FEE_BPS = 300; // 3%
    uint256 public constant BPS_DENOMINATOR = 10000;

    enum Category { Crypto, Sports, Politics, Entertainment, Tech, Other }
    enum MarketState { Open, Closed, Resolved }

    struct Market {
        uint256 id;
        string question;
        Category category;
        address creator;
        uint256 resolutionDeadline;
        MarketState state;
        uint256 totalYes;
        uint256 totalNo;
        bool outcome; // true = Yes, false = No
        uint256 createdAt;
    }

    IERC20 public immutable usdc;
    uint256 public marketCount;
    uint256 public totalFees;

    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => uint256)) public betsYes;
    mapping(uint256 => mapping(address => uint256)) public betsNo;
    mapping(uint256 => mapping(address => bool)) public claimed;
    mapping(uint256 => uint256) public marketFee;
    mapping(uint256 => bool) public feeCollected;

    event MarketCreated(uint256 indexed marketId, string question, Category category, uint256 resolutionDeadline, address creator);
    event BetPlaced(uint256 indexed marketId, address indexed bettor, bool onYes, uint256 amount);
    event MarketResolved(uint256 indexed marketId, bool outcome);
    event WinningsClaimed(uint256 indexed marketId, address indexed claimant, uint256 amount);
    event FeesWithdrawn(address indexed to, uint256 amount);

    constructor(address _usdc, address initialOwner) Ownable(initialOwner) {
        usdc = IERC20(_usdc);
    }

    function createMarket(
        string calldata _question,
        Category _category,
        uint256 _resolutionDeadline,
        uint256 _initialLiquidity
    ) external returns (uint256) {
        require(_resolutionDeadline > block.timestamp, "Deadline must be future");
        require(_resolutionDeadline >= block.timestamp + 1 days, "Deadline too soon");
        require(_initialLiquidity > 0, "Must provide initial liquidity");

        uint256 marketId = marketCount++;

        markets[marketId] = Market({
            id: marketId,
            question: _question,
            category: _category,
            creator: msg.sender,
            resolutionDeadline: _resolutionDeadline,
            state: MarketState.Open,
            totalYes: _initialLiquidity,
            totalNo: 0,
            outcome: false,
            createdAt: block.timestamp
        });

        // Initial liquidity goes to Yes side
        betsYes[marketId][msg.sender] = _initialLiquidity;
        usdc.safeTransferFrom(msg.sender, address(this), _initialLiquidity);

        emit MarketCreated(marketId, _question, _category, _resolutionDeadline, msg.sender);
        return marketId;
    }

    function placeBet(uint256 _marketId, bool _onYes, uint256 _amount) external nonReentrant {
        Market storage market = markets[_marketId];
        require(market.state == MarketState.Open, "Market not open");
        require(block.timestamp < market.resolutionDeadline, "Market deadline passed");
        require(_amount > 0, "Amount must be > 0");

        if (_onYes) {
            market.totalYes += _amount;
            betsYes[_marketId][msg.sender] += _amount;
        } else {
            market.totalNo += _amount;
            betsNo[_marketId][msg.sender] += _amount;
        }

        usdc.safeTransferFrom(msg.sender, address(this), _amount);
        emit BetPlaced(_marketId, msg.sender, _onYes, _amount);
    }

    function resolveMarket(uint256 _marketId, bool _outcome) external {
        Market storage market = markets[_marketId];
        require(msg.sender == owner(), "Not authorized");
        require(market.state == MarketState.Open, "Market not open");
        require(block.timestamp >= market.resolutionDeadline, "Deadline not reached");

        market.state = MarketState.Resolved;
        market.outcome = _outcome;

        uint256 loserTotal = _outcome ? market.totalNo : market.totalYes;
        marketFee[_marketId] = (loserTotal * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;

        emit MarketResolved(_marketId, _outcome);
    }

    function claimWinnings(uint256 _marketId) external nonReentrant {
        Market storage market = markets[_marketId];
        require(market.state == MarketState.Resolved, "Market not resolved");
        require(!claimed[_marketId][msg.sender], "Already claimed");

        uint256 winnerTotal = market.outcome ? market.totalYes : market.totalNo;
        uint256 loserTotal = market.outcome ? market.totalNo : market.totalYes;

        // No winners or no losers => return original bets
        if (winnerTotal == 0 || loserTotal == 0) {
            claimed[_marketId][msg.sender] = true;
            return;
        }

        // Mark as claimed before transfer (reentrancy)
        claimed[_marketId][msg.sender] = true;

        // Use pre-computed fee from resolution time
        uint256 prizePool = loserTotal - marketFee[_marketId];

        // Get user's winning bet
        uint256 userBet;
        if (market.outcome) {
            userBet = betsYes[_marketId][msg.sender];
        } else {
            userBet = betsNo[_marketId][msg.sender];
        }
        require(userBet > 0, "No winning bet");

        uint256 payout = (userBet * (winnerTotal + prizePool)) / winnerTotal;

        // Zero out the user's bet
        if (market.outcome) {
            betsYes[_marketId][msg.sender] = 0;
        } else {
            betsNo[_marketId][msg.sender] = 0;
        }

        if (!feeCollected[_marketId]) {
            totalFees += marketFee[_marketId];
            feeCollected[_marketId] = true;
        }
        usdc.safeTransfer(msg.sender, payout);
        emit WinningsClaimed(_marketId, msg.sender, payout);
    }

    function withdrawFees() external onlyOwner nonReentrant {
        uint256 fees = totalFees;
        require(fees > 0, "No fees");
        totalFees = 0;
        usdc.safeTransfer(owner(), fees);
        emit FeesWithdrawn(owner(), fees);
    }

    function getMarket(uint256 _marketId) external view returns (Market memory) {
        return markets[_marketId];
    }
}
