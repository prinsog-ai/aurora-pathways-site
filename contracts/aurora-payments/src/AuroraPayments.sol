// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AuroraPayments
/// @notice Multi-chain stablecoin payment splitter for Aurora Pathways
/// @dev Accepts USDC, USDT, DAI on any EVM chain. Splits payments to configured recipients.
contract AuroraPayments is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Recipient {
        address wallet;
        uint256 share; // basis points (e.g. 5000 = 50%)
    }

    /// @notice All configured recipients with their share percentages
    Recipient[] public recipients;

    /// @notice Supported tokens (USDC, USDT, DAI per chain)
    mapping(address => bool) public supportedTokens;

    /// @notice Total basis points for all recipients (must always be 10000 = 100%)
    uint256 public totalShares;

    /// @notice Total lifetime revenue tracked per token
    mapping(address => uint256) public totalRevenue;

    /// @notice Track per-recipient earnings per token
    mapping(address => mapping(address => uint256)) public recipientEarnings;

    event PaymentReceived(address indexed token, address indexed from, uint256 amount);
    event PaymentDistributed(address indexed token, uint256 totalAmount);
    event TokenAdded(address indexed token, string symbol);
    event TokenRemoved(address indexed token);
    event RecipientsUpdated();

    error InvalidShares(uint256 total);
    error TokenNotSupported(address token);
    error NoRecipients();
    error NoBalance();

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Set the payment split recipients — only owner
    /// @param _recipients Array of recipient wallets and their share basis points
    function setRecipients(Recipient[] calldata _recipients) external onlyOwner {
        delete recipients;
        uint256 _total;
        for (uint256 i = 0; i < _recipients.length; i++) {
            require(_recipients[i].wallet != address(0), "Invalid address");
            _total += _recipients[i].share;
            recipients.push(_recipients[i]);
        }
        if (_total != 10000) revert InvalidShares(_total);
        totalShares = _total;
        emit RecipientsUpdated();
    }

    /// @notice Add a supported stablecoin token — only owner
    function addSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = true;
        emit TokenAdded(token, ""); // symbol can be read off-chain
    }

    /// @notice Remove a supported token — only owner
    function removeSupportedToken(address token) external onlyOwner {
        supportedTokens[token] = false;
        emit TokenRemoved(token);
    }

    /// @notice Anyone can trigger distribution of a token's balance to recipients
    /// @param token The ERC-20 stablecoin to distribute
    function distribute(address token) external nonReentrant {
        if (!supportedTokens[token]) revert TokenNotSupported(token);
        if (recipients.length == 0) revert NoRecipients();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NoBalance();

        totalRevenue[token] += balance;

        for (uint256 i = 0; i < recipients.length; i++) {
            Recipient memory r = recipients[i];
            uint256 amount = (balance * r.share) / 10000;
            if (amount > 0) {
                IERC20(token).safeTransfer(r.wallet, amount);
                recipientEarnings[r.wallet][token] += amount;
            }
        }

        emit PaymentDistributed(token, balance);
    }

    /// @notice View total receivable for a given token
    function pendingBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Get all recipients
    function getRecipients() external view returns (Recipient[] memory) {
        return recipients;
    }

    /// @notice Get number of recipients
    function recipientCount() external view returns (uint256) {
        return recipients.length;
    }
}