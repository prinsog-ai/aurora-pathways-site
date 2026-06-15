import {
  BigInt,
  Bytes,
  dataSource,
} from "@graphprotocol/graph-ts";
import {
  JobCreated,
  ApplicantAdded,
  FreelancerAccepted,
  MilestoneReleased,
  JobCompleted,
  JobCancelled,
  JobDisputed,
  DisputeVoteCast,
  DisputeResolved,
  FreelancerRated,
  DeadlineRefund,
} from "../generated/TaskEscrowV2/TaskEscrowV2";
import {
  Job,
  Milestone,
  Application,
  Freelancer,
  Dispute,
  DisputeVote,
  PlatformStats,
  DailyStats,
} from "../generated/schema";

// ───────────── Helpers ─────────────

function getOrCreateStats(): PlatformStats {
  let stats = PlatformStats.load("global");
  if (!stats) {
    stats = new PlatformStats("global");
    stats.totalJobs = BigInt.fromI32(0);
    stats.openJobs = BigInt.fromI32(0);
    stats.completedJobs = BigInt.fromI32(0);
    stats.totalVolume = BigInt.fromI32(0);
    stats.totalFees = BigInt.fromI32(0);
    stats.uniqueClients = BigInt.fromI32(0);
    stats.uniqueFreelancers = BigInt.fromI32(0);
    stats.lastUpdated = BigInt.fromI32(0);
  }
  return stats;
}

function getOrCreateDailyStats(timestamp: BigInt): DailyStats {
  // Convert to day string (YYYY-MM-DD)
  let daySec = timestamp.toI32() / 86400;
  let dayId = BigInt.fromI32(daySec).toString();

  let stats = DailyStats.load(dayId);
  if (!stats) {
    stats = new DailyStats(dayId);
    stats.date = BigInt.fromI32(daySec * 86400);
    stats.newJobs = BigInt.fromI32(0);
    stats.completedJobs = BigInt.fromI32(0);
    stats.volume = BigInt.fromI32(0);
    stats.fees = BigInt.fromI32(0);
  }
  return stats;
}

function getOrCreateFreelancer(address: Bytes): Freelancer {
  let f = Freelancer.load(address);
  if (!f) {
    f = new Freelancer(address);
    f.address = address;
    f.completedJobs = BigInt.fromI32(0);
    f.totalRating = BigInt.fromI32(0);
    f.ratingCount = BigInt.fromI32(0);
    f.averageRating = BigInt.fromI32(0);
  }
  return f;
}

function statusToString(status: i32): string {
  if (status == 0) return "Open";
  if (status == 1) return "InProgress";
  if (status == 2) return "Completed";
  if (status == 3) return "Cancelled";
  if (status == 4) return "Disputed";
  return "Open";
}

function milestoneStatusToString(status: i32): string {
  if (status == 0) return "Pending";
  if (status == 1) return "Released";
  if (status == 2) return "Refunded";
  return "Pending";
}

// ───────────── Event Handlers ─────────────

export function handleJobCreated(event: JobCreated): void {
  let jobId = event.params.jobId;
  let job = new Job(
    Bytes.fromHexString(
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    ).concat(Bytes.fromBigInt(jobId))
  );
  job.jobId = jobId;
  job.client = event.params.client;
  job.token = event.transaction.to!;
  job.amount = event.params.amount;
  job.description = event.params.description;
  job.category = event.params.category;
  job.status = "Open";
  job.createdAt = event.params.createdAt;
  job.deadline = event.params.deadline;
  job.milestoneCount = BigInt.fromI32(0);
  job.rated = false;
  job.disputeResolved = false;
  job.createdAtBlock = event.block.number;
  job.createdAtTx = event.transaction.hash;
  job.save();

  // Update platform stats
  let stats = getOrCreateStats();
  stats.totalJobs = stats.totalJobs.plus(BigInt.fromI32(1));
  stats.openJobs = stats.openJobs.plus(BigInt.fromI32(1));
  stats.totalVolume = stats.totalVolume.plus(event.params.amount);
  stats.lastUpdated = event.block.timestamp;
  stats.save();

  // Update daily stats
  let daily = getOrCreateDailyStats(event.block.timestamp);
  daily.newJobs = daily.newJobs.plus(BigInt.fromI32(1));
  daily.volume = daily.volume.plus(event.params.amount);
  daily.save();
}

export function handleApplicantAdded(event: ApplicantAdded): void {
  let appId = event.params.jobId
    .toHexString()
    .concat("-")
    .concat(event.params.applicant.toHexString());
  let app = new Application(Bytes.fromUTF8(appId));
  app.job = Bytes.fromBigInt(event.params.jobId);
  app.applicant = event.params.applicant;
  app.appliedAt = event.block.timestamp;
  app.save();
}

export function handleFreelancerAccepted(event: FreelancerAccepted): void {
  let job = Job.load(
    Bytes.fromHexString(
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    ).concat(Bytes.fromBigInt(event.params.jobId))
  );
  if (!job) return;

  job.freelancer = event.params.freelancer;
  job.status = "InProgress";
  job.save();

  // Update stats
  let stats = getOrCreateStats();
  stats.openJobs = stats.openJobs.minus(BigInt.fromI32(1));
  stats.lastUpdated = event.block.timestamp;
  stats.save();
}

