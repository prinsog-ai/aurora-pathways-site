// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AcmeSupplyChain — On-chain supply chain provenance tracking
contract AcmeSupplyChain is Ownable {
    struct Product {
        uint256 id;
        string name;
        string manufacturer;
        uint256 manufactureDate;
        string metadataHash; // IPFS hash of product details
        address creator;
        bool exists;
    }

    struct Transfer {
        uint256 productId;
        address from;
        address to;
        uint256 timestamp;
        string location;
        string conditionHash; // hash of inspection/photos
        string notes;
    }

    uint256 public nextProductId;
    mapping(uint256 => Product) public products;
    mapping(uint256 => Transfer[]) public transfers;
    mapping(address => bool) public authorizedHandlers;

    event ProductCreated(uint256 indexed id, string name, string manufacturer);
    event TransferRecorded(uint256 indexed productId, address from, address to, string location);
    event HandlerAuthorized(address handler, bool status);

    constructor() Ownable(msg.sender) {}

    function createProduct(
        string calldata name,
        string calldata manufacturer,
        string calldata metadataHash
    ) external returns (uint256) {
        uint256 id = nextProductId++;
        products[id] = Product({
            id: id,
            name: name,
            manufacturer: manufacturer,
            manufactureDate: block.timestamp,
            metadataHash: metadataHash,
            creator: msg.sender,
            exists: true
        });

        emit ProductCreated(id, name, manufacturer);
        return id;
    }

    function recordTransfer(
        uint256 productId,
        address to,
        string calldata location,
        string calldata conditionHash,
        string calldata notes
    ) external {
        require(products[productId].exists, "Product not found");
        require(authorizedHandlers[msg.sender] || msg.sender == owner(), "Not authorized");

        transfers[productId].push(Transfer({
            productId: productId,
            from: msg.sender,
            to: to,
            timestamp: block.timestamp,
            location: location,
            conditionHash: conditionHash,
            notes: notes
        }));

        emit TransferRecorded(productId, msg.sender, to, location);
    }

    function authorizeHandler(address handler, bool status) external onlyOwner {
        authorizedHandlers[handler] = status;
        emit HandlerAuthorized(handler, status);
    }

    function getTransferCount(uint256 productId) external view returns (uint256) {
        return transfers[productId].length;
    }

    function getProductChain(uint256 productId) external view returns (Transfer[] memory) {
        return transfers[productId];
    }
}
