// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AuroraToken
/// @notice ERC-20 token for the Aurora Pathways ecosystem
/// @dev Standard ERC-20 with owner-only minting and a 1 billion supply cap
contract AuroraToken is ERC20, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18; // 1 billion tokens

    error ExceedsMaxSupply(uint256 requested, uint256 max);

    constructor(address initialOwner) ERC20("Aurora Token", "AURA") Ownable(initialOwner) {}

    /// @notice Mint new tokens — only owner can call
    /// @param to Recipient address
    /// @param amount Amount to mint (in wei)
    function mint(address to, uint256 amount) external onlyOwner {
        if (totalSupply() + amount > MAX_SUPPLY) {
            revert ExceedsMaxSupply(totalSupply() + amount, MAX_SUPPLY);
        }
        _mint(to, amount);
    }

    /// @notice Burn tokens from caller's balance
    /// @param amount Amount to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
