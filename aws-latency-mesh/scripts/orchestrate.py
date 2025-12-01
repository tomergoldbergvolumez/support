#!/usr/bin/env python3
"""
Orchestrates full-mesh latency measurements across AWS and Azure regions.

Usage:
    ./orchestrate.py                          # Uses Terraform in ../terraform
    ./orchestrate.py --terraform-dir /path    # Custom Terraform directory
    ./orchestrate.py --inventory inv.json     # Use existing inventory file

Environment variables:
    SSH_KEY       - Path to SSH private key (required if --ssh-key not provided)
    PING_COUNT    - Number of ping packets per measurement (default: 100)
    PARALLEL_JOBS - Max parallel SSH connections (default: 10)
"""

import json
import subprocess
import os
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
import argparse

# Default SSH users per cloud
DEFAULT_SSH_USERS = {
    'aws': 'ec2-user',
    'azure': 'azureuser'
}


def get_terraform_inventory(terraform_dir):
    """Fetch instance inventory from Terraform output."""
    try:
        result = subprocess.run(
            ['terraform', f'-chdir={terraform_dir}', 'output', '-json', 'instances'],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            return None
        return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
        return None


def load_inventory(inventory_file):
    """Load instance inventory from JSON file."""
    with open(inventory_file, 'r') as f:
        return json.load(f)


def get_ssh_user(instance, override_user=None):
    """Get SSH user for an instance based on cloud type."""
    if override_user:
        return override_user
    cloud = instance.get('cloud', 'aws')
    return DEFAULT_SSH_USERS.get(cloud, 'ec2-user')


def run_measurement(source_instance, target_instance, ssh_key, ssh_user_override, ping_count):
    """Run latency measurement from source to target instance."""
    source_ip = source_instance['public_ip']
    target_ip = target_instance['private_ip']
    source_az = source_instance['az_id']
    target_az = target_instance['az_id']
    region = source_instance['region']
    cloud = source_instance.get('cloud', 'aws')

    # Skip same-AZ measurements
    if source_az == target_az:
        return {
            'type': 'skip',
            'cloud': cloud,
            'source_az': source_az,
            'target_az': target_az,
            'reason': 'same_az'
        }

    # Get SSH user for this instance
    ssh_user = get_ssh_user(source_instance, ssh_user_override)

    # Build SSH command
    ssh_cmd = [
        'ssh', '-i', ssh_key,
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=/dev/null',
        '-o', 'ConnectTimeout=10',
        '-o', 'LogLevel=ERROR',
        f'{ssh_user}@{source_ip}',
        f'ping -c {ping_count} -i 0.2 -q {target_ip}'
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
                        'cloud': cloud,
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
                        'timestamp': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
                    }

        return {
            'type': 'error',
            'cloud': cloud,
            'source_az': source_az,
            'target_az': target_az,
            'error': 'parse_failed',
            'output': output[:500]
        }

    except subprocess.TimeoutExpired:
        return {
            'type': 'error',
            'cloud': cloud,
            'source_az': source_az,
            'target_az': target_az,
            'error': 'timeout'
        }
    except Exception as e:
        return {
            'type': 'error',
            'cloud': cloud,
            'source_az': source_az,
            'target_az': target_az,
            'error': str(e)
        }


def run_region_measurements(cloud, region, instances, ssh_key, ssh_user, ping_count, max_workers):
    """Run full-mesh measurements for a single region."""
    results = []
    instance_list = list(instances.values())

    # Generate all pairs (full mesh, bidirectional)
    pairs = [(a, b) for a in instance_list for b in instance_list if a['az_id'] != b['az_id']]

    print(f"  Running {len(pairs)} measurements in {cloud}/{region}...")

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(run_measurement, src, dst, ssh_key, ssh_user, ping_count): (src, dst)
            for src, dst in pairs
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
    script_dir = Path(__file__).parent.resolve()
    default_terraform_dir = script_dir.parent / 'terraform'
    default_results_dir = script_dir.parent / 'results' / datetime.now().strftime('%Y%m%d_%H%M%S')

    parser = argparse.ArgumentParser(
        description='Run full-mesh latency measurements across AWS and Azure AZs',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('--inventory', help='Path to inventory JSON (skips Terraform)')
    parser.add_argument('--terraform-dir', default=str(default_terraform_dir),
                        help=f'Terraform directory (default: {default_terraform_dir})')
    parser.add_argument('--output-dir', default=str(default_results_dir),
                        help='Output directory for results')
    parser.add_argument('--ssh-key', default=os.environ.get('SSH_KEY'),
                        required='SSH_KEY' not in os.environ,
                        help='SSH private key (required, or set SSH_KEY env var)')
    parser.add_argument('--ssh-user', default=None,
                        help='SSH username override (default: auto-detect per cloud)')
    parser.add_argument('--ping-count', type=int, default=int(os.environ.get('PING_COUNT', '100')),
                        help='Number of ping packets')
    parser.add_argument('--max-workers', type=int, default=int(os.environ.get('PARALLEL_JOBS', '10')),
                        help='Max parallel measurements per region')
    args = parser.parse_args()

    print("=" * 60)
    print("Multi-Cloud Full-Mesh Latency Measurement")
    print("=" * 60)

    # Get inventory
    if args.inventory:
        print(f"\nLoading inventory from {args.inventory}...")
        inventory = load_inventory(args.inventory)
    else:
        print(f"\nFetching inventory from Terraform ({args.terraform_dir})...")
        inventory = get_terraform_inventory(args.terraform_dir)
        if not inventory:
            print("ERROR: No instances found. Run 'terraform apply' first.", file=sys.stderr)
            sys.exit(1)

    # Create output directory and save inventory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    inventory_file = output_dir / 'inventory.json'
    with open(inventory_file, 'w') as f:
        json.dump(inventory, f, indent=2)
    print(f"Inventory saved to {inventory_file}")

    # Group instances by cloud, then by region
    clouds = {}
    for az_id, instance in inventory.items():
        cloud = instance.get('cloud', 'aws')
        region = instance['region']
        if cloud not in clouds:
            clouds[cloud] = {}
        if region not in clouds[cloud]:
            clouds[cloud][region] = {}
        clouds[cloud][region][az_id] = instance

    # Count totals
    total_instances = len(inventory)
    total_regions = sum(len(regions) for regions in clouds.values())
    print(f"Found {len(clouds)} clouds, {total_regions} regions, {total_instances} total instances")

    for cloud, regions in sorted(clouds.items()):
        print(f"  {cloud.upper()}: {len(regions)} regions, {sum(len(r) for r in regions.values())} instances")

    # Run measurements for each cloud/region
    all_results = []
    for cloud in sorted(clouds.keys()):
        print(f"\n{'='*60}")
        print(f"[{cloud.upper()}]")
        print("=" * 60)

        for region, instances in sorted(clouds[cloud].items()):
            print(f"\n[{cloud}/{region}] {len(instances)} AZs")
            results = run_region_measurements(
                cloud, region, instances,
                args.ssh_key, args.ssh_user,
                args.ping_count, args.max_workers
            )
            all_results.extend(results)

    # Save results
    output_data = {
        'metadata': {
            'timestamp': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
            'ping_count': args.ping_count,
            'total_measurements': len([r for r in all_results if r['type'] == 'result']),
            'total_errors': len([r for r in all_results if r['type'] == 'error']),
            'clouds': list(clouds.keys()),
            'regions': {cloud: list(regions.keys()) for cloud, regions in clouds.items()}
        },
        'results': all_results
    }

    results_file = output_dir / 'results.json'
    with open(results_file, 'w') as f:
        json.dump(output_data, f, indent=2)

    # Generate markdown report
    report_file = output_dir / 'report.md'
    from generate_report import generate_report
    generate_report(output_data, report_file, inventory=inventory)

    print(f"\n{'=' * 60}")
    print(f"Complete!")
    print(f"Results: {results_file}")
    print(f"Report:  {report_file}")
    print(f"Total measurements: {output_data['metadata']['total_measurements']}")
    print(f"Total errors: {output_data['metadata']['total_errors']}")
    print("=" * 60)


if __name__ == '__main__':
    main()