export function handleMilestoneReleased(event: MilestoneReleased): void {
  let msId = event.params.jobId
    .toHexString()
    .concat("-")
    .concat(event.params.milestoneIndex.toString());
  let ms = Milestone.load(Bytes.fromUTF8(msId));
  if (!ms) {
    ms = new Milestone(Bytes.fromUTF8(msId));
    ms.job = Bytes.fromBigInt(event.params.jobId);
    ms.index = event.params.milestoneIndex;
    ms.description = "";
    ms.amount = BigInt.fromI32(0);
  }
  ms.status = "Released";
  ms.releasedAt = event.block.timestamp;
  ms.releasedTo = event.params.freelancer;
  ms.save();

  // Track fees
  let stats = getOrCreateStats();
  stats.totalFees = stats.totalFees.plus(event.params.fee);
  stats.lastUpdated = event.block.timestamp;
  stats.save();

  let daily = getOrCreateDailyStats(event.block.timestamp);
  daily.fees = daily.fees.plus(event.params.fee);
  daily.save();
}

export function handleJobCompleted(event: JobCompleted): void {
  let job = Job.load(
    Bytes.fromHexString(
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    ).concat(Bytes.fromBigInt(event.params.jobId))
  );
  if (!job) return;

  job.status = "Completed";
  job.save();

  let stats = getOrCreateStats();
  stats.openJobs = stats.openJobs.minus(BigInt.fromI32(1));
  stats.completedJobs = stats.completedJobs.plus(BigInt.fromI32(1));
  stats.lastUpdated = event.block.timestamp;
  stats.save();

  let daily = getOrCreateDailyStats(event.block.timestamp);
  daily.completedJobs = daily.completedJobs.plus(BigInt.fromI32(1));
  daily.save();
}

export function handleJobCancelled(event: JobCancelled): void {
  let job = Job.load(
    Bytes.fromHexString(
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    ).concat(Bytes.fromBigInt(event.params.jobId))
  );
  if (!job) return;

  job.status = "Cancelled";
  job.save();

  let stats = getOrCreateStats();
  stats.openJobs = stats.openJobs.minus(BigInt.fromI32(1));
  stats.lastUpdated = event.block.timestamp;
  stats.save();
}

export function handleJobDisputed(event: JobDisputed): void {
  let job = Job.load(
    Bytes.fromHexString(
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    ).concat(Bytes.fromBigInt(event.params.jobId))
  );
  if (!job) return;

  job.status = "Disputed";
  job.save();

  let dispute = new Dispute(Bytes.fromBigInt(event.params.jobId));
  dispute.job = Bytes.fromBigInt(event.params.jobId);
  dispute.disputer = event.params.disputer;
  dispute.status = "Active";
  dispute.votesForFreelancer = BigInt.fromI32(0);
  dispute.votesForClient = BigInt.fromI32(0);
  dispute.save();
}

export function handleDisputeVoteCast(event: DisputeVoteCast): void {
  let voteId = event.params.jobId
    .toHexString()
    .concat("-")
    .concat(event.params.juror.toHexString());
  let vote = new DisputeVote(Bytes.fromUTF8(voteId));
  vote.dispute = Bytes.fromBigInt(event.params.jobId);
  vote.juror = event.params.juror;
  vote.payFreelancer = event.params.payFreelancer;
  vote.votedAt = event.block.timestamp;
  vote.save();

  let dispute = Dispute.load(Bytes.fromBigInt(event.params.jobId));
  if (!dispute) return;

  if (event.params.payFreelancer) {
    dispute.votesForFreelancer = dispute.votesForFreelancer.plus(
      BigInt.fromI32(1)
    );
  } else {
    dispute.votesForClient = dispute.votesForClient.plus(BigInt.fromI32(1));
  }
  dispute.save();
}

export function handleDisputeResolved(event: DisputeResolved): void {
  let dispute = Dispute.load(Bytes.fromBigInt(event.params.jobId));
  if (!dispute) return;

  dispute.status = "Resolved";
  dispute.resolvedAt = event.block.timestamp;
  dispute.payFreelancer = event.params.payFreelancer;
  dispute.save();

  let job = Job.load(
    Bytes.fromHexString(
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    ).concat(Bytes.fromBigInt(event.params.jobId))
  );
  if (job) {
    job.disputeResolved = true;
    if (event.params.payFreelancer) {
      job.status = "Completed";
    } else {
      job.status = "Cancelled";
    }
    job.save();
  }
}

export function handleFreelancerRated(event: FreelancerRated): void {
  let job = Job.load(
    Bytes.fromHexString(
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    ).concat(Bytes.fromBigInt(event.params.jobId))
  );
  if (job) {
    job.rated = true;
    job.save();
  }

  let freelancer = getOrCreateFreelancer(event.params.freelancer);
  freelancer.totalRating = freelancer.totalRating.plus(event.params.rating);
  freelancer.ratingCount = freelancer.ratingCount.plus(BigInt.fromI32(1));
  freelancer.averageRating = freelancer.totalRating
    .times(BigInt.fromI32(100))
    .div(freelancer.ratingCount);
  freelancer.completedJobs = freelancer.completedJobs.plus(BigInt.fromI32(1));
  freelancer.save();
}

export function handleDeadlineRefund(event: DeadlineRefund): void {
  let job = Job.load(
    Bytes.fromHexString(
      "0x0000000000000000000000000000000000000000000000000000000000000000"
    ).concat(Bytes.fromBigInt(event.params.jobId))
  );
  if (job) {
    job.status = "Cancelled";
    job.save();
  }
}
