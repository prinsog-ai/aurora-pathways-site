// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155Burnable} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import {ERC1155Pausable} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Pausable.sol";
import {ERC1155URIStorage} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AuroraMultiToken
/// @notice ERC-1155 multi-token for membership tiers, gaming items, and multi-asset collections
/// @dev Features:
///      - Create token types with configurable max supply and mint price
///      - Per-token URI storage (each token ID has its own metadata URI)
///      - Supply tracking per token ID
///      - Pausable by owner
///      - Burnable by token holders
///      - Batch mint support
///      - Owner-only minting and token type creation
contract AuroraMultiToken is
    ERC1155,
    ERC1155Supply,
    ERC1155Burnable,
    ERC1155Pausable,
    ERC1155URIStorage,
    Ownable,
    ReentrancyGuard
{
    // ─── Types ───

    struct TokenType {
        uint256 maxSupply; // 0 = unlimited
        uint256 mintPrice; // 0 = free
        bool isCreated; // whether this token type has been created
    }

    error TokenTypeAlreadyExists(uint256 id);
    error TokenTypeDoesNotExist(uint256 id);
    error MaxSupplyReached(uint256 id, uint256 supply, uint256 max);
    error InsufficientPayment(uint256 sent, uint256 required);
    error InvalidQuantity();
    error NoFundsToWithdraw();

    // ─── Events ───

    event TokenTypeCreated(uint256 indexed id, uint256 maxSupply, uint256 mintPrice, string uri);
    event TokenMinted(address indexed to, uint256 indexed id, uint256 amount);
    event FundsWithdrawn(address indexed to, uint256 amount);

    // ─── State ───

    /// @notice Configuration for each token type
    mapping(uint256 => TokenType) public tokenTypes;

    /// @notice Next token ID to be created (starts at 1)
    uint256 public nextTokenId;

    // ─── Constructor ───

    /// @param uri_ Base URI for token metadata (used as fallback)
    /// @param owner_ Initial contract owner
    constructor(string memory uri_, address owner_) ERC1155(uri_) Ownable(owner_) {}

    // ─── Token Type Management (Owner) ───

    /// @notice Create a new token type with configurable max supply and price
    /// @param id Token ID to create
    /// @param maxSupply Maximum supply (0 = unlimited)
    /// @param mintPrice Price per token in wei (0 = free)
    /// @param tokenURI Metadata URI for this token type
    function createTokenType(
        uint256 id,
        uint256 maxSupply,
        uint256 mintPrice,
        string calldata tokenURI
    ) external onlyOwner {
        if (tokenTypes[id].isCreated) revert TokenTypeAlreadyExists(id);

        tokenTypes[id] = TokenType({maxSupply: maxSupply, mintPrice: mintPrice, isCreated: true});

        if (bytes(tokenURI).length > 0) {
            _setURI(id, tokenURI);
        }

        if (id >= nextTokenId) {
            nextTokenId = id + 1;
        }

        emit TokenTypeCreated(id, maxSupply, mintPrice, tokenURI);
    }

    /// @notice Update the mint price for an existing token type
    /// @param id Token ID
    /// @param newPrice New price in wei
    function setMintPrice(uint256 id, uint256 newPrice) external onlyOwner {
        if (!tokenTypes[id].isCreated) revert TokenTypeDoesNotExist(id);
        tokenTypes[id].mintPrice = newPrice;
    }

    /// @notice Update the max supply for an existing token type
    /// @param id Token ID
    /// @param newMaxSupply New max supply (0 = unlimited)
    function setMaxSupply(uint256 id, uint256 newMaxSupply) external onlyOwner {
        if (!tokenTypes[id].isCreated) revert TokenTypeDoesNotExist(id);
        tokenTypes[id].maxSupply = newMaxSupply;
    }

    // ─── Minting ───

    /// @notice Mint tokens of a specific type (public, pays mint price)
    /// @param to Recipient address
    /// @param id Token ID to mint
    /// @param amount Number of tokens to mint
    function mint(
        address to,
        uint256 id,
        uint256 amount
    ) external payable nonReentrant {
        if (amount == 0) revert InvalidQuantity();
        if (!tokenTypes[id].isCreated) revert TokenTypeDoesNotExist(id);

        TokenType memory tt = tokenTypes[id];

        // Check max supply
        if (tt.maxSupply > 0 && totalSupply(id) + amount > tt.maxSupply) {
            revert MaxSupplyReached(id, totalSupply(id), tt.maxSupply);
        }

        // Check payment
        uint256 cost = tt.mintPrice * amount;
        if (msg.value < cost) revert InsufficientPayment(msg.value, cost);

        _mint(to, id, amount, "");
        emit TokenMinted(to, id, amount);
    }

    /// @notice Owner mint — free mint bypassing price and supply checks
    /// @param to Recipient address
    /// @param id Token ID
    /// @param amount Number of tokens
    function ownerMint(
        address to,
        uint256 id,
        uint256 amount
    ) external onlyOwner {
        if (!tokenTypes[id].isCreated) revert TokenTypeDoesNotExist(id);
        if (amount == 0) revert InvalidQuantity();

        _mint(to, id, amount, "");
        emit TokenMinted(to, id, amount);
    }

    /// @notice Batch mint multiple token types at once
    /// @param to Recipient address
    /// @param ids Array of token IDs
    /// @param amounts Array of amounts per token ID
    function batchMint(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external payable nonReentrant {
        if (ids.length != amounts.length) revert InvalidQuantity();
        if (ids.length == 0) revert InvalidQuantity();

        uint256 totalCost;
        for (uint256 i = 0; i < ids.length; i++) {
            if (amounts[i] == 0) revert InvalidQuantity();
            if (!tokenTypes[ids[i]].isCreated) revert TokenTypeDoesNotExist(ids[i]);

            TokenType memory tt = tokenTypes[ids[i]];

            if (tt.maxSupply > 0 && totalSupply(ids[i]) + amounts[i] > tt.maxSupply) {
                revert MaxSupplyReached(ids[i], totalSupply(ids[i]), tt.maxSupply);
            }

            totalCost += tt.mintPrice * amounts[i];
        }

        if (msg.value < totalCost) revert InsufficientPayment(msg.value, totalCost);

        _mintBatch(to, ids, amounts, "");
    }

    /// @notice Owner batch mint — free, bypasses price/supply checks
    /// @param to Recipient address
    /// @param ids Array of token IDs
    /// @param amounts Array of amounts
    function ownerBatchMint(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external onlyOwner {
        if (ids.length != amounts.length || ids.length == 0) revert InvalidQuantity();

        for (uint256 i = 0; i < ids.length; i++) {
            if (!tokenTypes[ids[i]].isCreated) revert TokenTypeDoesNotExist(ids[i]);
        }

        _mintBatch(to, ids, amounts, "");
    }

    // ─── Pause Control (Owner) ───

    /// @notice Pause all token transfers, minting, and burning. Only owner.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause all token operations. Only owner.
    function unpause() external onlyOwner {
        _unpause();
    }

    // ─── Withdraw ───

    /// @notice Withdraw accumulated ETH from mints. Only owner.
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoFundsToWithdraw();
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Transfer failed");
        emit FundsWithdrawn(owner(), balance);
    }

    // ─── Overrides ───

    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply, ERC1155Pausable) {
        super._update(from, to, ids, values);
    }

    // uri() must be overridden because both ERC1155 and ERC1155URIStorage define it
    function uri(uint256 tokenId) public view override(ERC1155, ERC1155URIStorage) returns (string memory) {
        return super.uri(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
