// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AuroraMultiSig} from "../src/AuroraMultiSig.sol";
import {MultiSigFactory} from "../src/MultiSigFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract AuroraMultiSigTest is Test {
    MultiSigFactory public factory;
    AuroraMultiSig public wallet;

    // Actors
    address public factoryOwner = makeAddr("factoryOwner");
    address public msOwner = makeAddr("msOwner");
    address public signer1 = makeAddr("signer1");
    address public signer2 = makeAddr("signer2");
    address public signer3 = makeAddr("signer3");
    address public nonSigner = makeAddr("nonSigner");

    address[] public signers;
    uint256 constant THRESHOLD = 2; // 2-of-3

    // ─── Setup ───

    function setUp() public {
        // Create signers array
        signers.push(signer1);
        signers.push(signer2);
        signers.push(signer3);

        // Deploy factory
        vm.prank(factoryOwner);
        factory = new MultiSigFactory(factoryOwner);

        // Deploy a multi-sig via factory
        vm.prank(factoryOwner);
        address walletAddr = factory.deployMultiSig(signers, THRESHOLD, msOwner);
        wallet = AuroraMultiSig(payable(walletAddr));

        // Fund the wallet
        vm.deal(address(wallet), 10 ether);
    }

    // ═══════════════════════════════════════════════════════
    // FACTORY
    // ═══════════════════════════════════════════════════════

    function test_FactoryOwner() public view {
        assertEq(factory.owner(), factoryOwner);
    }

    function test_FactoryDeploy() public view {
        assertEq(factory.getDeployedCount(), 1);
        assertTrue(factory.isDeployedWallet(address(wallet)));
    }

    function test_FactoryWalletsByCreator() public {
        address[] memory wallets = factory.getWalletsByCreator(factoryOwner);
        assertEq(wallets.length, 1);
        assertEq(wallets[0], address(wallet));
    }

    function test_FactoryDeployMultiple() public {
        address[] memory signers2 = new address[](2);
        signers2[0] = makeAddr("s1");
        signers2[1] = makeAddr("s2");

        vm.prank(factoryOwner);
        factory.deployMultiSig(signers2, 1, msOwner);

        assertEq(factory.getDeployedCount(), 2);
    }

    function test_FactoryAllWallets() public {
        address[] memory all = factory.getAllWallets();
        assertEq(all.length, 1);
        assertEq(all[0], address(wallet));
    }

    // ═══════════════════════════════════════════════════════
    // WALLET DEPLOYMENT
    // ═══════════════════════════════════════════════════════

    function test_WalletSigners() public view {
        assertEq(wallet.getSignerCount(), 3);
        assertTrue(wallet.isSigner(signer1));
        assertTrue(wallet.isSigner(signer2));
        assertTrue(wallet.isSigner(signer3));
        assertFalse(wallet.isSigner(nonSigner));
    }

    function test_WalletThreshold() public view {
        assertEq(wallet.threshold(), THRESHOLD);
    }

    function test_WalletOwner() public view {
        assertEq(wallet.owner(), msOwner);
    }

    function test_WalletBalance() public view {
        assertEq(address(wallet).balance, 10 ether);
    }

    function test_WalletInvalidThreshold() public {
        address[] memory s = new address[](1);
        s[0] = signer1;

        vm.prank(factoryOwner);
        vm.expectRevert(
            abi.encodeWithSignature("InvalidThreshold(uint256,uint256)", 2, 1)
        );
        factory.deployMultiSig(s, 2, msOwner);
    }

    function test_WalletZeroSigners() public {
        address[] memory empty = new address[](0);

        vm.prank(factoryOwner);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigners()"));
        factory.deployMultiSig(empty, 1, msOwner);
    }

    // ═══════════════════════════════════════════════════════
    // RECEIVE ETH
    // ═══════════════════════════════════════════════════════

    function test_ReceiveETH() public {
        uint256 balBefore = address(wallet).balance;
        vm.deal(nonSigner, 5 ether);

        vm.prank(nonSigner);
        (bool ok, ) = address(wallet).call{value: 5 ether}("");
        assertTrue(ok);
        assertEq(address(wallet).balance, balBefore + 5 ether);
    }

    // ═══════════════════════════════════════════════════════
    // SUBMIT TRANSACTION
    // ═══════════════════════════════════════════════════════

    function test_SubmitTransaction() public {
        vm.prank(signer1);
        uint256 txId = wallet.submitTransaction(nonSigner, 1 ether, "");

        assertEq(wallet.getTransactionCount(), 1);
        assertEq(wallet.txCountPerSigner(signer1), 1);

        (address to, uint256 value, , bool executed, uint256 confs) = wallet.getTransaction(txId);
        assertEq(to, nonSigner);
        assertEq(value, 1 ether);
        assertFalse(executed);
        assertEq(confs, 0);
    }

    function test_SubmitTransactionNotSigner() public {
        vm.prank(nonSigner);
        vm.expectRevert(
            abi.encodeWithSignature("NotSigner(address)", nonSigner)
        );
        wallet.submitTransaction(nonSigner, 1 ether, "");
    }

    // ═══════════════════════════════════════════════════════
    // CONFIRM & EXECUTE
    // ═══════════════════════════════════════════════════════

    function test_ConfirmAndExecute() public {
        // Submit
        vm.prank(signer1);
        uint256 txId = wallet.submitTransaction(nonSigner, 1 ether, "");

        // First confirmation (signer1)
        vm.prank(signer1);
        wallet.confirmTransaction(txId);

        // Second confirmation (signer2) — meets threshold
        vm.prank(signer2);
        wallet.confirmTransaction(txId);

        // Execute
        uint256 recipientBalBefore = nonSigner.balance;
        vm.prank(signer1);
        wallet.executeTransaction(txId);

        assertEq(nonSigner.balance, recipientBalBefore + 1 ether);

        (, , , bool executed, uint256 confs) = wallet.getTransaction(txId);
        assertTrue(executed);
        assertEq(confs, 2);
    }

    function test_ExecuteWithoutEnoughConfirmations() public {
        vm.prank(signer1);
        uint256 txId = wallet.submitTransaction(nonSigner, 1 ether, "");

        vm.prank(signer1);
        wallet.confirmTransaction(txId);

        vm.prank(signer1);
        vm.expectRevert(
            abi.encodeWithSignature("InsufficientConfirmations(uint256,uint256)", 1, 2)
        );
        wallet.executeTransaction(txId);
    }

    function test_ExecuteOnlySigner() public {
        vm.prank(signer1);
        uint256 txId = wallet.submitTransaction(nonSigner, 1 ether, "");

        vm.prank(nonSigner);
        vm.expectRevert(
            abi.encodeWithSignature("NotSigner(address)", nonSigner)
        );
        wallet.executeTransaction(txId);
    }

    function test_ConfirmNotSigner() public {
        vm.prank(signer1);
        uint256 txId = wallet.submitTransaction(nonSigner, 1 ether, "");

        vm.prank(nonSigner);
        vm.expectRevert(
            abi.encodeWithSignature("NotSigner(address)", nonSigner)
        );
        wallet.confirmTransaction(txId);
    }

    function test_ConfirmAlreadyConfirmed() public {
        vm.prank(signer1);
        uint256 txId = wallet.submitTransaction(nonSigner, 1 ether, "");

        vm.prank(signer1);
        wallet.confirmTransaction(txId);

        vm.prank(signer1);
        vm.expectRevert(
            abi.encodeWithSignature("TxAlreadyConfirmed(uint256)", txId)
        );
        wallet.confirmTransaction(txId);
    }

    function test_ConfirmNonexistentTx() public {
        vm.prank(signer1);
        vm.expectRevert(
            abi.encodeWithSignature("TxDoesNotExist(uint256)", 999)
        );
        wallet.confirmTransaction(999);
    }

    function test_ExecuteAlreadyExecuted() public {
        vm.prank(signer1);
        uint256 txId = wallet.submitTransaction(nonSigner, 1 ether, "");

        vm.prank(signer1);
        wallet.confirmTransaction(txId);
        vm.prank(signer2);
        wallet.confirmTransaction(txId);

        vm.prank(signer1);
        wallet.executeTransaction(txId);

        vm.prank(signer1);
        vm.expectRevert(
            abi.encodeWithSignature("TxAlreadyExecuted(uint256)", txId)
        );
        wallet.executeTransaction(txId);
    }

    // ═══════════════════════════════════════════════════════
    // REVOKE CONFIRMATION
    // ═══════════════════════════════════════════════════════

    function test_RevokeConfirmation() public {
        vm.prank(signer1);
        uint256 txId = wallet.submitTransaction(nonSigner, 1 ether, "");

        vm.prank(signer1);
        wallet.confirmTransaction(txId);

        (, , , , uint256 confs) = wallet.getTransaction(txId);
        assertEq(confs, 1);

        vm.prank(signer1);
        wallet.revokeConfirmation(txId);

        (, , , , confs) = wallet.getTransaction(txId);
        assertEq(confs, 0);
    }

    function test_RevokeNotConfirmed() public {
        vm.prank(signer1);
        uint256 txId = wallet.submitTransaction(nonSigner, 1 ether, "");

        vm.prank(signer1);
        vm.expectRevert(
            abi.encodeWithSignature("TxNotConfirmed(uint256)", txId)
        );
        wallet.revokeConfirmation(txId);
    }

    function test_RevokeAlreadyExecuted() public {
        vm.prank(signer1);
        uint256 txId = wallet.submitTransaction(nonSigner, 1 ether, "");

        vm.prank(signer1);
        wallet.confirmTransaction(txId);
        vm.prank(signer2);
        wallet.confirmTransaction(txId);
        vm.prank(signer1);
        wallet.executeTransaction(txId);

        vm.prank(signer1);
        vm.expectRevert(
            abi.encodeWithSignature("TxAlreadyExecuted(uint256)", txId)
        );
        wallet.revokeConfirmation(txId);
    }

    // ═══════════════════════════════════════════════════════
    // SIGNER MANAGEMENT (Owner)
    // ═══════════════════════════════════════════════════════

    function test_UpdateSigners() public {
        address[] memory newSigners = new address[](2);
        newSigners[0] = makeAddr("new1");
        newSigners[1] = makeAddr("new2");

        vm.prank(msOwner);
        wallet.updateSigners(newSigners, 1);

        assertEq(wallet.getSignerCount(), 2);
        assertTrue(wallet.isSigner(newSigners[0]));
        assertTrue(wallet.isSigner(newSigners[1]));
        assertFalse(wallet.isSigner(signer1)); // removed
    }

    function test_UpdateSignersOnlyOwner() public {
        address[] memory newSigners = new address[](1);
        newSigners[0] = makeAddr("new1");

        vm.prank(signer1);
        vm.expectRevert();
        wallet.updateSigners(newSigners, 1);
    }

    function test_UpdateSignersInvalidThreshold() public {
        address[] memory newSigners = new address[](1);
        newSigners[0] = makeAddr("new1");

        vm.prank(msOwner);
        vm.expectRevert(
            abi.encodeWithSignature("InvalidThreshold(uint256,uint256)", 2, 1)
        );
        wallet.updateSigners(newSigners, 2);
    }

    // ═══════════════════════════════════════════════════════
    // GET SIGNERS
    // ═══════════════════════════════════════════════════════

    function test_GetSigners() public {
        address[] memory s = wallet.getSigners();
        assertEq(s.length, 3);
        assertEq(s[0], signer1);
        assertEq(s[1], signer2);
        assertEq(s[2], signer3);
    }
}
