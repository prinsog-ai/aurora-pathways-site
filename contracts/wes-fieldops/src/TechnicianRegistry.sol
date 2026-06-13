// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TechnicianRegistry
/// @notice Manages registration, certification, and reputation of WES field technicians
/// @dev Only owner (WES admin) can register/certify technicians. Ratings are public.
contract TechnicianRegistry is Ownable {

    enum Specialization { Electrical, Plumbing, HVAC, Structural, Mechanical, General }
    enum Tier { Bronze, Silver, Gold, Platinum }

    struct Technician {
        address wallet;
        string name;
        Specialization specialization;
        Tier tier;
        bool isActive;
        bool isCertified;
        uint256 totalJobs;
        uint256 completedJobs;
        uint256 totalRating;   // sum of all ratings (1-5)
        uint256 ratingCount;
        uint256 registeredAt;
        uint256 lastActiveAt;
    }

    // Storage
    mapping(address => Technician) public technicians;
    address[] public technicianList;
    mapping(Specialization => address[]) public techniciansBySpec;
    mapping(address => mapping(address => bool)) public hasRated; // client => tech => rated

    // Events
    event TechnicianRegistered(address indexed tech, string name, Specialization spec);
    event TechnicianCertified(address indexed tech, Tier tier);
    event TechnicianDeactivated(address indexed tech);
    event TechnicianReactivated(address indexed tech);
    event TechnicianRated(address indexed tech, address indexed client, uint8 rating);
    event TierUpgraded(address indexed tech, Tier oldTier, Tier newTier);

    // Errors
    error AlreadyRegistered();
    error NotRegistered();
    error NotCertified();
    error InvalidRating();
    error AlreadyRated();
    error NotActive();

    constructor() Ownable(msg.sender) {}

    /// @notice Register a new field technician
    function registerTechnician(
        address _wallet,
        string calldata _name,
        Specialization _spec
    ) external onlyOwner {
        if (technicians[_wallet].wallet != address(0)) revert AlreadyRegistered();

        technicians[_wallet] = Technician({
            wallet: _wallet,
            name: _name,
            specialization: _spec,
            tier: Tier.Bronze,
            isActive: true,
            isCertified: false,
            totalJobs: 0,
            completedJobs: 0,
            totalRating: 0,
            ratingCount: 0,
            registeredAt: block.timestamp,
            lastActiveAt: block.timestamp
        });

        technicianList.push(_wallet);
        techniciansBySpec[_spec].push(_wallet);

        emit TechnicianRegistered(_wallet, _name, _spec);
    }

    /// @notice Certify a technician (allows accepting work orders)
    function certifyTechnician(address _tech, Tier _tier) external onlyOwner {
        if (technicians[_tech].wallet == address(0)) revert NotRegistered();
        technicians[_tech].isCertified = true;
        technicians[_tech].tier = _tier;
        emit TechnicianCertified(_tech, _tier);
    }

    /// @notice Deactivate a technician
    function deactivateTechnician(address _tech) external onlyOwner {
        if (technicians[_tech].wallet == address(0)) revert NotRegistered();
        technicians[_tech].isActive = false;
        emit TechnicianDeactivated(_tech);
    }

    /// @notice Reactivate a technician
    function reactivateTechnician(address _tech) external onlyOwner {
        if (technicians[_tech].wallet == address(0)) revert NotRegistered();
        technicians[_tech].isActive = true;
        emit TechnicianReactivated(_tech);
    }

    /// @notice Rate a completed job (1-5 stars, called by client)
    function rateTechnician(address _tech, uint8 _rating) external {
        if (technicians[_tech].wallet == address(0)) revert NotRegistered();
        if (_rating < 1 || _rating > 5) revert InvalidRating();
        if (hasRated[msg.sender][_tech]) revert AlreadyRated();

        hasRated[msg.sender][_tech] = true;
        technicians[_tech].totalRating += _rating;
        technicians[_tech].ratingCount += 1;

        // Auto-tier upgrade check
        _checkTierUpgrade(_tech);

        emit TechnicianRated(_tech, msg.sender, _rating);
    }

    /// @notice Record job assignment (called by WorkOrderManager)
    function recordJobAssignment(address _tech) external onlyOwner {
        technicians[_tech].totalJobs += 1;
        technicians[_tech].lastActiveAt = block.timestamp;
    }

    /// @notice Record job completion (called by WorkOrderManager)
    function recordJobCompletion(address _tech) external onlyOwner {
        technicians[_tech].completedJobs += 1;
    }

    /// @dev Auto-tier upgrade based on completed jobs and rating (avgRating is 1-5 scale, integer)
    function _checkTierUpgrade(address _tech) internal {
        Technician storage tech = technicians[_tech];
        if (tech.ratingCount < 3) return; // need minimum ratings

        // Use 100x precision to avoid integer truncation: (total * 100) / count
        uint256 avgRatingX100 = (tech.totalRating * 100) / tech.ratingCount;
        Tier oldTier = tech.tier;
        Tier newTier;

        if (tech.completedJobs >= 100 && avgRatingX100 >= 480) {      // 4.80+
            newTier = Tier.Platinum;
        } else if (tech.completedJobs >= 50 && avgRatingX100 >= 450) { // 4.50+
            newTier = Tier.Gold;
        } else if (tech.completedJobs >= 10 && avgRatingX100 >= 400) { // 4.00+
            newTier = Tier.Silver;
        } else {
            return; // no upgrade
        }

        if (newTier > oldTier) {
            tech.tier = newTier;
            emit TierUpgraded(_tech, oldTier, newTier);
        }
    }

    // --- View Functions ---

    function getTechnician(address _tech) external view returns (Technician memory) {
        return technicians[_tech];
    }

    function getAverageRating(address _tech) external view returns (uint256) {
        if (technicians[_tech].ratingCount == 0) return 0;
        return (technicians[_tech].totalRating * 100) / technicians[_tech].ratingCount; // *100 for 2 decimal precision
    }

    function getTechnicianCount() external view returns (uint256) {
        return technicianList.length;
    }

    function getTechniciansBySpec(Specialization _spec) external view returns (address[] memory) {
        return techniciansBySpec[_spec];
    }
}
