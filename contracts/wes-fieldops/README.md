# WES Field Operations — Smart Contract System

Williams Engineering Services (WES) field operations management on Polygon.

## Contracts

| Contract | Description |
|----------|-------------|
| **TechnicianRegistry** | Register, certify, and rate field technicians with auto-tier upgrades |
| **WorkOrderManager** | Create work orders with USDC escrow, assignment, completion, and payment release |
| **EquipmentManager** | Track field equipment inventory, assignment, maintenance schedules |
| **ServiceLevelAgreement** | Enforce response/completion SLAs with penalty/bonus mechanics |

## Architecture

```
Client → WorkOrderManager (create + escrow USDC)
              ↓
Admin → assignTechnician → TechnicianRegistry (verify certified + active)
              ↓
Technician → startWork → completeWork
              ↓
Client → verifyWorkOrder → Payment released (minus 5% platform fee)
```

## Work Order Lifecycle

`Pending` → `Assigned` → `InProgress` → `Completed` → `Verified` (payment released)

With dispute path: `Completed` → `Disputed` → Admin resolves → `Verified` or `Cancelled`

## Technician Tiers

| Tier | Requirements |
|------|-------------|
| Bronze | Newly registered |
| Silver | 10+ jobs, 4.0+ avg rating |
| Gold | 50+ jobs, 4.5+ avg rating |
| Platinum | 100+ jobs, 4.8+ avg rating |

## Deployment

```bash
# Set env vars
export POLYGON_RPC_URL="https://polygon-rpc.com"
export PRIVATE_KEY="0x..."
export TREASURY_ADDRESS="0x..."
export USDC_ADDRESS="0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359"

# Deploy to Polygon
forge script script/DeployPolygon.s.sol:DeployWES --rpc-url $POLYGON_RPC_URL --broadcast --verify

# Run tests
forge test -vvv
```

## Platform Fee

5% (500 basis points) — configurable by admin, max 15%.
