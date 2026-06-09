// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AuroraNFT} from "../src/AuroraNFT.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract AuroraNFTTest is Test {
    AuroraNFT public nft;

    // Actors
    address public owner = makeAddr("owner");
    address public minter1 = makeAddr("minter1");
    address public minter2 = makeAddr("minter2");
    address public stranger = makeAddr("stranger");
    address public royaltyRecipient = makeAddr("royaltyRecipient");
    address public nftBuyer = makeAddr("nftBuyer");

    // Constants
    uint256 constant MAX_SUPPLY = 100;
    uint256 constant PUBLIC_PRICE = 0.1 ether;
    uint256 constant WL_PRICE = 0.05 ether;
    uint256 constant MAX_PER_WALLET = 5;
    uint96 constant ROYALTY_BPS = 500; // 5%

    // ─── Merkle Proof Helpers ───

    bytes32 public merkleRoot;
    bytes32[] public proof1;
    bytes32[] public proof2;

    function _buildMerkleTree() internal {
        // Hash leaves: keccak256(abi.encodePacked(address))
        bytes32 leaf1 = keccak256(abi.encodePacked(minter1));
        bytes32 leaf2 = keccak256(abi.encodePacked(minter2));

        // Build tree: root = hash(left + right), sorted for simplicity
        bytes32[] memory leaves = new bytes32[](2);
        if (leaf1 < leaf2) {
            leaves[0] = leaf1;
            leaves[1] = leaf2;
        } else {
            leaves[0] = leaf2;
            leaves[1] = leaf1;
        }

        merkleRoot = keccak256(abi.encodePacked(leaves[0], leaves[1]));

        // Proof for leaf1: sibling is leaf2
        proof1 = new bytes32[](1);
        proof1[0] = leaves[1];

        // Proof for leaf2: sibling is leaf1
        proof2 = new bytes32[](1);
        proof2[0] = leaves[0];
    }

    // ─── Setup ───

    function setUp() public {
        _buildMerkleTree();

        vm.prank(owner);
        nft = new AuroraNFT(
            "Aurora Pathways NFT",
            "APNFT",
            MAX_SUPPLY,
            PUBLIC_PRICE,
            WL_PRICE,
            MAX_PER_WALLET,
            royaltyRecipient,
            ROYALTY_BPS,
            owner
        );

        // Set merkle root and pre-reveal URI
        vm.startPrank(owner);
        nft.setMerkleRoot(merkleRoot);
        nft.setPreRevealURI("ipfs://pre-reveal-placeholder");
        nft.setPublicMintActive(true);
        nft.setWhitelistMintActive(true);
        vm.stopPrank();

        // Fund minters
        vm.deal(minter1, 10 ether);
        vm.deal(minter2, 10 ether);
    }

    // ═══════════════════════════════════════════════════════
    // DEPLOYMENT & INITIAL STATE
    // ═══════════════════════════════════════════════════════

    function test_DeployOwner() public view {
        assertEq(nft.owner(), owner);
    }

    function test_DeployNameAndSymbol() public view {
        assertEq(nft.name(), "Aurora Pathways NFT");
        assertEq(nft.symbol(), "APNFT");
    }

    function test_DeployMaxSupply() public view {
        assertEq(nft.maxSupply(), MAX_SUPPLY);
    }

    function test_DeployPrices() public view {
        assertEq(nft.publicPrice(), PUBLIC_PRICE);
        assertEq(nft.whitelistPrice(), WL_PRICE);
    }

    function test_DeployMaxPerWallet() public view {
        assertEq(nft.maxPerWallet(), MAX_PER_WALLET);
    }

    function test_DeployNotRevealed() public view {
        assertFalse(nft.revealed());
    }

    function test_DeployMintInactiveByDefault() public view {
        // mintActive should be what we set in setUp
        assertTrue(nft.publicMintActive());
        assertTrue(nft.whitelistMintActive());
    }

    function test_DeployRoyaltySet() public {
        (address receiver, uint256 fee) = nft.royaltyInfo(1, 10000);
        assertEq(receiver, royaltyRecipient);
        assertEq(fee, (10000 * ROYALTY_BPS) / 10000); // 5% of 10000 = 500
    }

    function test_DeployFailsZeroMaxSupply() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSignature("InvalidMaxSupply(uint256,uint256)", 0, 0)
        );
        new AuroraNFT("Test", "TST", 0, 0, 0, 5, address(0), 0, owner);
    }

    function test_DeployFailsExcessiveRoyalty() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSignature("InvalidRoyalty(uint96,uint96)", 5000, 1000)
        );
        new AuroraNFT("Test", "TST", 10, 0, 0, 5, royaltyRecipient, 5000, owner);
    }

    // ═══════════════════════════════════════════════════════
    // PUBLIC MINT
    // ═══════════════════════════════════════════════════════

    function test_PublicMintSingle() public {
        vm.prank(minter1);
        nft.mint{value: PUBLIC_PRICE}(1);

        assertEq(nft.balanceOf(minter1), 1);
        assertEq(nft.ownerOf(0), minter1);
        assertEq(nft.totalSupply(), 1);
    }

    function test_PublicMintMultiple() public {
        vm.prank(minter1);
        nft.mint{value: PUBLIC_PRICE * 3}(3);

        assertEq(nft.balanceOf(minter1), 3);
        assertEq(nft.totalSupply(), 3);
        assertEq(nft.ownerOf(0), minter1);
        assertEq(nft.ownerOf(1), minter1);
        assertEq(nft.ownerOf(2), minter1);
    }

    function test_PublicMintInsufficientPayment() public {
        vm.prank(minter1);
        vm.expectRevert(
            abi.encodeWithSignature("InsufficientPayment(uint256,uint256)", 0, PUBLIC_PRICE)
        );
        nft.mint(1); // no value sent
    }

    function test_PublicMintInsufficientPaymentPartial() public {
        vm.prank(minter1);
        vm.expectRevert(
            abi.encodeWithSignature("InsufficientPayment(uint256,uint256)", 0.05 ether, 0.1 ether)
        );
        nft.mint{value: 0.05 ether}(1);
    }

    function test_PublicMintMaxPerWallet() public {
        vm.startPrank(minter1);
        nft.mint{value: PUBLIC_PRICE * 5}(5);

        vm.expectRevert(
            abi.encodeWithSignature("MaxPerWalletExceeded(uint256,uint256)", 6, 5)
        );
        nft.mint{value: PUBLIC_PRICE}(1);
        vm.stopPrank();
    }

    function test_PublicMintMaxSupplyReached() public {
        // Mint in batches across different wallets to avoid per-wallet limit
        address[] memory minters = new address[](20);
        for (uint256 i = 0; i < 20; i++) {
            minters[i] = makeAddr(string(abi.encodePacked("batchMinter", i)));
            vm.deal(minters[i], 10 ether);
        }

        // Each minter mints 5 tokens (maxPerWallet = 5), 20 minters x 5 = 100 = MAX_SUPPLY
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(minters[i]);
            nft.mint{value: PUBLIC_PRICE * 5}(5);
        }

        assertEq(nft.totalSupply(), MAX_SUPPLY);

        vm.prank(minter2);
        vm.expectRevert(
            abi.encodeWithSignature("MaxSupplyReached(uint256,uint256)", 100, 100)
        );
        nft.mint{value: PUBLIC_PRICE}(1);
    }

    function test_PublicMintInactive() public {
        vm.prank(owner);
        nft.setPublicMintActive(false);

        vm.prank(minter1);
        vm.expectRevert(abi.encodeWithSignature("MintNotActive()"));
        nft.mint{value: PUBLIC_PRICE}(1);
    }

    function test_PublicMintExcessPayment() public {
        uint256 balanceBefore = minter1.balance;

        vm.prank(minter1);
        nft.mint{value: 1 ether}(1); // overpay

        // Excess should remain in contract; minter lost extra
        assertEq(nft.balanceOf(minter1), 1);
        assertEq(address(nft).balance, 1 ether);
    }

    // ═══════════════════════════════════════════════════════
    // WHITELIST MINT
    // ═══════════════════════════════════════════════════════

    function test_WhitelistMint() public {
        vm.prank(minter1);
        nft.whitelistMint{value: WL_PRICE}(1, proof1);

        assertEq(nft.balanceOf(minter1), 1);
        assertEq(nft.totalSupply(), 1);
        assertTrue(nft.whitelistMinted(minter1));
    }

    function test_WhitelistMintMultiple() public {
        vm.prank(minter1);
        nft.whitelistMint{value: WL_PRICE * 3}(3, proof1);

        assertEq(nft.balanceOf(minter1), 3);
    }

    function test_WhitelistMintWrongProof() public {
        vm.prank(minter1);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        nft.whitelistMint{value: WL_PRICE}(1, proof2); // proof2 is for minter2
    }

    function test_WhitelistMintNoProof() public {
        bytes32[] memory empty;
        vm.prank(minter1);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        nft.whitelistMint{value: WL_PRICE}(1, empty);
    }

    function test_WhitelistMintNotWhitelisted() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("InvalidProof()"));
        nft.whitelistMint{value: WL_PRICE}(1, proof1);
    }

    function test_WhitelistCannotMintTwice() public {
        vm.startPrank(minter1);
        nft.whitelistMint{value: WL_PRICE}(1, proof1);

        vm.expectRevert(abi.encodeWithSignature("NotWhitelisted(address)", minter1));
        nft.whitelistMint{value: WL_PRICE}(1, proof1);
        vm.stopPrank();
    }

    function test_WhitelistInsufficientPayment() public {
        vm.prank(minter1);
        vm.expectRevert(
            abi.encodeWithSignature("InsufficientPayment(uint256,uint256)", 0, WL_PRICE)
        );
        nft.whitelistMint(1, proof1); // no value
    }

    function test_WhitelistMintInactive() public {
        vm.prank(owner);
        nft.setWhitelistMintActive(false);

        vm.prank(minter1);
        vm.expectRevert(abi.encodeWithSignature("MintNotActive()"));
        nft.whitelistMint{value: WL_PRICE}(1, proof1);
    }

    // ═══════════════════════════════════════════════════════
    // OWNER MINT
    // ═══════════════════════════════════════════════════════

    function test_OwnerMint() public {
        vm.prank(owner);
        nft.ownerMint(nftBuyer, 10);

        assertEq(nft.balanceOf(nftBuyer), 10);
        assertEq(nft.totalSupply(), 10);
    }

    function test_OwnerMintOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        nft.ownerMint(nftBuyer, 1);
    }

    function test_OwnerMintMaxSupply() public {
        // Owner mints all supply
        vm.prank(owner);
        nft.ownerMint(owner, MAX_SUPPLY);

        assertEq(nft.totalSupply(), MAX_SUPPLY);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSignature("MaxSupplyReached(uint256,uint256)", 100, 100)
        );
        nft.ownerMint(minter1, 1);
    }

    // ═══════════════════════════════════════════════════════
    // REVEAL MECHANICS
    // ═══════════════════════════════════════════════════════

    function test_PreRevealTokenURI() public {
        vm.prank(minter1);
        nft.mint{value: PUBLIC_PRICE}(1);

        assertEq(nft.tokenURI(0), "ipfs://pre-reveal-placeholder");
    }

    function test_RevealSetsRevealedFlag() public {
        vm.prank(owner);
        nft.reveal("ipfs://real-metadata/");

        assertTrue(nft.revealed());
    }

    function test_RevealTokenURI() public {
        vm.prank(minter1);
        nft.mint{value: PUBLIC_PRICE}(1);

        vm.prank(owner);
        nft.reveal("ipfs://real-metadata/");

        assertEq(nft.tokenURI(0), "ipfs://real-metadata/0.json");
    }

    function test_RevealOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        nft.reveal("ipfs://leak/");
    }

    function test_SetPreRevealURIOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        nft.setPreRevealURI("ipfs://hacked/");
    }

    function test_TokenURIRevertsForNonexistentToken() public {
        vm.expectRevert();
        nft.tokenURI(999);
    }

    // ═══════════════════════════════════════════════════════
    // ROYALTIES (EIP-2981)
    // ═══════════════════════════════════════════════════════

    function test_RoyaltyInfo() public {
        (address receiver, uint256 amount) = nft.royaltyInfo(5, 1000);
        assertEq(receiver, royaltyRecipient);
        assertEq(amount, 50); // 5% of 1000
    }

    function test_RoyaltyInfoLargeSale() public {
        (address receiver, uint256 amount) = nft.royaltyInfo(1, 10 ether);
        assertEq(receiver, royaltyRecipient);
        assertEq(amount, 0.5 ether); // 5% of 10 ether
    }

    function test_SetRoyalty() public {
        vm.prank(owner);
        nft.setDefaultRoyalty(minter1, 250); // 2.5%

        (address receiver, uint256 amount) = nft.royaltyInfo(0, 10000);
        assertEq(receiver, minter1);
        assertEq(amount, 250);
    }

    function test_SetRoyaltyOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        nft.setDefaultRoyalty(stranger, 100);
    }

    function test_SetRoyaltyMax() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidRoyalty(uint96,uint96)", 5000, 1000));
        nft.setDefaultRoyalty(royaltyRecipient, 5000);
    }

    function test_SetsRoyaltyToZero() public {
        // ERC2981 doesn't allow address(0) as receiver, even with 0 fee.
        // Use deleteDefaultRoyalty path: set a zero fee to a valid address
        vm.prank(owner);
        nft.setDefaultRoyalty(owner, 0);

        (address receiver, uint256 amount) = nft.royaltyInfo(1, 1000);
        assertEq(receiver, owner);
        assertEq(amount, 0);
    }

    // ═══════════════════════════════════════════════════════
    // CONFIGURATION (OWNER GATING)
    // ═══════════════════════════════════════════════════════

    function test_SetMintConfig() public {
        vm.prank(owner);
        nft.setMintConfig(0.2 ether, 0.1 ether, 10);

        assertEq(nft.publicPrice(), 0.2 ether);
        assertEq(nft.whitelistPrice(), 0.1 ether);
        assertEq(nft.maxPerWallet(), 10);
    }

    function test_SetMintConfigOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        nft.setMintConfig(0, 0, 1);
    }

    function test_SetMerkleRoot() public {
        bytes32 newRoot = bytes32(uint256(0xdeadbeef));
        vm.prank(owner);
        nft.setMerkleRoot(newRoot);
        assertEq(nft.merkleRoot(), newRoot);
    }

    function test_SetMerkleRootOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        nft.setMerkleRoot(bytes32(0));
    }

    // ═══════════════════════════════════════════════════════
    // WITHDRAW
    // ═══════════════════════════════════════════════════════

    function test_Withdraw() public {
        vm.prank(minter1);
        nft.mint{value: 1 ether}(1);

        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);
        nft.withdraw();

        assertEq(address(nft).balance, 0);
        assertEq(owner.balance, ownerBalanceBefore + 1 ether);
    }

    function test_WithdrawOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        nft.withdraw();
    }

    function test_WithdrawNoFunds() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("NoFundsToWithdraw()"));
        nft.withdraw();
    }

    // ═══════════════════════════════════════════════════════
    // ERC-721 ENUMERABLE
    // ═══════════════════════════════════════════════════════

    function test_EnumerableTotalSupply() public {
        assertEq(nft.totalSupply(), 0);

        vm.prank(minter1);
        nft.mint{value: PUBLIC_PRICE * 2}(2);
        assertEq(nft.totalSupply(), 2);

        vm.prank(minter2);
        nft.mint{value: PUBLIC_PRICE}(1);
        assertEq(nft.totalSupply(), 3);
    }

    function test_EnumerableTokenByIndex() public {
        vm.prank(minter1);
        nft.mint{value: PUBLIC_PRICE * 3}(3);

        assertEq(nft.tokenByIndex(0), 0);
        assertEq(nft.tokenByIndex(1), 1);
        assertEq(nft.tokenByIndex(2), 2);
    }

    function test_EnumerableTokenOfOwnerByIndex() public {
        vm.startPrank(minter1);
        nft.mint{value: PUBLIC_PRICE * 3}(3);
        vm.stopPrank();

        assertEq(nft.tokenOfOwnerByIndex(minter1, 0), 0);
        assertEq(nft.tokenOfOwnerByIndex(minter1, 1), 1);
        assertEq(nft.tokenOfOwnerByIndex(minter1, 2), 2);
    }

    // ═══════════════════════════════════════════════════════
    // ERC-721 TRANSFERS
    // ═══════════════════════════════════════════════════════

    function test_Transfer() public {
        vm.prank(minter1);
        nft.mint{value: PUBLIC_PRICE}(1);

        vm.prank(minter1);
        nft.transferFrom(minter1, minter2, 0);

        assertEq(nft.ownerOf(0), minter2);
        assertEq(nft.balanceOf(minter1), 0);
        assertEq(nft.balanceOf(minter2), 1);
    }

    // ═══════════════════════════════════════════════════════
    // MIXED MINTING SCENARIOS
    // ═══════════════════════════════════════════════════════

    function test_MixedMintingPerWalletLimit() public {
        // minter2 whitelist mints 2, then public mints 3 = 5 total = max
        vm.startPrank(minter2);
        nft.whitelistMint{value: WL_PRICE * 2}(2, proof2);
        nft.mint{value: PUBLIC_PRICE * 3}(3);

        vm.expectRevert(
            abi.encodeWithSignature("MaxPerWalletExceeded(uint256,uint256)", 6, 5)
        );
        nft.mint{value: PUBLIC_PRICE}(1);
        vm.stopPrank();
    }

    function test_MintEmitsEvents() public {
        vm.prank(owner);
        nft.ownerMint(minter1, 5);

        // Token enum works
        assertEq(nft.balanceOf(minter1), 5);
        assertEq(nft.mintsPerWallet(minter1), 0); // ownerMint doesn't count
    }

    function test_SequenceTokenIds() public {
        // Owner mints 10 -> IDs 0-9
        vm.prank(owner);
        nft.ownerMint(owner, 10);

        // Public mint 3 -> IDs 10-12
        vm.prank(minter1);
        nft.mint{value: PUBLIC_PRICE * 3}(3);

        assertEq(nft.ownerOf(0), owner);
        assertEq(nft.ownerOf(9), owner);
        assertEq(nft.ownerOf(10), minter1);
        assertEq(nft.ownerOf(12), minter1);
    }
}
