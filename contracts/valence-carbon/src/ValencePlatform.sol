// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ValenceCarbonCredit} from "./ValenceCarbonCredit.sol";

/// @title ValencePlatform
/// @notice Core platform for carbon credit issuance, site management, and revenue splitting
/// @dev Manages flare gas capture sites, MRV (Measurement/Reporting/Verification) data,
///      and automatic credit distribution between Valence and site owners.
///      1 VCC token = 1 metric ton of CO2 reduced.
contract ValencePlatform is Ownable, ReentrancyGuard {

    // ─── Token ──────────────────────────────────────────────────
    ValenceCarbonCredit public immutable creditToken;

    // ─── Conversion factor ──────────────────────────────────────
    /// @dev CO2 tons = gasMCF * co2Factor / 10_000
    ///      Default 360 → 3.6% → 80,000 MCF ≈ 2,880 tons
    uint256 public co2Factor;
    uint256 public constant CO2_FACTOR_PRECISION = 10_000;

    // ─── Site data ──────────────────────────────────────────────
    struct Site {
        uint256 id;
        string name;
        string location;
        address siteOwner;
        uint256 valenceShareBps;  // basis points (6000 = 60%)
        uint256 totalGasMCF;      // cumulative MCF logged
        uint256 totalCredits;     // cumulative credits issued
        bool active;
        uint256 createdAt;
    }

    mapping(uint256 => Site) public sites;
    uint256 public siteCount;

    // ─── MRV data ───────────────────────────────────────────────
    struct MRVEntry {
        uint256 id;
        uint256 siteId;
        address submittedBy;
        uint256 gasVolumeMCF;
        uint256 co2ReducedTons;
        uint256 creditsIssued;
        uint256 valenceCredits;
        uint256 siteOwnerCredits;
        uint256 timestamp;
        bool verified;
    }

    mapping(uint256 => MRVEntry) public mrvEntries;
    uint256 public mrvCount;

    // ─── Whitelist for data entry ───────────────────────────────
    mapping(address => bool) public dataSubmitters;

    // ─── Events ─────────────────────────────────────────────────
    event SiteRegistered(uint256 indexed siteId, string name, address siteOwner, uint256 valenceShareBps);
    event SiteUpdated(uint256 indexed siteId, bool active, uint256 valenceShareBps);
    event MRVSubmitted(uint256 indexed mrvId, uint256 indexed siteId, address submittedBy, uint256 gasVolumeMCF, uint256 co2ReducedTons, uint256 creditsIssued);
    event CreditsDistributed(uint256 indexed mrvId, address valence, uint256 valenceCredits, address siteOwner, uint256 siteOwnerCredits);
    event DataSubmitterUpdated(address indexed submitter, bool allowed);
    event Co2FactorUpdated(uint256 oldFactor, uint256 newFactor);
    event TokensWithdrawn(address indexed to, uint256 amount);

    // ─── Errors ─────────────────────────────────────────────────
    error InvalidSite();
    error SiteNotActive();
    error Unauthorized();
    error ZeroVolume();
    error InvalidShare();
    error TransferFailed();

    // ─── Constructor ────────────────────────────────────────────
    /// @param _owner Platform admin / multisig address
    /// @param _creditToken Address of the deployed ValenceCarbonCredit token
    /// @param _co2Factor Initial CO2 conversion factor (basis points; 360 = 3.6%)
    constructor(address _owner, address _creditToken, uint256 _co2Factor)
        Ownable(_owner)
    {
        creditToken = ValenceCarbonCredit(_creditToken);
        co2Factor = _co2Factor;
        dataSubmitters[_owner] = true;
    }

    // ─── Admin functions ────────────────────────────────────────

    /// @notice Register a new flare gas capture site
    /// @param _name Human-readable site name
    /// @param _location Location description
    /// @param _siteOwner Wallet that receives the owner's share of credits
    /// @param _valenceShareBps Valence's cut in basis points (6000 = 60%)
    /// @return siteId The new site's ID
    function registerSite(
        string calldata _name,
        string calldata _location,
        address _siteOwner,
        uint256 _valenceShareBps
    ) external onlyOwner returns (uint256 siteId) {
        if (_valenceShareBps > 10_000) revert InvalidShare();

        siteId = ++siteCount;
        sites[siteId] = Site({
            id: siteId,
            name: _name,
            location: _location,
            siteOwner: _siteOwner,
            valenceShareBps: _valenceShareBps,
            totalGasMCF: 0,
            totalCredits: 0,
            active: true,
            createdAt: block.timestamp
        });

        emit SiteRegistered(siteId, _name, _siteOwner, _valenceShareBps);
    }

    /// @notice Update site parameters
    function updateSite(
        uint256 _siteId,
        bool _active,
        uint256 _valenceShareBps,
        address _newOwner
    ) external onlyOwner {
        if (_siteId == 0 || _siteId > siteCount) revert InvalidSite();
        if (_valenceShareBps > 10_000) revert InvalidShare();

        Site storage s = sites[_siteId];
        s.active = _active;
        s.valenceShareBps = _valenceShareBps;
        if (_newOwner != address(0)) {
            s.siteOwner = _newOwner;
        }

        emit SiteUpdated(_siteId, _active, _valenceShareBps);
    }

    /// @notice Grant or revoke data entry permission
    function setDataSubmitter(address _submitter, bool _allowed) external onlyOwner {
        dataSubmitters[_submitter] = _allowed;
        emit DataSubmitterUpdated(_submitter, _allowed);
    }

    /// @notice Update the CO2 conversion factor
    function setCo2Factor(uint256 _newFactor) external onlyOwner {
        uint256 old = co2Factor;
        co2Factor = _newFactor;
        emit Co2FactorUpdated(old, _newFactor);
    }

    // ─── Core operations ────────────────────────────────────────

    /// @notice Submit MRV data and issue carbon credits
    /// @dev Calculates CO2 reduced, mints VCC tokens, and auto-splits
    ///      between Valence and the site owner.
    /// @param _siteId The site this data belongs to
    /// @param _gasVolumeMCF Flare gas captured in MCF (thousands of cubic feet)
    /// @return mrvId The MRV entry ID
    function submitMRV(uint256 _siteId, uint256 _gasVolumeMCF)
        external
        nonReentrant
        returns (uint256 mrvId)
    {
        if (!dataSubmitters[msg.sender]) revert Unauthorized();
        if (_siteId == 0 || _siteId > siteCount) revert InvalidSite();
        if (_gasVolumeMCF == 0) revert ZeroVolume();

        Site storage site = sites[_siteId];
        if (!site.active) revert SiteNotActive();

        // Calculate CO2 reduced (1 credit = 1 ton CO2)
        uint256 co2Tons = (_gasVolumeMCF * co2Factor) / CO2_FACTOR_PRECISION;
        if (co2Tons == 0) revert ZeroVolume();

        // Calculate split
        uint256 valenceCredits = (co2Tons * site.valenceShareBps) / 10_000;
        uint256 siteOwnerCredits = co2Tons - valenceCredits;

        // Record MRV
        mrvId = ++mrvCount;
        mrvEntries[mrvId] = MRVEntry({
            id: mrvId,
            siteId: _siteId,
            submittedBy: msg.sender,
            gasVolumeMCF: _gasVolumeMCF,
            co2ReducedTons: co2Tons,
            creditsIssued: co2Tons,
            valenceCredits: valenceCredits,
            siteOwnerCredits: siteOwnerCredits,
            timestamp: block.timestamp,
            verified: true
        });

        // Update site totals
        site.totalGasMCF += _gasVolumeMCF;
        site.totalCredits += co2Tons;

        // Mint and distribute credits (1 credit = 1e18 tokens = 1 ton CO2)
        uint256 mintValence = valenceCredits * 1e18;
        uint256 mintOwner = siteOwnerCredits * 1e18;
        // Valence share goes to the contract (owner collects later)
        if (mintValence > 0) {
            creditToken.mint(address(this), mintValence);
        }
        // Site owner gets their share directly
        if (mintOwner > 0) {
            creditToken.mint(site.siteOwner, mintOwner);
        }

        emit MRVSubmitted(mrvId, _siteId, msg.sender, _gasVolumeMCF, co2Tons, co2Tons);
        emit CreditsDistributed(mrvId, address(this), valenceCredits, site.siteOwner, siteOwnerCredits);
    }

    // ─── Valence revenue management ─────────────────────────────

    /// @notice Transfer Valence's accumulated credits to a recipient
    /// @dev Only owner can withdraw the platform's share
    function withdrawValenceCredits(address _to, uint256 _amount) external onlyOwner {
        uint256 bal = creditToken.balanceOf(address(this));
        if (_amount > bal) revert TransferFailed();
        bool success = creditToken.transfer(_to, _amount);
        if (!success) revert TransferFailed();
        emit TokensWithdrawn(_to, _amount);
    }

    // ─── View helpers ───────────────────────────────────────────

    /// @notice Get a site's info
    function getSite(uint256 _siteId) external view returns (Site memory) {
        if (_siteId == 0 || _siteId > siteCount) revert InvalidSite();
        return sites[_siteId];
    }

    /// @notice Get an MRV entry
    function getMRV(uint256 _mrvId) external view returns (MRVEntry memory) {
        if (_mrvId == 0 || _mrvId > mrvCount) revert InvalidSite();
        return mrvEntries[_mrvId];
    }

    /// @notice Calculate expected credits for a given gas volume
    function estimateCredits(uint256 _gasVolumeMCF) external view returns (uint256) {
        return (_gasVolumeMCF * co2Factor) / CO2_FACTOR_PRECISION;
    }

    /// @notice Platform's current VCC balance
    function platformCreditBalance() external view returns (uint256) {
        return creditToken.balanceOf(address(this));
    }
}
