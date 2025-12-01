# AWS Full-Mesh Inter-AZ Latency Measurement

This toolkit automates the measurement of network latency between all Availability Zones in AWS regions using a full-mesh approach.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Control Machine                         │
│  (runs Terraform, orchestrates tests, collects results)     │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│   Region A    │     │   Region B    │     │   Region N    │
│ ┌───┐ ┌───┐  │     │ ┌───┐ ┌───┐  │     │ ┌───┐ ┌───┐  │
│ │AZ1│◄─►│AZ2│  │     │ │AZ1│◄─►│AZ2│  │     │ │AZ1│◄─►│AZ2│  │
│ └─┬─┘ └─┬─┘  │     │ └─┬─┘ └─┬─┘  │     │ └─┬─┘ └─┬─┘  │
│   │  ╲╱  │    │     │   │  ╲╱  │    │     │   │  ╲╱  │    │
│   │  ╱╲  │    │     │   │  ╱╲  │    │     │   │  ╱╲  │    │
│ ┌─┴─┐ ┌─┴─┐  │     │ ┌─┴─┐ ┌─┴─┐  │     │ ┌─┴─┐ ┌─┴─┐  │
│ │AZ3│◄─►│AZ4│  │     │ │AZ3│◄─►│AZ4│  │     │ │AZ3│◄─►│AZ4│  │
│ └───┘ └───┘  │     │ └───┘ └───┘  │     │ └───┘ └───┘  │
└───────────────┘     └───────────────┘     └───────────────┘
```

## Components

1. **Terraform Configuration** (`terraform/`) - Deploys VPC, subnets, and t3.micro instances in every AZ
2. **Orchestrator** (`scripts/orchestrate.py`) - Fetches inventory from Terraform, runs measurements, collects results
3. **Report Generator** (`scripts/generate_report.py`) - Aggregates data into a final report

## Quick Start

```bash
# 1. Deploy infrastructure
cd terraform
terraform init
terraform apply -var="key_name=YOUR_KEY_PAIR_NAME"

# 2. Run measurements (automatically generates report)
cd ../scripts
./orchestrate.py --ssh-key ~/.ssh/YOUR_KEY.pem

# Results saved to results/<timestamp>/results.json and report.md

# 3. Clean up (IMPORTANT: destroy infrastructure when done!)
cd ../terraform
terraform destroy -var="key_name=YOUR_KEY_PAIR_NAME"
```

## Terraform Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `key_name` | **Yes** | - | AWS EC2 key pair name |
| `public_key` | No | - | SSH public key content (if provided, creates key pair in each region) |
| `instance_type` | No | `t3.micro` | EC2 instance type |

**Key Pair Options:**
- If you have an existing key pair in all 17 regions, just provide `key_name`
- If you want Terraform to create the key pair, provide both `key_name` and `public_key`:
  ```bash
  terraform apply -var="key_name=my-key" -var="public_key=$(cat ~/.ssh/my-key.pub)"
  ```

Example with custom values:
```bash
terraform apply \
  -var="key_name=my-key" \
  -var="instance_type=t3.small"
```

## Orchestrator Options

| Option | Env Var | Default | Description |
|--------|---------|---------|-------------|
| `--ssh-key` | `SSH_KEY` | *required* | Path to SSH private key file |
| `--ssh-user` | `SSH_USER` | `ec2-user` | SSH username |
| `--ping-count` | `PING_COUNT` | `100` | Ping packets per measurement |
| `--max-workers` | `PARALLEL_JOBS` | `10` | Max parallel SSH connections |
| `--terraform-dir` | - | `../terraform` | Terraform directory |
| `--output-dir` | - | `../results/<timestamp>` | Output directory |

```bash
# Using CLI arguments
./orchestrate.py --ssh-key ~/.ssh/mykey.pem --ping-count 50

# Using environment variables
SSH_KEY=~/.ssh/mykey.pem PING_COUNT=50 ./orchestrate.py

# Use existing inventory file (skip Terraform)
./orchestrate.py --ssh-key ~/.ssh/mykey.pem --inventory results/inventory.json
```

## Cleanup

**Important:** Always destroy the infrastructure when done to avoid ongoing charges.

```bash
cd terraform
terraform destroy -var="key_name=YOUR_KEY_PAIR_NAME"
```

## Cost Estimate

- 2-6 t3.micro instances per region (one per supported AZ, varies by region)
- ~50-60 instances total across all 17 regions
- Running for ~1 hour: approximately $0.50-1.00 USD total
- Data transfer: minimal (ping packets only)

## Regions Covered

The tool deploys to 17 AWS regions:
- **Americas:** us-east-1, us-east-2, us-west-1, us-west-2, ca-central-1, sa-east-1
- **Europe:** eu-west-1, eu-west-2, eu-west-3, eu-central-1, eu-north-1
- **Asia Pacific:** ap-south-1, ap-northeast-1, ap-northeast-2, ap-northeast-3, ap-southeast-1, ap-southeast-2

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Python 3.8+
- SSH key pair (either existing in all regions, or provide public key for Terraform to create)
