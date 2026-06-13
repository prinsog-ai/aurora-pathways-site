// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/WESJobTicket.sol";
import "../src/WESCompliance.sol";

contract WESTest is Test {
    WESJobTicket jobs;
    WESCompliance compliance;
    address crew1 = address(0x10);
    address client1 = address(0x20);

    function setUp() public {
        jobs = new WESJobTicket();
        compliance = new WESCompliance();
        jobs.registerCrew(crew1, "Alpha Crew", "Roustabout Lead");
        jobs.verifyCrew(crew1, true);
    }

    function test_create_job() public {
        uint256 id = jobs.createJob(client1, "Well Pad A", WESJobTicket.ServiceType.Roustabout, "Install flow lines", 5000e6);
        assertEq(id, 0);
        assertEq(jobs.getJobCount(), 1);
    }

    function test_assign_crew() public {
        uint256 id = jobs.createJob(client1, "Site A", WESJobTicket.ServiceType.Roustabout, "Work", 1000e6);
        jobs.assignCrew(id, crew1);
        assertEq(uint8(jobs.getJobStatus(id)), uint8(WESJobTicket.JobStatus.Assigned));
    }

    function test_job_lifecycle() public {
        uint256 id = jobs.createJob(client1, "Site A", WESJobTicket.ServiceType.Welding, "Weld pipe", 2000e6);
        jobs.assignCrew(id, crew1);
        vm.prank(crew1); jobs.startJob(id);
        assertEq(uint8(jobs.getJobStatus(id)), uint8(WESJobTicket.JobStatus.InProgress));
        vm.prank(crew1); jobs.completeJob(id, "QmEvidence123");
        assertEq(uint8(jobs.getJobStatus(id)), uint8(WESJobTicket.JobStatus.Completed));
    }

    function test_dispute_and_resolve() public {
        uint256 id = jobs.createJob(client1, "Site A", WESJobTicket.ServiceType.HydroExcavation, "Dig", 3000e6);
        jobs.assignCrew(id, crew1);
        vm.prank(crew1); jobs.startJob(id);
        vm.prank(crew1); jobs.completeJob(id, "QmHash");
        jobs.disputeJob(id, "Incomplete scope");
        assertEq(uint8(jobs.getJobStatus(id)), uint8(WESJobTicket.JobStatus.Disputed));
        jobs.resolveDispute(id, true);
        assertEq(uint8(jobs.getJobStatus(id)), uint8(WESJobTicket.JobStatus.Completed));
    }

    function test_mark_paid() public {
        uint256 id = jobs.createJob(client1, "Site A", WESJobTicket.ServiceType.Roustabout, "Work", 1000e6);
        jobs.assignCrew(id, crew1);
        vm.prank(crew1); jobs.startJob(id);
        vm.prank(crew1); jobs.completeJob(id, "QmHash");
        jobs.markPaid(id);
        // Verify via job data
        (,,,,,,,,,,, bool paid) = jobs.jobs(id);
        assertTrue(paid);
    }

    function test_unverified_crew_rejected() public {
        uint256 id = jobs.createJob(client1, "Site A", WESJobTicket.ServiceType.Roustabout, "Work", 1000e6);
        vm.expectRevert("Crew not verified");
        jobs.assignCrew(id, address(0x99));
    }

    function test_crew_cannot_start_unassigned() public {
        uint256 id = jobs.createJob(client1, "Site A", WESJobTicket.ServiceType.Roustabout, "Work", 1000e6);
        vm.prank(crew1);
        vm.expectRevert("Not assigned crew");
        jobs.startJob(id);
    }

    function test_record_compliance() public {
        compliance.recordCompliance(crew1, WESCompliance.ComplianceType.OSHA, block.timestamp, block.timestamp + 365 days, "QmCert");
        assertTrue(compliance.isCompliant(crew1, WESCompliance.ComplianceType.OSHA));
    }

    function test_expired_compliance() public {
        compliance.recordCompliance(crew1, WESCompliance.ComplianceType.CDL, block.timestamp, block.timestamp + 1 days, "QmCert");
        vm.warp(block.timestamp + 2 days);
        assertFalse(compliance.isCompliant(crew1, WESCompliance.ComplianceType.CDL));
    }

    function test_incident_lifecycle() public {
        uint256 id = compliance.reportIncident(crew1, "Near miss", 2, "QmEvidence");
        assertEq(compliance.getIncidentCount(), 1);
        (,,,,,,, bool resolved,) = compliance.incidents(id);
        assertFalse(resolved);
        compliance.resolveIncident(id, "Added safety barrier");
        (,,,,,,, resolved,) = compliance.incidents(id);
        assertTrue(resolved);
    }

    function test_invalid_severity() public {
        vm.expectRevert("Invalid severity");
        compliance.reportIncident(crew1, "Test", 6, "QmHash");
    }

    function test_crew_stats() public {
        uint256 id = jobs.createJob(client1, "Site A", WESJobTicket.ServiceType.Roustabout, "Work", 1000e6);
        jobs.assignCrew(id, crew1);
        vm.prank(crew1); jobs.startJob(id);
        vm.prank(crew1); jobs.completeJob(id, "QmHash");
        (,, bool active, uint256 totalJobs,) = jobs.crews(crew1);
        assertTrue(active);
        assertEq(totalJobs, 1);
    }

    receive() external payable {}
}
