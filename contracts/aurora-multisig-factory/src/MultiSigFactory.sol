// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AuroraMultiSig} from "./AuroraMultiSig.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MultiSigFactory
/// @notice Deploy custom multi-sig wallets for Aurora Pathways clients
/// @dev Features:
///      - Deploy new AuroraMultiSig instances with custom signers/threshold
///      - Track all deployed wallets
///      - Query wallets by owner/creator
///      - Factory owner can deploy on behalf of clients
contract MultiSigFactory is Ownable {
    // ─── Events ───

    event MultiSigDeployed(
        address indexed wallet,
        address indexed creator,
        address[] signers,
        uint256 threshold
    );

    // ─── State ───

    /// @notice All deployed multi-sig wallet addresses
    address[] public deployedWallets;

    /// @notice Wallets deployed by a specific creator
    mapping(address => address[]) public walletsByCreator;

    /// @notice Whether an address is a deployed multi-sig from this factory
    mapping(address => bool) public isDeployedWallet;

    // ─── Constructor ───

    constructor(address owner_) Ownable(owner_) {}

    // ─── Deploy ───

    /// @notice Deploy a new multi-sig wallet
    /// @param _signers Authorized signer addresses
    /// @param _threshold Required confirmations (1 to signers.length)
    /// @param _owner Owner of the multi-sig (can update signers later)
    /// @return wallet Address of the deployed multi-sig
    function deployMultiSig(
        address[] calldata _signers,
        uint256 _threshold,
        address _owner
    ) external returns (address wallet) {
        AuroraMultiSig ms = new AuroraMultiSig(_signers, _threshold, _owner);
        wallet = address(ms);

        deployedWallets.push(wallet);
        walletsByCreator[msg.sender].push(wallet);
        isDeployedWallet[wallet] = true;

        emit MultiSigDeployed(wallet, msg.sender, _signers, _threshold);
    }

    // ─── View Functions ───

    /// @notice Get total number of deployed wallets
    function getDeployedCount() external view returns (uint256) {
        return deployedWallets.length;
    }

    /// @notice Get wallets deployed by a specific creator
    function getWalletsByCreator(address creator) external view returns (address[] memory) {
        return walletsByCreator[creator];
    }

    /// @notice Get all deployed wallet addresses
    function getAllWallets() external view returns (address[] memory) {
        return deployedWallets;
    }
}
