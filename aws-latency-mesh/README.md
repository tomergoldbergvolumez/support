# Multi-Cloud Full-Mesh Inter-AZ Latency Measurement

This toolkit automates the measurement of network latency between all Availability Zones in AWS and Azure regions using a full-mesh approach.

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
│     AWS       │     │     Azure     │     │   Cloud N     │
│ ┌───┐ ┌───┐  │     │ ┌───┐ ┌───┐  │     │ ┌───┐ ┌───┐  │
│ │AZ1│◄─►│AZ2│  │     │ │Z1 │◄─►│Z2 │  │     │ │AZ1│◄─►│AZ2│  │
│ └─┬─┘ └─┬─┘  │     │ └─┬─┘ └─┬─┘  │     │ └─┬─┘ └─┬─┘  │
│   │  ╲╱  │    │     │   │  ╲╱  │    │     │   │  ╲╱  │    │
│   │  ╱╲  │    │     │   │  ╱╲  │    │     │   │  ╱╲  │    │
│ ┌─┴─┐ ┌─┴─┐  │     │ ┌─┴─┐ ┌─┴─┐  │     │ ┌─┴─┐ ┌─┴─┐  │
│ │AZ3│◄─►│AZ4│  │     │ │Z3 │◄─►│Z4 │  │     │ │AZ3│◄─►│AZ4│  │
│ └───┘ └───┘  │     │ └───┘ └───┘  │     │ └───┘ └───┘  │
└───────────────┘     └───────────────┘     └───────────────┘
```

## Components

1. **Terraform Configuration** (`terraform/`) - Deploys VPC/VNet, subnets, and instances in every AZ
2. **Orchestrator** (`scripts/orchestrate.py`) - Fetches inventory from Terraform, runs measurements, collects results
3. **Report Generator** (`scripts/generate_report.py`) - Aggregates data into a final report

## Quick Start

### AWS Only
```bash
# 1. Deploy infrastructure
cd terraform
terraform init
terraform apply -var="enable_aws=true" -var="aws_key_name=YOUR_KEY" -var="aws_public_key=$(cat ~/.ssh/YOUR_KEY.pub)"

# 2. Run measurements (automatically generates report)
cd ../scripts
./orchestrate.py --ssh-key ~/.ssh/YOUR_KEY.pem

# 3. Clean up
cd ../terraform
terraform destroy -var="enable_aws=true" -var="aws_key_name=YOUR_KEY"
```

### Azure Only
```bash
# 1. Login to Azure
az login

# 2. Deploy infrastructure
cd terraform
terraform init
terraform apply -var="enable_azure=true" -var="azure_ssh_public_key=$(cat ~/.ssh/YOUR_KEY.pub)"

# 3. Run measurements
cd ../scripts
./orchestrate.py --ssh-key ~/.ssh/YOUR_KEY.pem

# 4. Clean up
cd ../terraform
terraform destroy -var="enable_azure=true"
```

### Both Clouds
```bash
# 1. Login to both clouds
az login
aws sso login --profile your-profile

# 2. Deploy infrastructure
cd terraform
terraform init
terraform apply \
  -var="enable_aws=true" \
  -var="enable_azure=true" \
  -var="aws_key_name=YOUR_KEY" \
  -var="aws_public_key=$(cat ~/.ssh/YOUR_KEY.pub)" \
  -var="azure_ssh_public_key=$(cat ~/.ssh/YOUR_KEY.pub)"

# 3. Run measurements
cd ../scripts
./orchestrate.py --ssh-key ~/.ssh/YOUR_KEY.pem

# 4. Clean up
cd ../terraform
terraform destroy \
  -var="enable_aws=true" \
  -var="enable_azure=true" \
  -var="aws_key_name=YOUR_KEY" \
  -var="aws_public_key=$(cat ~/.ssh/YOUR_KEY.pub)" \
  -var="azure_ssh_public_key=$(cat ~/.ssh/YOUR_KEY.pub)"
```

## Terraform Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `enable_aws` | **Yes** | `false` | Enable AWS deployment (set to `true` to deploy) |
| `enable_azure` | **Yes** | `false` | Enable Azure deployment (set to `true` to deploy) |
| `aws_key_name` | If AWS | - | AWS SSH key pair name |
| `aws_public_key` | No | - | SSH public key for AWS (creates key pair if provided) |
| `aws_instance_type` | No | `t3.micro` | AWS EC2 instance type |
| `azure_ssh_public_key` | If Azure | - | SSH public key for Azure VMs |
| `azure_vm_size` | No | `Standard_B2s` | Azure VM size |
| `azure_admin_username` | No | `azureuser` | Azure VM admin username |

## Orchestrator Options

| Option | Env Var | Default | Description |
|--------|---------|---------|-------------|
| `--ssh-key` | `SSH_KEY` | *required* | Path to SSH private key file |
| `--ssh-user` | - | Auto | SSH username (auto-detects per cloud) |
| `--ping-count` | `PING_COUNT` | `100` | Ping packets per measurement |
| `--max-workers` | `PARALLEL_JOBS` | `10` | Max parallel SSH connections |
| `--terraform-dir` | - | `../terraform` | Terraform directory |
| `--output-dir` | - | `../results/<timestamp>` | Output directory |

## Regions Covered

### AWS (17 regions)
- **Americas:** us-east-1, us-east-2, us-west-1, us-west-2, ca-central-1, sa-east-1
- **Europe:** eu-west-1, eu-west-2, eu-west-3, eu-central-1, eu-north-1
- **Asia Pacific:** ap-south-1, ap-northeast-1, ap-northeast-2, ap-northeast-3, ap-southeast-1, ap-southeast-2

### Azure (25 regions with Availability Zones)
- **Americas:** eastus, eastus2, westus2, westus3, centralus, southcentralus, canadacentral, brazilsouth
- **Europe:** uksouth, westeurope, northeurope, francecentral, germanywestcentral, norwayeast, swedencentral, switzerlandnorth
- **Middle East/Africa:** uaenorth, southafricanorth, qatarcentral
- **Asia Pacific:** australiaeast, southeastasia, eastasia, japaneast, koreacentral, centralindia

## Cost Estimate

### AWS
- 2-6 t3.micro instances per region (one per supported AZ)
- ~50-60 instances total across 17 regions
- Running for ~1 hour: approximately $0.50-1.00 USD total

### Azure
- 3 Standard_B2s VMs per region (zones 1, 2, 3)
- ~75 VMs total across 25 regions
- Running for ~1 hour: approximately $3.00-4.00 USD total

### Combined
- Total: ~$4.00-5.00 USD per hour

## Prerequisites

- Terraform >= 1.0
- Python 3.8+
- SSH key pair
- **For AWS:** AWS CLI configured with appropriate permissions
- **For Azure:** Azure CLI installed and logged in (`az login`)

## Cleanup

**Important:** Always destroy the infrastructure when done to avoid ongoing charges.

```bash
cd terraform
# Use the same enable flags as apply
terraform destroy -var="enable_aws=true" -var="enable_azure=true" -var="aws_key_name=YOUR_KEY"
```

## Output

Results are saved to `results/<timestamp>/`:
- `inventory.json` - All deployed instances
- `results.json` - Raw measurement data
- `report.md` - Markdown report with statistics
