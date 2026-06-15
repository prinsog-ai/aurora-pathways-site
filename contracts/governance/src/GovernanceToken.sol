// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title GovernanceToken
/// @notice ERC20Votes token for protocol governance.
/// @dev Each protocol deploys its own instance with a unique name/symbol.
///      Supports vote delegation (required for Governor to count votes).
///      Owner can mint tokens for initial distribution.
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    uint256 public immutable maxSupply;

    error GovernanceToken__ExceedsMaxSupply();
    error GovernanceToken__ZeroAmount();

    /// @param _name       Token name (e.g. "TaskEscrow Token")
    /// @param _symbol     Token symbol (e.g. "TET")
    /// @param _maxSupply  Maximum token supply (in wei)
    /// @param _owner      Initial owner who can mint
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        address _owner
    ) ERC20(_name, _symbol) ERC20Permit(_name) Ownable(_owner) {
        maxSupply = _maxSupply;
    }

    // ───────────── Minting ─────────────

    /// @notice Mint tokens to an address. Only owner can call.
    /// @param to    Recipient address
    /// @param amount Amount to mint (in wei)
    function mint(address to, uint256 amount) external onlyOwner {
        if (amount == 0) revert GovernanceToken__ZeroAmount();
        if (totalSupply() + amount > maxSupply) revert GovernanceToken__ExceedsMaxSupply();
        _mint(to, amount);
    }

    // ───────────── Required Overrides ─────────────

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
