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
    lines.append("# AWS Inter-AZ Latency Measurement Report")
    lines.append("")
    lines.append(f"**Generated:** {metadata.get('timestamp', datetime.now().isoformat())}")
    lines.append("")

    # Executive Summary
    lines.append("## Executive Summary")
    lines.append("")

    if results:
        # Calculate statistics
        all_latencies = [(r['region'], r['source_az'], r['target_az'], r['avg_ms']) for r in results]
        all_latencies.sort(key=lambda x: x[3])

        min_result = all_latencies[0]
        max_result = all_latencies[-1]
        avg_latency = sum(r[3] for r in all_latencies) / len(all_latencies)

        lines.append("### Measurement Summary")
        lines.append("")
        lines.append(f"- **Total measurements:** {metadata.get('total_measurements', len(results))}")
        lines.append(f"- **Regions covered:** {len(metadata.get('regions', []))}")
        lines.append(f"- **Ping count per measurement:** {metadata.get('ping_count', 'N/A')}")
        lines.append(f"- **Errors:** {metadata.get('total_errors', 0)}")
        lines.append("")
        lines.append("### Key Findings")
        lines.append("")
        lines.append(f"- **Lowest latency:** {min_result[1]} ↔ {min_result[2]} ({min_result[0]}) = **{min_result[3]:.3f}ms**")
        lines.append(f"- **Highest latency:** {max_result[1]} ↔ {max_result[2]} ({max_result[0]}) = **{max_result[3]:.3f}ms**")
        lines.append(f"- **Average latency:** {avg_latency:.3f}ms")
        lines.append("")
    else:
        lines.append("No measurement results found.")
        lines.append("")

    # Group results by region
    by_region = defaultdict(list)
    for r in results:
        by_region[r['region']].append(r)

    # Per-region results
    lines.append("## Detailed Results by Region")
    lines.append("")

    for region in sorted(by_region.keys()):
        region_results = sorted(by_region[region], key=lambda x: x['avg_ms'])

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

        # Top 10 lowest
        lines.append("### Top 10 Lowest Latency AZ Pairs")
        lines.append("")
        lines.append("| Region | Source AZ | Target AZ | Avg (ms) |")
        lines.append("|--------|-----------|-----------|----------|")
        for region, src, dst, lat in all_latencies[:10]:
            lines.append(f"| {region} | {src} | {dst} | {lat:.3f} |")
        lines.append("")

        # Top 10 highest
        lines.append("### Top 10 Highest Latency AZ Pairs")
        lines.append("")
        lines.append("| Region | Source AZ | Target AZ | Avg (ms) |")
        lines.append("|--------|-----------|-----------|----------|")
        for region, src, dst, lat in all_latencies[-10:][::-1]:
            lines.append(f"| {region} | {src} | {dst} | {lat:.3f} |")
        lines.append("")

        # Per-region summary
        lines.append("### Per-Region Latency Summary")
        lines.append("")
        lines.append("| Region | AZ Pairs | Min (ms) | Avg (ms) | Max (ms) |")
        lines.append("|--------|----------|----------|----------|----------|")
        for region in sorted(by_region.keys()):
            region_results = by_region[region]
            latencies = [r['avg_ms'] for r in region_results]
            lines.append(f"| {region} | {len(region_results)} | {min(latencies):.3f} | {sum(latencies)/len(latencies):.3f} | {max(latencies):.3f} |")
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
    lines.append("- Instance type: t3.micro")
    lines.append("- One instance deployed per AZ")
    lines.append("- Measurements use private IPs within the same region")
    lines.append("- Full mesh: every AZ pair measured")
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
