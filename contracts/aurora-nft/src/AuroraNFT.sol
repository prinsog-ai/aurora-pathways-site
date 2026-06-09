// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Royalty} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title AuroraNFT
/// @notice Mintable ERC-721 NFT collection for Aurora Pathways ecosystem
/// @dev Features:
///      - Public mint with configurable price (native ETH/MATIC)
///      - Whitelist mint via Merkle proof (discounted price)
///      - EIP-2981 royalties on secondary sales
///      - Reveal mechanics (pre-reveal placeholder → post-reveal baseURI)
///      - Configurable max supply and per-wallet limits
///      - Owner-controlled minting (free team mints)
contract AuroraNFT is ERC721, ERC721Royalty, ERC721Enumerable, Ownable, ReentrancyGuard {
    using MerkleProof for bytes32[];

    // ─── Types ───

    error MaxSupplyReached(uint256 totalSupply, uint256 maxSupply);
    error MintNotActive();
    error InsufficientPayment(uint256 sent, uint256 required);
    error MaxPerWalletExceeded(uint256 have, uint256 max);
    error NotWhitelisted(address caller);
    error InvalidProof();
    error TokenNotRevealed();
    error InvalidMaxSupply(uint256 maxSupply, uint256 currentSupply);
    error InvalidRoyalty(uint96 fee, uint96 max);
    error NoFundsToWithdraw();

    // ─── Events ───

    event MintConfigUpdated(uint256 publicPrice, uint256 whitelistPrice, uint256 maxPerWallet);
    event MerkleRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    event Revealed(string baseURI);
    event Minted(address indexed buyer, uint256 indexed tokenId, bool whitelist);
    event FundsWithdrawn(address indexed to, uint256 amount);

    // ─── Constants ───

    uint96 public constant MAX_ROYALTY = 1000; // 10% in basis points (1000 / 10000)

    // ─── State ───

    /// @notice Maximum number of tokens that can ever be minted
    uint256 public immutable maxSupply;

    /// @notice Public mint price in wei (0 for free mint)
    uint256 public publicPrice;

    /// @notice Whitelist mint price in wei (discounted)
    uint256 public whitelistPrice;

    /// @notice Maximum tokens a single wallet can mint (public + whitelist combined)
    uint256 public maxPerWallet;

    /// @notice Whether public minting is active
    bool public publicMintActive;

    /// @notice Whether whitelist minting is active
    bool public whitelistMintActive;

    /// @notice Whether the collection has been revealed
    bool public revealed;

    /// @notice Merkle root for the whitelist
    bytes32 public merkleRoot;

    /// @notice Pre-reveal metadata URI (shown before reveal)
    string public preRevealURI;

    /// @notice Post-reveal base URI (set during reveal)
    string public baseURI;

    /// @notice Track tokens minted per wallet (public + whitelist)
    mapping(address => uint256) public mintsPerWallet;

    /// @notice Track whether an address has been whitelist-minted (prevents double-use of same whitelist spot)
    mapping(address => bool) public whitelistMinted;

    // ─── Constructor ───

    /// @param name_ NFT collection name
    /// @param symbol_ NFT collection symbol
    /// @param _maxSupply Maximum tokens that can be minted
    /// @param _publicPrice Public mint price in wei
    /// @param _whitelistPrice Whitelist mint price in wei
    /// @param _maxPerWallet Max tokens per wallet
    /// @param royaltyReceiver Address receiving secondary sale royalties
    /// @param royaltyFeeBps Royalty in basis points (e.g., 500 = 5%)
    /// @param owner_ Initial owner
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 _maxSupply,
        uint256 _publicPrice,
        uint256 _whitelistPrice,
        uint256 _maxPerWallet,
        address royaltyReceiver,
        uint96 royaltyFeeBps,
        address owner_
    )
        ERC721(name_, symbol_)
        Ownable(owner_)
    {
        if (_maxSupply == 0) revert InvalidMaxSupply(_maxSupply, 0);
        if (royaltyFeeBps > MAX_ROYALTY) revert InvalidRoyalty(royaltyFeeBps, MAX_ROYALTY);

        maxSupply = _maxSupply;
        publicPrice = _publicPrice;
        whitelistPrice = _whitelistPrice;
        maxPerWallet = _maxPerWallet;

        if (royaltyFeeBps > 0 && royaltyReceiver != address(0)) {
            _setDefaultRoyalty(royaltyReceiver, royaltyFeeBps);
        }
    }

    // ─── Mint Functions ───

    /// @notice Public mint — pay the public price
    /// @param quantity Number of tokens to mint
    function mint(uint256 quantity) external payable nonReentrant {
        if (!publicMintActive) revert MintNotActive();
        if (totalSupply() + quantity > maxSupply) revert MaxSupplyReached(totalSupply(), maxSupply);

        uint256 cost = publicPrice * quantity;
        if (msg.value < cost) revert InsufficientPayment(msg.value, cost);

        uint256 newTotal = mintsPerWallet[msg.sender] + quantity;
        if (newTotal > maxPerWallet) revert MaxPerWalletExceeded(newTotal, maxPerWallet);

        mintsPerWallet[msg.sender] = newTotal;

        _batchMint(msg.sender, quantity);
    }

    /// @notice Whitelist mint — requires valid Merkle proof, pays whitelist price
    /// @param quantity Number of tokens to mint
    /// @param proof Merkle proof array
    function whitelistMint(uint256 quantity, bytes32[] calldata proof) external payable nonReentrant {
        if (!whitelistMintActive) revert MintNotActive();
        if (totalSupply() + quantity > maxSupply) revert MaxSupplyReached(totalSupply(), maxSupply);
        if (whitelistMinted[msg.sender]) revert NotWhitelisted(msg.sender);

        // Verify Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        if (!proof.verifyCalldata(merkleRoot, leaf)) revert InvalidProof();

        uint256 cost = whitelistPrice * quantity;
        if (msg.value < cost) revert InsufficientPayment(msg.value, cost);

        uint256 newTotal = mintsPerWallet[msg.sender] + quantity;
        if (newTotal > maxPerWallet) revert MaxPerWalletExceeded(newTotal, maxPerWallet);

        mintsPerWallet[msg.sender] = newTotal;
        whitelistMinted[msg.sender] = true;

        _batchMint(msg.sender, quantity);

        emit Minted(msg.sender, totalSupply(), true);
    }

    /// @notice Owner mint — free mint for team, marketing, etc.
    /// @param to Recipient address
    /// @param quantity Number of tokens to mint
    function ownerMint(address to, uint256 quantity) external onlyOwner {
        if (totalSupply() + quantity > maxSupply) revert MaxSupplyReached(totalSupply(), maxSupply);
        _batchMint(to, quantity);
    }

    // ─── Reveal ───

    /// @notice Reveal the collection by setting the real base URI. Only owner.
    /// @param _baseURI The base URI for token metadata (e.g., ipfs://.../)
    function reveal(string calldata _baseURI) external onlyOwner {
        baseURI = _baseURI;
        revealed = true;
        emit Revealed(_baseURI);
    }

    /// @notice Set the pre-reveal placeholder URI. Only owner.
    /// @param _preRevealURI Placeholder metadata URI
    function setPreRevealURI(string calldata _preRevealURI) external onlyOwner {
        preRevealURI = _preRevealURI;
    }

    // ─── Configuration (Owner) ───

    /// @notice Update mint configuration. Only owner.
    function setMintConfig(
        uint256 _publicPrice,
        uint256 _whitelistPrice,
        uint256 _maxPerWallet
    ) external onlyOwner {
        publicPrice = _publicPrice;
        whitelistPrice = _whitelistPrice;
        maxPerWallet = _maxPerWallet;
        emit MintConfigUpdated(_publicPrice, _whitelistPrice, _maxPerWallet);
    }

    /// @notice Toggle public minting on/off. Only owner.
    function setPublicMintActive(bool active) external onlyOwner {
        publicMintActive = active;
    }

    /// @notice Toggle whitelist minting on/off. Only owner.
    function setWhitelistMintActive(bool active) external onlyOwner {
        whitelistMintActive = active;
    }

    /// @notice Set the Merkle root for the whitelist. Only owner.
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        bytes32 oldRoot = merkleRoot;
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(oldRoot, _merkleRoot);
    }

    /// @notice Update the default royalty. Only owner.
    function setDefaultRoyalty(address receiver, uint96 feeBps) external onlyOwner {
        if (feeBps > MAX_ROYALTY) revert InvalidRoyalty(feeBps, MAX_ROYALTY);
        _setDefaultRoyalty(receiver, feeBps);
    }

    // ─── Withdraw ───

    /// @notice Withdraw all accumulated ETH from mints. Only owner.
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoFundsToWithdraw();
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Transfer failed");
        emit FundsWithdrawn(owner(), balance);
    }

    // ─── Overrides ───

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        if (!revealed) {
            return preRevealURI;
        }

        return string(abi.encodePacked(baseURI, _toString(tokenId), ".json"));
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Royalty, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ─── Internal Helpers ───

    /// @dev Batch mint sequential tokens starting from current supply
    function _batchMint(address to, uint256 quantity) private {
        uint256 startId = totalSupply();
        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(to, startId + i);
        }
    }

    /// @dev Convert uint to string (like OpenZeppelin's Strings.toString but cheaper for simple numbers)
    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
