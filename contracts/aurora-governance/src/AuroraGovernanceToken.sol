// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title AuroraGovernanceToken
/// @notice Governance token for the Aurora Pathways DAO
/// @dev ERC-20 with voting, delegation, permit (gasless approvals), and owner-only minting
contract AuroraGovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18; // 1 billion tokens

    error ExceedsMaxSupply(uint256 requested, uint256 max);

    constructor(address initialOwner)
        ERC20("Aurora Governance", "AURAG")
        ERC20Permit("Aurora Governance")
        Ownable(initialOwner)
    {}

    /// @notice Mint new governance tokens — only owner
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

    // ──────────── Required overrides ────────────

    /// @dev Clock for ERC-6372 — block numbers (matching Governor's default)
    function clock() public view override returns (uint48) {
        return uint48(block.number);
    }

    /// @dev Clock mode string per ERC-6372
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    /// @dev Hook required by ERC20Votes and ERC20Permit
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    /// @dev Required by ERC20Permit + ERC20Votes (both inherit Nonces)
    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
