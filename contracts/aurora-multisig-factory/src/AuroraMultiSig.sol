// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AuroraMultiSig
/// @notice Multi-signature wallet requiring N-of-M confirmations to execute transactions
/// @dev Features:
///      - Configurable signers and threshold
///      - Submit, confirm, revoke, and execute transactions
///      - Support for native ETH and ERC-20 token transfers
///      - Transaction tracking per signer
///      - Owner can update signers and threshold
///      - ReentrancyGuard on execute
contract AuroraMultiSig is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── Types ───

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
    }

    error InvalidThreshold(uint256 threshold, uint256 signers);
    error InvalidSigners();
    error DuplicateSigner(address signer);
    error NotSigner(address caller);
    error TxDoesNotExist(uint256 txId);
    error TxAlreadyExecuted(uint256 txId);
    error TxAlreadyConfirmed(uint256 txId);
    error TxNotConfirmed(uint256 txId);
    error InsufficientConfirmations(uint256 have, uint256 need);
    error ExecutionFailed(uint256 txId);
    error NoFundsToRecover();

    // ─── Events ───

    event TransactionSubmitted(uint256 indexed txId, address indexed to, uint256 value);
    event TransactionConfirmed(uint256 indexed txId, address indexed signer);
    event ConfirmationRevoked(uint256 indexed txId, address indexed signer);
    event TransactionExecuted(uint256 indexed txId);
    event SignersUpdated(address[] newSigners, uint256 newThreshold);
    event Deposit(address indexed sender, uint256 amount);

    // ─── State ───

    /// @notice List of authorized signers
    address[] public signers;

    /// @notice Number of confirmations required to execute a transaction
    uint256 public threshold;

    /// @notice Whether an address is a signer
    mapping(address => bool) public isSigner;

    /// @notice All submitted transactions
    Transaction[] public transactions;

    /// @notice Whether a signer has confirmed a specific transaction
    mapping(uint256 => mapping(address => bool)) public confirmations;

    /// @notice Number of transactions submitted by each signer
    mapping(address => uint256) public txCountPerSigner;

    // ─── Constructor ───

    /// @param _signers Array of signer addresses (no duplicates, no zero address)
    /// @param _threshold Number of required confirmations (1 <= threshold <= signers.length)
    /// @param owner_ Initial contract owner
    constructor(address[] memory _signers, uint256 _threshold, address owner_) Ownable(owner_) {
        if (_signers.length == 0) revert InvalidSigners();
        if (_threshold == 0 || _threshold > _signers.length) {
            revert InvalidThreshold(_threshold, _signers.length);
        }

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            if (signer == address(0)) revert InvalidSigners();
            if (isSigner[signer]) revert DuplicateSigner(signer);

            isSigner[signer] = true;
            signers.push(signer);
        }

        threshold = _threshold;
    }

    // ─── Receive ETH ───

    receive() external payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    }

    // ─── Transaction Lifecycle ───

    /// @notice Submit a new transaction for confirmation
    /// @param to Destination address
    /// @param value ETH value to send
    /// @param data Calldata for contract interaction
    /// @return txId The transaction ID
    function submitTransaction(address to, uint256 value, bytes calldata data) external returns (uint256 txId) {
        if (!isSigner[msg.sender]) revert NotSigner(msg.sender);

        txId = transactions.length;
        transactions.push(Transaction({
            to: to,
            value: value,
            data: data,
            executed: false,
            confirmations: 0
        }));

        txCountPerSigner[msg.sender]++;
        emit TransactionSubmitted(txId, to, value);
    }

    /// @notice Confirm a pending transaction
    /// @param txId Transaction ID
    function confirmTransaction(uint256 txId) external {
        if (!isSigner[msg.sender]) revert NotSigner(msg.sender);
        if (txId >= transactions.length) revert TxDoesNotExist(txId);
        if (transactions[txId].executed) revert TxAlreadyExecuted(txId);
        if (confirmations[txId][msg.sender]) revert TxAlreadyConfirmed(txId);

        confirmations[txId][msg.sender] = true;
        transactions[txId].confirmations++;

        emit TransactionConfirmed(txId, msg.sender);
    }

    /// @notice Revoke a previously given confirmation
    /// @param txId Transaction ID
    function revokeConfirmation(uint256 txId) external {
        if (!isSigner[msg.sender]) revert NotSigner(msg.sender);
        if (txId >= transactions.length) revert TxDoesNotExist(txId);
        if (transactions[txId].executed) revert TxAlreadyExecuted(txId);
        if (!confirmations[txId][msg.sender]) revert TxNotConfirmed(txId);

        confirmations[txId][msg.sender] = false;
        transactions[txId].confirmations--;

        emit ConfirmationRevoked(txId, msg.sender);
    }

    /// @notice Execute a transaction after enough confirmations
    /// @param txId Transaction ID
    function executeTransaction(uint256 txId) external nonReentrant {
        if (!isSigner[msg.sender]) revert NotSigner(msg.sender);
        if (txId >= transactions.length) revert TxDoesNotExist(txId);
        if (transactions[txId].executed) revert TxAlreadyExecuted(txId);

        Transaction storage txn = transactions[txId];
        if (txn.confirmations < threshold) {
            revert InsufficientConfirmations(txn.confirmations, threshold);
        }

        txn.executed = true;

        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        if (!success) revert ExecutionFailed(txId);

        emit TransactionExecuted(txId);
    }

    // ─── Owner Management ───

    /// @notice Update signers and threshold. Only owner.
    /// @param _signers New signer addresses
    /// @param _threshold New threshold
    function updateSigners(address[] calldata _signers, uint256 _threshold) external onlyOwner {
        if (_signers.length == 0) revert InvalidSigners();
        if (_threshold == 0 || _threshold > _signers.length) {
            revert InvalidThreshold(_threshold, _signers.length);
        }

        // Remove old signers
        for (uint256 i = 0; i < signers.length; i++) {
            isSigner[signers[i]] = false;
        }

        // Add new signers
        delete signers;
        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            if (signer == address(0)) revert InvalidSigners();
            if (isSigner[signer]) revert DuplicateSigner(signer);

            isSigner[signer] = true;
            signers.push(signer);
        }

        threshold = _threshold;

        emit SignersUpdated(_signers, _threshold);
    }

    // ─── View Functions ───

    /// @notice Get the number of signers
    function getSignerCount() external view returns (uint256) {
        return signers.length;
    }

    /// @notice Get the total number of transactions
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    /// @notice Get transaction details
    /// @param txId Transaction ID
    /// @return to Destination address
    /// @return value ETH value
    /// @return data Calldata
    /// @return executed Whether executed
    /// @return confirmations Number of confirmations
    function getTransaction(uint256 txId)
        external
        view
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 confirmations
        )
    {
        if (txId >= transactions.length) revert TxDoesNotExist(txId);
        Transaction storage txn = transactions[txId];
        return (txn.to, txn.value, txn.data, txn.executed, txn.confirmations);
    }

    /// @notice Get list of all signers
    function getSigners() external view returns (address[] memory) {
        return signers;
    }

    /// @notice Recover ETH or ERC-20 tokens accidentally sent (owner only, not native ETH)
    function recoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /// @notice Recover excess ETH (owner only)
    function recoverETH() external onlyOwner {
        uint256 balance = address(this).balance;
        // Keep enough for pending txns? For simplicity, owner decides
        if (balance == 0) revert NoFundsToRecover();
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "ETH transfer failed");
    }
}
