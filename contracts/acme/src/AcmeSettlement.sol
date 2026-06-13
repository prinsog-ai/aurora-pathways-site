// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AcmeSettlement — Cross-border payment settlement engine
contract AcmeSettlement is Ownable {
    struct Settlement {
        uint256 id;
        address sender;
        address receiver;
        uint256 amount; // in smallest unit (e.g. USDC = 6 decimals)
        string currency;
        string sourceCountry;
        string destCountry;
        uint256 createdAt;
        uint256 settledAt;
        bool settled;
        bool disputed;
    }

    uint256 public nextSettlementId;
    mapping(uint256 => Settlement) public settlements;
    mapping(address => uint256) public balances;

    event SettlementCreated(uint256 indexed id, address sender, address receiver, uint256 amount);
    event SettlementCompleted(uint256 indexed id, uint256 settledAt);
    event SettlementDisputed(uint256 indexed id);
    event FundsDeposited(address depositor, uint256 amount);

    constructor() Ownable(msg.sender) {}

    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
        balances[msg.sender] += msg.value;
    }

    function createSettlement(
        address receiver,
        uint256 amount,
        string calldata currency,
        string calldata sourceCountry,
        string calldata destCountry
    ) external returns (uint256) {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        uint256 id = nextSettlementId++;
        settlements[id] = Settlement({
            id: id,
            sender: msg.sender,
            receiver: receiver,
            amount: amount,
            currency: currency,
            sourceCountry: sourceCountry,
            destCountry: destCountry,
            createdAt: block.timestamp,
            settledAt: 0,
            settled: false,
            disputed: false
        });

        balances[msg.sender] -= amount;

        emit SettlementCreated(id, msg.sender, receiver, amount);
        return id;
    }

    function settle(uint256 settlementId) external onlyOwner {
        Settlement storage s = settlements[settlementId];
        require(!s.settled, "Already settled");
        require(!s.disputed, "Under dispute");

        s.settled = true;
        s.settledAt = block.timestamp;
        balances[s.receiver] += s.amount;

        emit SettlementCompleted(settlementId, block.timestamp);
    }

    function dispute(uint256 settlementId) external {
        Settlement storage s = settlements[settlementId];
        require(msg.sender == s.sender || msg.sender == s.receiver, "Not party");
        require(!s.settled, "Already settled");

        s.disputed = true;
        // Refund sender
        balances[s.sender] += s.amount;
        emit SettlementDisputed(settlementId);
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
    }

    function getSettlementCount() external view returns (uint256) {
        return nextSettlementId;
    }

    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }
}
