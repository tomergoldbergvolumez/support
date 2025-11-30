#!/bin/bash
# orchestrate_measurements.sh
# Orchestrates full-mesh latency measurements across all AZs in all regions

set -e

# Configuration
RESULTS_DIR="./results/$(date +%Y%m%d_%H%M%S)"
SSH_KEY="${SSH_KEY:-~/.ssh/aws-latency-key.pem}"
SSH_USER="ec2-user"
PING_COUNT=100
PARALLEL_JOBS=10

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Create results directory
mkdir -p "$RESULTS_DIR"
log_info "Results will be saved to: $RESULTS_DIR"

# Get instance inventory from Terraform
log_info "Fetching instance inventory from Terraform..."
cd ../terraform
INVENTORY=$(terraform output -json instances 2>/dev/null || echo "{}")
cd - > /dev/null

if [ "$INVENTORY" == "{}" ]; then
    log_error "No instances found. Run 'terraform apply' first."
    exit 1
fi

# Save inventory
echo "$INVENTORY" > "$RESULTS_DIR/inventory.json"
log_info "Inventory saved to $RESULTS_DIR/inventory.json"

# Parse inventory and create measurement tasks
log_info "Creating measurement tasks..."

# Generate measurement script to run on each instance
cat > "$RESULTS_DIR/run_measurements.sh" << 'MEASUREMENT_SCRIPT'
#!/bin/bash
# This script runs on each EC2 instance
# Arguments: target_ip target_az_id ping_count

TARGET_IP=$1
TARGET_AZ=$2
PING_COUNT=${3:-100}

SOURCE_AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Skip if measuring to self
if [ "$SOURCE_AZ" == "$TARGET_AZ" ]; then
    echo "{\"type\":\"skip\",\"source_az\":\"$SOURCE_AZ\",\"target_az\":\"$TARGET_AZ\",\"reason\":\"same_az\"}"
    exit 0
fi

# Run ping test
PING_OUTPUT=$(ping -c $PING_COUNT -i 0.05 -q $TARGET_IP 2>&1)

# Parse results
if echo "$PING_OUTPUT" | grep -q "rtt"; then
    STATS=$(echo "$PING_OUTPUT" | grep "rtt" | awk -F'=' '{print $2}' | awk -F'/' '{print $1","$2","$3","$4}')
    MIN=$(echo $STATS | cut -d',' -f1 | tr -d ' ')
    AVG=$(echo $STATS | cut -d',' -f2 | tr -d ' ')
    MAX=$(echo $STATS | cut -d',' -f3 | tr -d ' ')
    MDEV=$(echo $STATS | cut -d',' -f4 | tr -d ' ' | tr -d 'ms')
    
    LOSS=$(echo "$PING_OUTPUT" | grep "packet loss" | awk -F',' '{print $3}' | awk '{print $1}' | tr -d '%')
    
    echo "{\"type\":\"result\",\"region\":\"$REGION\",\"source_az\":\"$SOURCE_AZ\",\"target_az\":\"$TARGET_AZ\",\"target_ip\":\"$TARGET_IP\",\"min_ms\":$MIN,\"avg_ms\":$AVG,\"max_ms\":$MAX,\"mdev_ms\":$MDEV,\"packet_loss_pct\":$LOSS,\"ping_count\":$PING_COUNT,\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
else
    echo "{\"type\":\"error\",\"source_az\":\"$SOURCE_AZ\",\"target_az\":\"$TARGET_AZ\",\"error\":\"ping_failed\",\"output\":\"$PING_OUTPUT\"}"
fi
MEASUREMENT_SCRIPT

chmod +x "$RESULTS_DIR/run_measurements.sh"

# Python script to orchestrate measurements
cat > "$RESULTS_DIR/orchestrate.py" << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
"""
Orchestrates full-mesh latency measurements across AWS regions.
"""

import json
import subprocess
import sys
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from itertools import combinations
import argparse

def load_inventory(inventory_file):
    """Load instance inventory from JSON file."""
    with open(inventory_file, 'r') as f:
        return json.load(f)

