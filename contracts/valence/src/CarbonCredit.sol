// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title CarbonCredit — ERC-20 token representing 1 ton of CO2 reduced
contract CarbonCredit is ERC20, Ownable {
    address public minter;
    uint256 public totalMinted;
    uint256 public totalRetired;

    event CreditsMinted(address indexed to, uint256 amount, string siteId, uint256 timestamp);
    event CreditsRetired(address indexed from, uint256 amount, string reason);
    event MinterUpdated(address oldMinter, address newMinter);

    constructor(address _minter) ERC20("Valence Carbon Credit", "VC02") Ownable(msg.sender) {
        minter = _minter;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "Not authorized minter");
        _;
    }

    function mint(address to, uint256 amount, string calldata siteId) external onlyMinter {
        _mint(to, amount);
        totalMinted += amount;
        emit CreditsMinted(to, amount, siteId, block.timestamp);
    }

    function retire(uint256 amount, string calldata reason) external {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _burn(msg.sender, amount);
        totalRetired += amount;
        emit CreditsRetired(msg.sender, amount, reason);
    }

    function setMinter(address newMinter) external onlyOwner {
        emit MinterUpdated(minter, newMinter);
        minter = newMinter;
    }
}
