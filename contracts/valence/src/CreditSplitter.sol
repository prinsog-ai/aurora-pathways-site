// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./CarbonCredit.sol";

/// @title CreditSplitter — Auto-distributes minted credits between Valence and site owner
contract CreditSplitter is Ownable {
    CarbonCredit public creditToken;

    struct Site {
        string name;
        address siteOwner;
        uint256 valenceShare; // basis points (e.g. 6000 = 60%)
        uint256 totalDistributed;
        bool active;
    }

    mapping(string => Site) public sites;
    string[] public siteIds;

    event SiteRegistered(string siteId, address siteOwner, uint256 valenceShare);
    event CreditsDistributed(string siteId, uint256 valenceAmount, uint256 ownerAmount, uint256 total);
    event SiteUpdated(string siteId, uint256 newValenceShare);

    constructor(address _creditToken) Ownable(msg.sender) {
        creditToken = CarbonCredit(_creditToken);
    }

    function registerSite(
        string calldata siteId,
        address siteOwner,
        uint256 valenceShareBps
    ) external onlyOwner {
        require(valenceShareBps <= 10000, "Invalid share");
        require(sites[siteId].siteOwner == address(0), "Site exists");

        sites[siteId] = Site({
            name: siteId,
            siteOwner: siteOwner,
            valenceShare: valenceShareBps,
            totalDistributed: 0,
            active: true
        });
        siteIds.push(siteId);

        emit SiteRegistered(siteId, siteOwner, valenceShareBps);
    }

    function distribute(string calldata siteId, uint256 totalAmount) external onlyOwner {
        Site storage site = sites[siteId];
        require(site.active, "Site not active");

        uint256 valenceAmount = (totalAmount * site.valenceShare) / 10000;
        uint256 ownerAmount = totalAmount - valenceAmount;

        creditToken.transfer(owner(), valenceAmount);
        creditToken.transfer(site.siteOwner, ownerAmount);

        site.totalDistributed += totalAmount;

        emit CreditsDistributed(siteId, valenceAmount, ownerAmount, totalAmount);
    }

    function updateShare(string calldata siteId, uint256 newValenceShareBps) external onlyOwner {
        require(newValenceShareBps <= 10000, "Invalid share");
        sites[siteId].valenceShare = newValenceShareBps;
        emit SiteUpdated(siteId, newValenceShareBps);
    }

    function getSiteCount() external view returns (uint256) {
        return siteIds.length;
    }
}
