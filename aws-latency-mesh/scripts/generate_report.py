#!/usr/bin/env python3
"""
Generate report from latency measurement results.
Outputs markdown report (no external dependencies).
"""

import json
import sys
from datetime import datetime
from collections import defaultdict
from pathlib import Path
import argparse


def load_results(results_file):
    """Load measurement results from JSON file."""
    with open(results_file, 'r') as f:
        return json.load(f)


def generate_report(results_data, output_file, verbose=False):
    """Generate markdown report from results."""

    lines = []

    # Extract metadata and results
    metadata = results_data.get('metadata', {})
    results = [r for r in results_data.get('results', []) if r.get('type') == 'result']

    # Title
    lines.append("# Multi-Cloud Inter-AZ Latency Measurement Report")
    lines.append("")
    lines.append(f"**Generated:** {metadata.get('timestamp', datetime.now().isoformat())}")
    lines.append("")

    # Executive Summary
    lines.append("## Executive Summary")
    lines.append("")

    if results:
        # Calculate statistics
        all_latencies = [(r.get('cloud', 'aws'), r['region'], r['source_az'], r['target_az'], r['avg_ms']) for r in results]
        all_latencies.sort(key=lambda x: x[4])

        min_result = all_latencies[0]
        max_result = all_latencies[-1]
        avg_latency = sum(r[4] for r in all_latencies) / len(all_latencies)

        # Get clouds
        clouds = metadata.get('clouds', list(set(r.get('cloud', 'aws') for r in results)))

        lines.append("### Measurement Summary")
        lines.append("")
        lines.append(f"- **Total measurements:** {metadata.get('total_measurements', len(results))}")
        lines.append(f"- **Clouds:** {', '.join(c.upper() for c in sorted(clouds))}")

        # Count regions per cloud
        regions_meta = metadata.get('regions', {})
        if isinstance(regions_meta, dict):
            for cloud in sorted(regions_meta.keys()):
                lines.append(f"- **{cloud.upper()} regions:** {len(regions_meta[cloud])}")

        lines.append(f"- **Ping count per measurement:** {metadata.get('ping_count', 'N/A')}")
        lines.append(f"- **Errors:** {metadata.get('total_errors', 0)}")
        lines.append("")
        lines.append("### Key Findings")
        lines.append("")
        lines.append(f"- **Lowest latency:** {min_result[2]} -> {min_result[3]} ({min_result[0].upper()}/{min_result[1]}) = **{min_result[4]:.3f}ms**")
        lines.append(f"- **Highest latency:** {max_result[2]} -> {max_result[3]} ({max_result[0].upper()}/{max_result[1]}) = **{max_result[4]:.3f}ms**")
        lines.append(f"- **Average latency:** {avg_latency:.3f}ms")
        lines.append("")
    else:
        lines.append("No measurement results found.")
        lines.append("")

    # Group results by cloud, then by region
    by_cloud = defaultdict(lambda: defaultdict(list))
    for r in results:
        cloud = r.get('cloud', 'aws')
        by_cloud[cloud][r['region']].append(r)

    # Per-cloud, per-region results
    for cloud in sorted(by_cloud.keys()):
        lines.append(f"## {cloud.upper()} Results")
        lines.append("")

        for region in sorted(by_cloud[cloud].keys()):
            region_results = sorted(by_cloud[cloud][region], key=lambda x: x['avg_ms'])

            lines.append(f"### {region}")
            lines.append("")
            lines.append("| Source AZ | Target AZ | Min (ms) | Avg (ms) | Max (ms) | StdDev |")
            lines.append("|-----------|-----------|----------|----------|----------|--------|")

            for r in region_results:
                lines.append(f"| {r['source_az']} | {r['target_az']} | {r['min_ms']:.3f} | {r['avg_ms']:.3f} | {r['max_ms']:.3f} | {r.get('mdev_ms', 0):.3f} |")

            lines.append("")

    # Summary statistics
    if results:
        lines.append("## Summary Statistics")
        lines.append("")

        # Top 10 lowest across all clouds
        lines.append("### Top 10 Lowest Latency AZ Pairs (All Clouds)")
        lines.append("")
        lines.append("| Cloud | Region | Source AZ | Target AZ | Avg (ms) |")
        lines.append("|-------|--------|-----------|-----------|----------|")
        for cloud, region, src, dst, lat in all_latencies[:10]:
            lines.append(f"| {cloud.upper()} | {region} | {src} | {dst} | {lat:.3f} |")
        lines.append("")

        # Top 10 highest across all clouds
        lines.append("### Top 10 Highest Latency AZ Pairs (All Clouds)")
        lines.append("")
        lines.append("| Cloud | Region | Source AZ | Target AZ | Avg (ms) |")
        lines.append("|-------|--------|-----------|-----------|----------|")
        for cloud, region, src, dst, lat in all_latencies[-10:][::-1]:
            lines.append(f"| {cloud.upper()} | {region} | {src} | {dst} | {lat:.3f} |")
        lines.append("")

        # Per-cloud summary
        lines.append("### Per-Cloud Latency Summary")
        lines.append("")
        lines.append("| Cloud | Regions | AZ Pairs | Min (ms) | Avg (ms) | Max (ms) |")
        lines.append("|-------|---------|----------|----------|----------|----------|")
        for cloud in sorted(by_cloud.keys()):
            cloud_results = [r for r in results if r.get('cloud', 'aws') == cloud]
            latencies = [r['avg_ms'] for r in cloud_results]
            num_regions = len(by_cloud[cloud])
            lines.append(f"| {cloud.upper()} | {num_regions} | {len(cloud_results)} | {min(latencies):.3f} | {sum(latencies)/len(latencies):.3f} | {max(latencies):.3f} |")
        lines.append("")

        # Per-region summary
        lines.append("### Per-Region Latency Summary")
        lines.append("")
        lines.append("| Cloud | Region | AZ Pairs | Min (ms) | Avg (ms) | Max (ms) |")
        lines.append("|-------|--------|----------|----------|----------|----------|")
        for cloud in sorted(by_cloud.keys()):
            for region in sorted(by_cloud[cloud].keys()):
                region_results = by_cloud[cloud][region]
                latencies = [r['avg_ms'] for r in region_results]
                lines.append(f"| {cloud.upper()} | {region} | {len(region_results)} | {min(latencies):.3f} | {sum(latencies)/len(latencies):.3f} | {max(latencies):.3f} |")
        lines.append("")

    # Methodology
    lines.append("## Methodology")
    lines.append("")
    lines.append("**Measurement Method:**")
    lines.append("- Tool: ICMP ping")
    lines.append("- Interval: 200ms between packets")
    lines.append("- Metric: Round-trip time (RTT) in milliseconds")
    lines.append("- Statistics: min/avg/max/mdev calculated by ping")
    lines.append("")
    lines.append("**Infrastructure:**")
    lines.append("- AWS: t3.micro instances")
    lines.append("- Azure: Standard_B2s VMs")
    lines.append("- One instance deployed per availability zone")
    lines.append("- Measurements use private IPs within the same region")
    lines.append("- Full mesh: every AZ pair measured bidirectionally")
    lines.append("")

    # Write output
    report_content = '\n'.join(lines)
    with open(output_file, 'w') as f:
        f.write(report_content)

    if verbose:
        print(f"Report generated: {output_file}")
        print("\n" + "="*60)
        print(report_content)


def main():
    parser = argparse.ArgumentParser(description='Generate report from latency results')
    parser.add_argument('input', nargs='?', default='results.json', help='Input results JSON file')
    parser.add_argument('--output', '-o', help='Output markdown file (default: report.md in same dir as input)')
    args = parser.parse_args()

    input_path = Path(args.input)
    if args.output:
        output_path = Path(args.output)
    else:
        output_path = input_path.parent / 'report.md'

    print(f"Loading results from {input_path}...")
    results_data = load_results(input_path)

    print(f"Generating report...")
    generate_report(results_data, output_path, verbose=True)


if __name__ == '__main__':
    main()
