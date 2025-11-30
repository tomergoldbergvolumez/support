# AWS Full-Mesh Inter-AZ Latency Measurement

This toolkit automates the measurement of network latency between all Availability Zones in all AWS regions using a full-mesh approach.

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

1. **Terraform Configuration** - Deploys t3.micro instances in every AZ of every region
2. **Measurement Script** - Runs on each instance to measure latency to all other instances in the region
3. **Orchestrator** - Coordinates the measurement process and collects results
4. **Report Generator** - Aggregates data into a final report

## Quick Start

```bash
# 1. Initialize and deploy infrastructure
cd terraform
terraform init
terraform apply

# 2. Run measurements
cd ../scripts
./orchestrate_measurements.sh

# 3. Generate report
python3 generate_report.py
```

## Cost Estimate

- ~100 t3.micro instances across all regions
- Running for ~1 hour: approximately $1-2 USD
- Data transfer: minimal (ping packets only)

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Python 3.8+
- SSH key pair for EC2 access
