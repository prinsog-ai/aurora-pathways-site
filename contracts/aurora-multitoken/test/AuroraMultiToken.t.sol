// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AuroraMultiToken} from "../src/AuroraMultiToken.sol";

contract AuroraMultiTokenTest is Test {
    AuroraMultiToken public mt;

    // Actors
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public stranger = makeAddr("stranger");

    // Token IDs
    uint256 constant BRONZE = 1;
    uint256 constant SILVER = 2;
    uint256 constant GOLD = 3;
    uint256 constant SWORD = 10;
    uint256 constant SHIELD = 11;

    // Prices
    uint256 constant BRONZE_PRICE = 0.01 ether;
    uint256 constant SILVER_PRICE = 0.05 ether;
    uint256 constant GOLD_PRICE = 0.1 ether;
    uint256 constant SWORD_PRICE = 0.02 ether;

    // Max supplies
    uint256 constant GOLD_MAX = 100;
    uint256 constant SWORD_MAX = 1000;

    // ─── Setup ───

    function setUp() public {
        mt = new AuroraMultiToken("https://aurora.base.uri/", owner);

        // Create membership tiers
        vm.startPrank(owner);
        mt.createTokenType(BRONZE, 0, BRONZE_PRICE, "ipfs://bronze.json");
        mt.createTokenType(SILVER, 0, SILVER_PRICE, "ipfs://silver.json");
        mt.createTokenType(GOLD, GOLD_MAX, GOLD_PRICE, "ipfs://gold.json");

        // Create gaming items
        mt.createTokenType(SWORD, SWORD_MAX, SWORD_PRICE, "ipfs://sword.json");
        mt.createTokenType(SHIELD, 0, 0, "ipfs://shield.json"); // free, unlimited
        vm.stopPrank();

        // Fund test accounts
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    // ═══════════════════════════════════════════════════════
    // DEPLOYMENT & INITIAL STATE
    // ═══════════════════════════════════════════════════════

    function test_DeployOwner() public view {
        assertEq(mt.owner(), owner);
    }

    function test_DeployBaseURI() public view {
        // Base URI is used when no per-token URI is set
        assertEq(mt.uri(999), "https://aurora.base.uri/");
    }

    function test_DeployNextTokenId() public view {
        // After creating IDs 1,2,3,10,11 — next should be 12
        assertEq(mt.nextTokenId(), 12);
    }

    function test_TokenTypesCreated() public view {
        // Auto-generated getter returns (uint256 maxSupply, uint256 mintPrice, bool isCreated)
        (, , bool bronzeCreated) = mt.tokenTypes(BRONZE);
        (, , bool silverCreated) = mt.tokenTypes(SILVER);
        (, , bool goldCreated) = mt.tokenTypes(GOLD);
        (, , bool swordCreated) = mt.tokenTypes(SWORD);
        (, , bool shieldCreated) = mt.tokenTypes(SHIELD);
        (, , bool unknownCreated) = mt.tokenTypes(99);

        assertTrue(bronzeCreated);
        assertTrue(silverCreated);
        assertTrue(goldCreated);
        assertTrue(swordCreated);
        assertTrue(shieldCreated);
        assertFalse(unknownCreated);
    }

    function test_TokenTypeParams() public view {
        (uint256 maxSupply, uint256 mintPrice, ) = mt.tokenTypes(BRONZE);
        assertEq(maxSupply, 0); // unlimited
        assertEq(mintPrice, BRONZE_PRICE);

        (maxSupply, mintPrice, ) = mt.tokenTypes(GOLD);
        assertEq(maxSupply, GOLD_MAX);
        assertEq(mintPrice, GOLD_PRICE);
    }

    // ═══════════════════════════════════════════════════════
    // TOKEN TYPE URI
    // ═══════════════════════════════════════════════════════

    function test_PerTokenURI() public view {
        assertEq(mt.uri(BRONZE), "ipfs://bronze.json");
        assertEq(mt.uri(SILVER), "ipfs://silver.json");
        assertEq(mt.uri(GOLD), "ipfs://gold.json");
        assertEq(mt.uri(SWORD), "ipfs://sword.json");
        assertEq(mt.uri(SHIELD), "ipfs://shield.json");
    }

    // ═══════════════════════════════════════════════════════
    // CREATE TOKEN TYPE
    // ═══════════════════════════════════════════════════════

    function test_CreateTokenType() public {
        vm.prank(owner);
        mt.createTokenType(100, 50, 0.5 ether, "ipfs://rare.json");

        (uint256 maxSupply, uint256 mintPrice, bool isCreated) = mt.tokenTypes(100);
        assertTrue(isCreated);
        assertEq(maxSupply, 50);
        assertEq(mintPrice, 0.5 ether);
        assertEq(mt.uri(100), "ipfs://rare.json");
    }

    function test_CreateTokenTypeDuplicate() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSignature("TokenTypeAlreadyExists(uint256)", BRONZE)
        );
        mt.createTokenType(BRONZE, 0, 0, "");
    }

    function test_CreateTokenTypeOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        mt.createTokenType(200, 10, 1 ether, "");
    }

    function test_CreateTokenTypeNoURI() public {
        vm.prank(owner);
        mt.createTokenType(50, 0, 0, "");

        (, , bool isCreated) = mt.tokenTypes(50);
        assertTrue(isCreated);
        // Falls back to base URI
        assertEq(mt.uri(50), "https://aurora.base.uri/");
    }

    // ═══════════════════════════════════════════════════════
    // PUBLIC MINT (SINGLE)
    // ═══════════════════════════════════════════════════════

    function test_MintSingle() public {
        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE}(alice, BRONZE, 1);

        assertEq(mt.balanceOf(alice, BRONZE), 1);
        assertEq(mt.totalSupply(BRONZE), 1);
    }

    function test_MintMultiple() public {
        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE * 10}(alice, BRONZE, 10);

        assertEq(mt.balanceOf(alice, BRONZE), 10);
        assertEq(mt.totalSupply(BRONZE), 10);
    }

    function test_MintInsufficientPayment() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSignature("InsufficientPayment(uint256,uint256)", 0, BRONZE_PRICE)
        );
        mt.mint(alice, BRONZE, 1);
    }

    function test_MintInsufficientPaymentPartial() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSignature("InsufficientPayment(uint256,uint256)", 0.001 ether, BRONZE_PRICE)
        );
        mt.mint{value: 0.001 ether}(alice, BRONZE, 1);
    }

    function test_MintNonexistentTokenType() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSignature("TokenTypeDoesNotExist(uint256)", 999)
        );
        mt.mint{value: 1 ether}(alice, 999, 1);
    }

    function test_MintZeroQuantity() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuantity()"));
        mt.mint{value: 0}(alice, BRONZE, 0);
    }

    function test_MintToOther() public {
        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE}(bob, BRONZE, 1);

        assertEq(mt.balanceOf(bob, BRONZE), 1);
        assertEq(mt.balanceOf(alice, BRONZE), 0);
    }

    // ═══════════════════════════════════════════════════════
    // MAX SUPPLY ENFORCEMENT
    // ═══════════════════════════════════════════════════════

    function test_MintMaxSupplyReached() public {
        // GOLD has max supply of 100
        address[] memory minters = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            minters[i] = makeAddr(string(abi.encodePacked("goldMinter", i)));
            vm.deal(minters[i], 100 ether);
        }

        // Each mints 10, total = 100
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(minters[i]);
            mt.mint{value: GOLD_PRICE * 10}(minters[i], GOLD, 10);
        }

        assertEq(mt.totalSupply(GOLD), GOLD_MAX);

        // Now try to mint one more
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSignature("MaxSupplyReached(uint256,uint256,uint256)", GOLD, GOLD_MAX, GOLD_MAX)
        );
        mt.mint{value: GOLD_PRICE}(alice, GOLD, 1);
    }

    function test_MintMaxSupplyBatch() public {
        // SWORD has max supply 1000, try to mint 1001
        // Need enough ETH for 1001 swords
        address bigMinter = makeAddr("bigMinter");
        vm.deal(bigMinter, 100 ether);
        vm.prank(bigMinter);
        vm.expectRevert(
            abi.encodeWithSignature("MaxSupplyReached(uint256,uint256,uint256)", SWORD, 0, SWORD_MAX)
        );
        mt.mint{value: SWORD_PRICE * 1001}(bigMinter, SWORD, 1001);
    }

    // ═══════════════════════════════════════════════════════
    // FREE MINT (SHIELD)
    // ═══════════════════════════════════════════════════════

    function test_FreeMint() public {
        vm.prank(alice);
        mt.mint(alice, SHIELD, 5);

        assertEq(mt.balanceOf(alice, SHIELD), 5);
    }

    // ═══════════════════════════════════════════════════════
    // BATCH MINT
    // ═══════════════════════════════════════════════════════

    function test_BatchMint() public {
        uint256[] memory ids = new uint256[](3);
        ids[0] = BRONZE;
        ids[1] = SILVER;
        ids[2] = SHIELD;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 2;
        amounts[1] = 1;
        amounts[2] = 5;

        uint256 totalCost = BRONZE_PRICE * 2 + SILVER_PRICE * 1 + SHIELD * 0;

        vm.prank(alice);
        mt.batchMint{value: totalCost}(alice, ids, amounts);

        assertEq(mt.balanceOf(alice, BRONZE), 2);
        assertEq(mt.balanceOf(alice, SILVER), 1);
        assertEq(mt.balanceOf(alice, SHIELD), 5);
    }

    function test_BatchMintInsufficientPayment() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = BRONZE;
        ids[1] = SILVER;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        uint256 required = BRONZE_PRICE + SILVER_PRICE;

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSignature("InsufficientPayment(uint256,uint256)", 0, required)
        );
        mt.batchMint(alice, ids, amounts);
    }

    function test_BatchMintMismatchedArrays() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = BRONZE;
        ids[1] = SILVER;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuantity()"));
        mt.batchMint{value: 1 ether}(alice, ids, amounts);
    }

    function test_BatchMintEmptyArrays() public {
        uint256[] memory ids = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuantity()"));
        mt.batchMint(alice, ids, amounts);
    }

    // ═══════════════════════════════════════════════════════
    // OWNER MINT
    // ═══════════════════════════════════════════════════════

    function test_OwnerMint() public {
        vm.prank(owner);
        mt.ownerMint(alice, BRONZE, 50);

        assertEq(mt.balanceOf(alice, BRONZE), 50);
    }

    function test_OwnerMintOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        mt.ownerMint(alice, BRONZE, 1);
    }

    function test_OwnerMintNonexistentType() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSignature("TokenTypeDoesNotExist(uint256)", 999)
        );
        mt.ownerMint(alice, 999, 1);
    }

    function test_OwnerMintZeroQuantity() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidQuantity()"));
        mt.ownerMint(alice, BRONZE, 0);
    }

    function test_OwnerBatchMint() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = BRONZE;
        ids[1] = GOLD;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10;
        amounts[1] = 5;

        vm.prank(owner);
        mt.ownerBatchMint(alice, ids, amounts);

        assertEq(mt.balanceOf(alice, BRONZE), 10);
        assertEq(mt.balanceOf(alice, GOLD), 5);
    }

    function test_OwnerBatchMintOnlyOwner() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = BRONZE;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.prank(stranger);
        vm.expectRevert();
        mt.ownerBatchMint(alice, ids, amounts);
    }

    // ═══════════════════════════════════════════════════════
    // BURN
    // ═══════════════════════════════════════════════════════

    function test_Burn() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE * 5}(alice, BRONZE, 5);

        vm.prank(alice);
        mt.burn(alice, BRONZE, 3);

        assertEq(mt.balanceOf(alice, BRONZE), 2);
        assertEq(mt.totalSupply(BRONZE), 2);
    }

    function test_BurnBatch() public {
        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE * 5}(alice, BRONZE, 5);
        vm.prank(alice);
        mt.mint{value: SILVER_PRICE * 3}(alice, SILVER, 3);

        uint256[] memory ids = new uint256[](2);
        ids[0] = BRONZE;
        ids[1] = SILVER;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2;
        amounts[1] = 1;

        vm.prank(alice);
        mt.burnBatch(alice, ids, amounts);

        assertEq(mt.balanceOf(alice, BRONZE), 3);
        assertEq(mt.balanceOf(alice, SILVER), 2);
    }

    // ═══════════════════════════════════════════════════════
    // PAUSE
    // ═══════════════════════════════════════════════════════

    function test_Pause() public {
        vm.prank(owner);
        mt.pause();

        vm.prank(alice);
        vm.expectRevert();
        mt.mint{value: BRONZE_PRICE}(alice, BRONZE, 1);
    }

    function test_Unpause() public {
        vm.prank(owner);
        mt.pause();

        vm.prank(owner);
        mt.unpause();

        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE}(alice, BRONZE, 1);

        assertEq(mt.balanceOf(alice, BRONZE), 1);
    }

    function test_PauseOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        mt.pause();
    }

    // ═══════════════════════════════════════════════════════
    // SUPPLY TRACKING
    // ═══════════════════════════════════════════════════════

    function test_TotalSupplyPerId() public {
        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE * 3}(alice, BRONZE, 3);
        vm.prank(bob);
        mt.mint{value: BRONZE_PRICE * 2}(bob, BRONZE, 2);

        assertEq(mt.totalSupply(BRONZE), 5);
    }

    function test_Exists() public {
        assertFalse(mt.exists(BRONZE));

        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE}(alice, BRONZE, 1);

        assertTrue(mt.exists(BRONZE));
    }

    function test_TotalSupplyGlobal() public {
        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE * 2}(alice, BRONZE, 2);
        vm.prank(alice);
        mt.mint{value: SILVER_PRICE}(alice, SILVER, 1);

        assertEq(mt.totalSupply(), 3);
    }

    // ═══════════════════════════════════════════════════════
    // CONFIGURATION (OWNER)
    // ═══════════════════════════════════════════════════════

    function test_SetMintPrice() public {
        vm.prank(owner);
        mt.setMintPrice(BRONZE, 0.1 ether);

        (, uint256 mintPrice, ) = mt.tokenTypes(BRONZE);
        assertEq(mintPrice, 0.1 ether);
    }

    function test_SetMintPriceOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        mt.setMintPrice(BRONZE, 0);
    }

    function test_SetMintPriceNonexistent() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSignature("TokenTypeDoesNotExist(uint256)", 999)
        );
        mt.setMintPrice(999, 0);
    }

    function test_SetMaxSupply() public {
        vm.prank(owner);
        mt.setMaxSupply(BRONZE, 500);

        (uint256 maxSupply, , ) = mt.tokenTypes(BRONZE);
        assertEq(maxSupply, 500);
    }

    function test_SetMaxSupplyOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        mt.setMaxSupply(BRONZE, 100);
    }

    function test_SetMaxSupplyNonexistent() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSignature("TokenTypeDoesNotExist(uint256)", 999)
        );
        mt.setMaxSupply(999, 100);
    }

    // ═══════════════════════════════════════════════════════
    // WITHDRAW
    // ═══════════════════════════════════════════════════════

    function test_Withdraw() public {
        // Mint to accumulate ETH
        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE * 5}(alice, BRONZE, 5);

        uint256 contractBalance = address(mt).balance;
        assertEq(contractBalance, BRONZE_PRICE * 5);

        uint256 ownerBalBefore = owner.balance;

        vm.prank(owner);
        mt.withdraw();

        assertEq(address(mt).balance, 0);
        assertEq(owner.balance, ownerBalBefore + contractBalance);
    }

    function test_WithdrawOnlyOwner() public {
        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE}(alice, BRONZE, 1);

        vm.prank(stranger);
        vm.expectRevert();
        mt.withdraw();
    }

    function test_WithdrawNoFunds() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("NoFundsToWithdraw()"));
        mt.withdraw();
    }

    // ═══════════════════════════════════════════════════════
    // TRANSFERS
    // ═══════════════════════════════════════════════════════

    function test_SafeTransferFrom() public {
        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE * 5}(alice, BRONZE, 5);

        vm.prank(alice);
        mt.safeTransferFrom(alice, bob, BRONZE, 3, "");

        assertEq(mt.balanceOf(alice, BRONZE), 2);
        assertEq(mt.balanceOf(bob, BRONZE), 3);
    }

    function test_SafeBatchTransferFrom() public {
        vm.prank(alice);
        mt.mint{value: BRONZE_PRICE * 3}(alice, BRONZE, 3);
        vm.prank(alice);
        mt.mint{value: SILVER_PRICE * 2}(alice, SILVER, 2);

        uint256[] memory ids = new uint256[](2);
        ids[0] = BRONZE;
        ids[1] = SILVER;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        vm.prank(alice);
        mt.safeBatchTransferFrom(alice, bob, ids, amounts, "");

        assertEq(mt.balanceOf(alice, BRONZE), 2);
        assertEq(mt.balanceOf(alice, SILVER), 1);
        assertEq(mt.balanceOf(bob, BRONZE), 1);
        assertEq(mt.balanceOf(bob, SILVER), 1);
    }

    // ═══════════════════════════════════════════════════════
    // SUPPORTS INTERFACE
    // ═══════════════════════════════════════════════════════

    function test_SupportsInterface() public view {
        // ERC-1155 interface
        assertTrue(mt.supportsInterface(0xd9b67a26));
        // ERC-1155 Metadata
        assertTrue(mt.supportsInterface(0x0e89341c));
        // ERC-165
        assertTrue(mt.supportsInterface(0x01ffc9a7));
    }
}