def run_measurement(source_instance, target_instance, ssh_key, ssh_user, ping_count):
    """Run latency measurement from source to target instance."""
    source_ip = source_instance['public_ip']
    target_ip = target_instance['private_ip']
    source_az = source_instance['az_id']
    target_az = target_instance['az_id']
    region = source_instance['region']
    
    # Skip same-AZ measurements
    if source_az == target_az:
        return {
            'type': 'skip',
            'source_az': source_az,
            'target_az': target_az,
            'reason': 'same_az'
        }
    
    # Build SSH command
    ssh_cmd = [
        'ssh', '-i', ssh_key,
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=/dev/null',
        '-o', 'ConnectTimeout=10',
        '-o', 'LogLevel=ERROR',
        f'{ssh_user}@{source_ip}',
        f'ping -c {ping_count} -i 0.05 -q {target_ip}'
    ]
    
    try:
        result = subprocess.run(ssh_cmd, capture_output=True, text=True, timeout=60)
        output = result.stdout
        
        # Parse ping output
        if 'rtt' in output:
            # Extract stats line: rtt min/avg/max/mdev = 0.123/0.456/0.789/0.012 ms
            for line in output.split('\n'):
                if 'rtt' in line:
                    stats = line.split('=')[1].strip().split('/')
                    min_ms = float(stats[0])
                    avg_ms = float(stats[1])
                    max_ms = float(stats[2])
                    mdev_ms = float(stats[3].replace(' ms', ''))
                    
                    # Extract packet loss
                    loss_pct = 0
                    for line2 in output.split('\n'):
                        if 'packet loss' in line2:
                            loss_pct = float(line2.split(',')[2].split('%')[0].strip())
                    
                    return {
                        'type': 'result',
                        'region': region,
                        'source_az': source_az,
                        'target_az': target_az,
                        'source_ip': source_ip,
                        'target_ip': target_ip,
                        'min_ms': min_ms,
                        'avg_ms': avg_ms,
                        'max_ms': max_ms,
                        'mdev_ms': mdev_ms,
                        'packet_loss_pct': loss_pct,
                        'ping_count': ping_count,
                        'timestamp': datetime.utcnow().isoformat() + 'Z'
                    }
        
        return {
            'type': 'error',
            'source_az': source_az,
            'target_az': target_az,
            'error': 'parse_failed',
            'output': output[:500]
        }
        
    except subprocess.TimeoutExpired:
        return {
            'type': 'error',
            'source_az': source_az,
            'target_az': target_az,
            'error': 'timeout'
        }
    except Exception as e:
        return {
            'type': 'error',
            'source_az': source_az,
            'target_az': target_az,
            'error': str(e)
        }

def run_region_measurements(region, instances, ssh_key, ssh_user, ping_count, max_workers):
    """Run full-mesh measurements for a single region."""
    results = []
    instance_list = list(instances.values())
    
    # Generate all pairs (full mesh)
    pairs = [(a, b) for a in instance_list for b in instance_list if a['az_id'] != b['az_id']]
    
    # Remove duplicate pairs (A->B and B->A, keep only one direction)
    seen = set()
    unique_pairs = []
    for a, b in pairs:
        key = tuple(sorted([a['az_id'], b['az_id']]))
        if key not in seen:
            seen.add(key)
            unique_pairs.append((a, b))
    
    print(f"  Running {len(unique_pairs)} measurements in {region}...")
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(run_measurement, src, dst, ssh_key, ssh_user, ping_count): (src, dst)
            for src, dst in unique_pairs
        }
        
        for future in as_completed(futures):
            result = future.result()
            results.append(result)
            if result['type'] == 'result':
                print(f"    {result['source_az']} -> {result['target_az']}: {result['avg_ms']:.3f}ms")
            elif result['type'] == 'error':
                print(f"    {result['source_az']} -> {result['target_az']}: ERROR - {result.get('error', 'unknown')}")
    
    return results

def main():
    parser = argparse.ArgumentParser(description='Run full-mesh latency measurements')
    parser.add_argument('--inventory', default='inventory.json', help='Path to inventory JSON')
    parser.add_argument('--ssh-key', default=os.path.expanduser('~/.ssh/aws-latency-key.pem'), help='SSH private key')
    parser.add_argument('--ssh-user', default='ec2-user', help='SSH username')
    parser.add_argument('--ping-count', type=int, default=100, help='Number of ping packets')
    parser.add_argument('--max-workers', type=int, default=5, help='Max parallel measurements per region')
    parser.add_argument('--output', default='results.json', help='Output file for results')
    args = parser.parse_args()
    
    print("=" * 60)
    print("AWS Full-Mesh Latency Measurement")
    print("=" * 60)
    
    # Load inventory
    print(f"\nLoading inventory from {args.inventory}...")
    inventory = load_inventory(args.inventory)
    
    # Group instances by region
    regions = {}
    for az_id, instance in inventory.items():
        region = instance['region']
        if region not in regions:
            regions[region] = {}
        regions[region][az_id] = instance
    
    print(f"Found {len(regions)} regions with {len(inventory)} total instances")
    
    # Run measurements for each region
    all_results = []
    for region, instances in sorted(regions.items()):
        print(f"\n[{region}] {len(instances)} AZs")
        results = run_region_measurements(
            region, instances,
            args.ssh_key, args.ssh_user,
            args.ping_count, args.max_workers
        )
        all_results.extend(results)
    
    # Save results
    output_data = {
        'metadata': {
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'ping_count': args.ping_count,
            'total_measurements': len([r for r in all_results if r['type'] == 'result']),
            'total_errors': len([r for r in all_results if r['type'] == 'error']),
            'regions': list(regions.keys())
        },
        'results': all_results
    }
    
    with open(args.output, 'w') as f:
        json.dump(output_data, f, indent=2)
    
    print(f"\n{'=' * 60}")
    print(f"Complete! Results saved to {args.output}")
    print(f"Total measurements: {output_data['metadata']['total_measurements']}")
    print(f"Total errors: {output_data['metadata']['total_errors']}")
    print("=" * 60)

if __name__ == '__main__':
    main()
PYTHON_SCRIPT

chmod +x "$RESULTS_DIR/orchestrate.py"

log_info "Starting measurements..."
python3 "$RESULTS_DIR/orchestrate.py" \
    --inventory "$RESULTS_DIR/inventory.json" \
    --ssh-key "$SSH_KEY" \
    --ping-count $PING_COUNT \
    --max-workers $PARALLEL_JOBS \
    --output "$RESULTS_DIR/results.json"

log_info "Measurements complete!"
log_info "Results saved to: $RESULTS_DIR/results.json"
