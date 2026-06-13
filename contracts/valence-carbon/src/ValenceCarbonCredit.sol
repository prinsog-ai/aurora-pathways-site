// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ValenceCarbonCredit
/// @notice ERC-20 token representing carbon credits on the Valence platform
/// @dev 1 VCC = 1 metric ton of CO2 reduced. Minted by the platform contract
///      when MRV data is verified. Burnable by holders (retirement).
contract ValenceCarbonCredit is ERC20, ERC20Burnable, Ownable {
    uint256 public constant MAX_SUPPLY = 500_000_000 * 1e18; // 500M VCC cap

    error ExceedsMaxSupply(uint256 requested, uint256 max);

    /// @param initialOwner Address that owns the contract (platform)
    constructor(address initialOwner)
        ERC20("Valence Carbon Credit", "VCC")
        Ownable(initialOwner)
    {}

    /// @notice Mint new carbon credits — only owner (platform) can call
    /// @param to Recipient address
    /// @param amount Amount in wei (1e18 = 1 credit = 1 ton CO2)
    function mint(address to, uint256 amount) external onlyOwner {
        if (totalSupply() + amount > MAX_SUPPLY) {
            revert ExceedsMaxSupply(totalSupply() + amount, MAX_SUPPLY);
        }
        _mint(to, amount);
    }
}
