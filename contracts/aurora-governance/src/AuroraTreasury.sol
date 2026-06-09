// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title AuroraTreasury
/// @notice Multi-signature treasury wallet for the Aurora Pathways DAO
/// @dev Gnosis Safe-style multisig:
///      - Configurable signers and threshold (e.g., 3 of 5)
///      - Any signer can submit a transaction
///      - Signers confirm transactions; when threshold is met, anyone can execute
///      - Supports ETH and ERC-20 token transfers
///      - Governance-controlled (the AuroraGovernor can change signers/threshold)
contract AuroraTreasury is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ─── Types ───

    struct Transaction {
        address target;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmationCount;
    }

    // ─── Errors ───

    error NotASigner();
    error AlreadyConfirmed();
    error TxDoesNotExist(uint256 txId);
    error TxAlreadyExecuted(uint256 txId);
    error InsufficientConfirmations(uint256 have, uint256 need);
    error TxFailed(bytes reason);
    error InvalidThreshold(uint256 threshold, uint256 signerCount);
    error DuplicateSigner(address signer);
    error SignerNotFound(address signer);
    error CannotRemoveLastSigner();
    error InvalidSignature();
    error OnlyGovernance();

    // ─── Events ───

    event TransactionSubmitted(uint256 indexed txId, address indexed proposer, address target, uint256 value);
    event TransactionConfirmed(uint256 indexed txId, address indexed signer);
    event TransactionRevoked(uint256 indexed txId, address indexed signer);
    event TransactionExecuted(uint256 indexed txId);
    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event ThresholdChanged(uint256 oldThreshold, uint256 newThreshold);
    event GovernanceUpdated(address indexed oldGovernance, address indexed newGovernance);
    event ETHReceived(address indexed from, uint256 amount);
    event ERC20Received(address indexed token, address indexed from, uint256 amount);

    // ─── State ───

    /// @notice All current signers
    address[] public signers;

    /// @notice Whether an address is a signer
    mapping(address => bool) public isSigner;

    /// @notice Number of confirmations required to execute a transaction
    uint256 public threshold;

    /// @notice Total number of transactions submitted (also next tx ID)
    uint256 public transactionCount;

    /// @notice Stored transactions
    mapping(uint256 => Transaction) public transactions;

    /// @notice Confirmation bitmap: txId => signer => confirmed
    mapping(uint256 => mapping(address => bool)) public confirmations;

    /// @notice Address allowed to modify signers and threshold (governor contract)
    address public governance;

    // ─── Modifiers ───

    modifier onlySigner() {
        if (!isSigner[msg.sender]) revert NotASigner();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    modifier txExists(uint256 txId) {
        if (txId >= transactionCount) revert TxDoesNotExist(txId);
        _;
    }

    modifier notExecuted(uint256 txId) {
        if (transactions[txId].executed) revert TxAlreadyExecuted(txId);
        _;
    }

    modifier notConfirmed(uint256 txId) {
        if (confirmations[txId][msg.sender]) revert AlreadyConfirmed();
        _;
    }

    // ─── Constructor ───

    /// @param _signers Initial list of signer addresses
    /// @param _threshold Number of confirmations required (must be <= signer count)
    /// @param _governance Address of the governance contract allowed to manage signers
    constructor(address[] memory _signers, uint256 _threshold, address _governance) {
        if (_threshold == 0 || _threshold > _signers.length)
            revert InvalidThreshold(_threshold, _signers.length);

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            if (signer == address(0)) revert SignerNotFound(signer);
            if (isSigner[signer]) revert DuplicateSigner(signer);
            isSigner[signer] = true;
            signers.push(signer);
        }

        threshold = _threshold;
        governance = _governance;
    }

    // ─── Receive ETH ───

    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    // ─── ERC-20 Receiver ───

    /// @notice Anyone can deposit ERC-20 tokens to the treasury
    function depositERC20(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit ERC20Received(token, msg.sender, amount);
    }

    // ─── Transaction Lifecycle ───

    /// @notice Submit a new transaction for signer approval. Only existing signers may submit.
    /// @param target Destination address
    /// @param value ETH amount (0 for ERC-20 calls)
    /// @param data Encoded function call data (use abi.encodeWithSignature)
    /// @return txId The new transaction ID
    function submitTransaction(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlySigner returns (uint256 txId) {
        txId = transactionCount;
        transactions[txId] = Transaction({
            target: target,
            value: value,
            data: data,
            executed: false,
            confirmationCount: 0
        });
        transactionCount++;

        emit TransactionSubmitted(txId, msg.sender, target, value);

        // Auto-confirm by the submitter
        confirmations[txId][msg.sender] = true;
        transactions[txId].confirmationCount = 1;
        emit TransactionConfirmed(txId, msg.sender);
    }

    /// @notice Confirm an existing transaction. Must be a signer who hasn't confirmed yet.
    /// @param txId Transaction to confirm
    function confirmTransaction(uint256 txId)
        external
        onlySigner
        txExists(txId)
        notExecuted(txId)
        notConfirmed(txId)
    {
        confirmations[txId][msg.sender] = true;
        transactions[txId].confirmationCount++;

        emit TransactionConfirmed(txId, msg.sender);
    }

    /// @notice Revoke a previous confirmation. Must be a signer who has confirmed.
    /// @param txId Transaction to revoke confirmation from
    function revokeConfirmation(uint256 txId)
        external
        onlySigner
        txExists(txId)
        notExecuted(txId)
    {
        if (!confirmations[txId][msg.sender]) revert AlreadyConfirmed(); // wasn't confirmed

        confirmations[txId][msg.sender] = false;
        transactions[txId].confirmationCount--;

        emit TransactionRevoked(txId, msg.sender);
    }

    /// @notice Execute a transaction that has reached the required threshold. Anyone may call.
    /// @param txId Transaction to execute
    function executeTransaction(uint256 txId)
        external
        nonReentrant
        txExists(txId)
        notExecuted(txId)
    {
        Transaction storage txn = transactions[txId];

        if (txn.confirmationCount < threshold)
            revert InsufficientConfirmations(txn.confirmationCount, threshold);

        txn.executed = true;

        (bool success, bytes memory result) = txn.target.call{value: txn.value}(txn.data);
        if (!success) {
            // Revert with the reason string if available, otherwise generic
            if (result.length > 0) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            } else {
                revert TxFailed(result);
            }
        }

        emit TransactionExecuted(txId);
    }

    // ─── Signer Management (Governance Only) ───

    /// @notice Add a new signer. Only callable by the governance contract (or via multisig if set).
    /// @param signer Address to add
    function addSigner(address signer) external onlyGovernance {
        if (signer == address(0)) revert SignerNotFound(signer);
        if (isSigner[signer]) revert DuplicateSigner(signer);

        isSigner[signer] = true;
        signers.push(signer);

        emit SignerAdded(signer);
    }

    /// @notice Remove an existing signer. Only callable by governance.
    /// @param signer Address to remove
    function removeSigner(address signer) external onlyGovernance {
        if (!isSigner[signer]) revert SignerNotFound(signer);
        if (signers.length == 1) revert CannotRemoveLastSigner();

        isSigner[signer] = false;

        // Remove from array (order not preserved)
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == signer) {
                signers[i] = signers[signers.length - 1];
                signers.pop();
                break;
            }
        }

        // Auto-adjust threshold if needed
        if (threshold > signers.length) {
            uint256 oldThreshold = threshold;
            threshold = signers.length;
            emit ThresholdChanged(oldThreshold, threshold);
        }

        emit SignerRemoved(signer);
    }

    /// @notice Change the required confirmation threshold. Only callable by governance.
    /// @param newThreshold New threshold (must be >0 and <= signer count)
    function changeThreshold(uint256 newThreshold) external onlyGovernance {
        if (newThreshold == 0 || newThreshold > signers.length)
            revert InvalidThreshold(newThreshold, signers.length);

        uint256 oldThreshold = threshold;
        threshold = newThreshold;
        emit ThresholdChanged(oldThreshold, newThreshold);
    }

    /// @notice Update the governance address. Only current governance can call.
    /// @param newGovernance New governance address
    function updateGovernance(address newGovernance) external onlyGovernance {
        if (newGovernance == address(0)) revert SignerNotFound(newGovernance);
        address oldGovernance = governance;
        governance = newGovernance;
        emit GovernanceUpdated(oldGovernance, newGovernance);
    }

    // ─── View Functions ───

    /// @notice Get all current signers
    function getSigners() external view returns (address[] memory) {
        return signers;
    }

    /// @notice Get number of signers
    function signerCount() external view returns (uint256) {
        return signers.length;
    }

    /// @notice Check all confirmations for a transaction
    function getConfirmations(uint256 txId)
        external
        view
        txExists(txId)
        returns (address[] memory confirmed)
    {
        Transaction storage txn = transactions[txId];
        confirmed = new address[](txn.confirmationCount);
        uint256 idx;
        for (uint256 i = 0; i < signers.length; i++) {
            if (confirmations[txId][signers[i]]) {
                confirmed[idx] = signers[i];
                idx++;
            }
        }
    }

    /// @notice Get confirmation status for a specific signer on a transaction
    function isConfirmed(uint256 txId, address signer)
        external
        view
        txExists(txId)
        returns (bool)
    {
        return confirmations[txId][signer];
    }

    /// @notice Get the full transaction object
    function getTransaction(uint256 txId)
        external
        view
        txExists(txId)
        returns (
            address target,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 confirmationCount
        )
    {
        Transaction storage txn = transactions[txId];
        return (txn.target, txn.value, txn.data, txn.executed, txn.confirmationCount);
    }
}
