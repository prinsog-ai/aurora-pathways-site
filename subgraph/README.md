# Aurora Pathways — The Graph Subgraph

Indexes all TaskEscrowV2 events on Polygon mainnet for fast, efficient frontend queries.

## What It Indexes

- **Jobs** — created, accepted, completed, cancelled, disputed
- **Milestones** — status tracking, release events, fees
- **Applications** — who applied to which job
- **Freelancers** — reputation, ratings, completed jobs
- **Disputes** — votes, resolution outcomes
- **Platform Stats** — total jobs, volume, fees (global + daily)

## Setup

```bash
npm install
npm run codegen    # Generate types from ABI + schema
npm run build      # Compile mappings
```

## Deploy

### The Graph Studio (recommended for production)
```bash
npm run deploy:studio
```
Requires: `graph auth --studio <DEPLOY_KEY>` (get from [The Graph Studio](https://thegraph.com/studio/))

### Hosted Service (legacy)
```bash
npm run deploy
```

### Local Development
```bash
# Start local Graph Node (Docker required)
docker-compose up -d

# Create & deploy locally
npm run create-local
npm run deploy-local
```

## Query Examples

### Get all open jobs
```graphql
{
  jobs(where: { status: Open }, orderBy: createdAt, orderDirection: desc) {
    id
    jobId
    client
    freelancer
    amount
    description
    category
    createdAt
    deadline
    milestoneCount
  }
}
```

### Get platform stats
```graphql
{
  platformStats(id: "global") {
    totalJobs
    openJobs
    completedJobs
    totalVolume
    totalFees
    uniqueClients
    uniqueFreelancers
  }
}
```

### Get freelancer reputation
```graphql
{
  freelancer(id: "0x...") {
    address
    completedJobs
    averageRating
    jobs(orderBy: createdAt, orderDirection: desc, first: 10) {
      description
      status
      amount
    }
  }
}
```

### Get daily volume
```graphql
{
  dailyStats(orderBy: date, orderDirection: desc, first: 30) {
    date
    newJobs
    completedJobs
    volume
    fees
  }
}
```

### Get dispute details
```graphql
{
  dispute(id: "0x...") {
    disputer
    status
    votesForFreelancer
    votesForClient
    votes {
      juror
      payFreelancer
      votedAt
    }
  }
}
```

## Integration with Frontend

```javascript
import { createClient } from 'urql';

const client = createClient({
  url: 'https://api.thegraph.com/subgraphs/name/aurora-pathways/tasklync'
});

// Fetch open jobs
const OPEN_JOBS = `
  query {
    jobs(where: { status: Open }, first: 20, orderBy: createdAt, orderDirection: desc) {
      jobId
      client
      amount
      description
      category
      createdAt
      deadline
    }
  }
`;

const result = await client.query(OPEN_JOBS).toPromise();
```

## Schema Entities

| Entity | Description |
|--------|-------------|
| `Job` | Full job lifecycle (create → complete/cancel/dispute) |
| `Milestone` | Individual milestone within a job |
| `Application` | Freelancer application to a job |
| `Freelancer` | Aggregated reputation & rating data |
| `Dispute` | Dispute with vote tallies |
| `DisputeVote` | Individual juror vote |
| `PlatformStats` | Global platform metrics |
| `DailyStats` | Per-day aggregated metrics |
