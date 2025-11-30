#!/usr/bin/env python3
"""
Generate PDF report from latency measurement results.
"""

import json
import sys
from datetime import datetime
from collections import defaultdict

try:
    from reportlab.lib.pagesizes import letter
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib import colors
    from reportlab.lib.units import inch
except ImportError:
    print("Installing reportlab...")
    import subprocess
    subprocess.run([sys.executable, '-m', 'pip', 'install', 'reportlab', '-q'])
    from reportlab.lib.pagesizes import letter
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib import colors
    from reportlab.lib.units import inch

def load_results(results_file):
    """Load measurement results from JSON file."""
    with open(results_file, 'r') as f:
        return json.load(f)

def generate_report(results_data, output_file):
    """Generate PDF report from results."""
    
    doc = SimpleDocTemplate(output_file, pagesize=letter,
                            topMargin=0.75*inch, bottomMargin=0.75*inch,
                            leftMargin=0.75*inch, rightMargin=0.75*inch)
    
    styles = getSampleStyleSheet()
    story = []
    
    # Custom styles
    title_style = ParagraphStyle('CustomTitle', parent=styles['Title'], fontSize=24, spaceAfter=30)
    heading_style = ParagraphStyle('CustomHeading', parent=styles['Heading1'], fontSize=14, 
                                   spaceAfter=12, spaceBefore=20, textColor=colors.HexColor('#232F3E'))
    subheading_style = ParagraphStyle('CustomSubHeading', parent=styles['Heading2'], fontSize=12,
                                      spaceAfter=8, spaceBefore=12, textColor=colors.HexColor('#FF9900'))
    normal_style = ParagraphStyle('CustomNormal', parent=styles['Normal'], fontSize=10, spaceAfter=8)
    
    # Table style
    table_style = TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#232F3E')),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 10),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 8),
        ('TOPPADDING', (0, 0), (-1, 0), 8),
        ('BACKGROUND', (0, 1), (-1, -1), colors.HexColor('#FAFAFA')),
        ('TEXTCOLOR', (0, 1), (-1, -1), colors.black),
        ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
        ('FONTSIZE', (0, 1), (-1, -1), 9),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.grey),
        ('BOTTOMPADDING', (0, 1), (-1, -1), 6),
        ('TOPPADDING', (0, 1), (-1, -1), 6),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F5F5F5')]),
    ])
    
    # Extract metadata and results
    metadata = results_data.get('metadata', {})
    results = [r for r in results_data.get('results', []) if r.get('type') == 'result']
    
    # Title
    story.append(Paragraph("AWS Inter-AZ Latency Measurement Report", title_style))
    story.append(Paragraph(f"Generated: {metadata.get('timestamp', datetime.now().isoformat())}", normal_style))
    story.append(Spacer(1, 20))
    
    # Executive Summary
    story.append(Paragraph("Executive Summary", heading_style))
    
    if results:
        # Calculate statistics
        all_latencies = [(r['region'], r['source_az'], r['target_az'], r['avg_ms']) for r in results]
        all_latencies.sort(key=lambda x: x[3])
        
        min_result = all_latencies[0]
        max_result = all_latencies[-1]
        avg_latency = sum(r[3] for r in all_latencies) / len(all_latencies)
        
        summary_text = f"""
        <b>Measurement Summary:</b><br/>
        • Total measurements: {metadata.get('total_measurements', len(results))}<br/>
        • Regions covered: {len(metadata.get('regions', []))}<br/>
        • Ping count per measurement: {metadata.get('ping_count', 'N/A')}<br/>
        • Errors: {metadata.get('total_errors', 0)}<br/><br/>
        <b>Key Findings:</b><br/>
        • Lowest latency: {min_result[1]} ↔ {min_result[2]} ({min_result[0]}) = {min_result[3]:.3f}ms<br/>
        • Highest latency: {max_result[1]} ↔ {max_result[2]} ({max_result[0]}) = {max_result[3]:.3f}ms<br/>
        • Average latency across all AZ pairs: {avg_latency:.3f}ms
        """
    else:
        summary_text = "No measurement results found."
    
    story.append(Paragraph(summary_text, normal_style))
    story.append(PageBreak())
    
    # Group results by region
    by_region = defaultdict(list)
    for r in results:
        by_region[r['region']].append(r)
    
    # Per-region results
    story.append(Paragraph("Detailed Results by Region", heading_style))
    
    region_count = 0
    for region in sorted(by_region.keys()):
        region_results = sorted(by_region[region], key=lambda x: x['avg_ms'])
        
        story.append(Paragraph(f"{region}", subheading_style))
        
        # Create table
        table_data = [["Source AZ", "Target AZ", "Min (ms)", "Avg (ms)", "Max (ms)", "StdDev"]]
        for r in region_results:
            table_data.append([
                r['source_az'],
                r['target_az'],
                f"{r['min_ms']:.3f}",
                f"{r['avg_ms']:.3f}",
                f"{r['max_ms']:.3f}",
                f"{r.get('mdev_ms', 0):.3f}"
            ])
        
        col_widths = [1.2*inch, 1.2*inch, 0.8*inch, 0.8*inch, 0.8*inch, 0.8*inch]
        table = Table(table_data, colWidths=col_widths)
        table.setStyle(table_style)
        story.append(table)
        story.append(Spacer(1, 15))
        
        region_count += 1
        if region_count % 4 == 0:
            story.append(PageBreak())
    
    # Summary statistics page
    story.append(PageBreak())
    story.append(Paragraph("Summary Statistics", heading_style))
    
    if results:
        # Top 10 lowest
        story.append(Paragraph("Top 10 Lowest Latency AZ Pairs", subheading_style))
        low_table_data = [["Region", "Source AZ", "Target AZ", "Avg (ms)"]]
        for region, src, dst, lat in all_latencies[:10]:
            low_table_data.append([region, src, dst, f"{lat:.3f}"])
        
        low_table = Table(low_table_data, colWidths=[1.5*inch, 1.3*inch, 1.3*inch, 0.8*inch])
        low_table.setStyle(table_style)
        story.append(low_table)
        story.append(Spacer(1, 20))
        
        # Top 10 highest
        story.append(Paragraph("Top 10 Highest Latency AZ Pairs", subheading_style))
        high_table_data = [["Region", "Source AZ", "Target AZ", "Avg (ms)"]]
        for region, src, dst, lat in all_latencies[-10:][::-1]:
            high_table_data.append([region, src, dst, f"{lat:.3f}"])
        
        high_table = Table(high_table_data, colWidths=[1.5*inch, 1.3*inch, 1.3*inch, 0.8*inch])
        high_table.setStyle(table_style)
        story.append(high_table)
        
        # Per-region summary
        story.append(PageBreak())
        story.append(Paragraph("Per-Region Latency Summary", subheading_style))
        
        region_summary_data = [["Region", "AZ Pairs", "Min (ms)", "Avg (ms)", "Max (ms)"]]
        for region in sorted(by_region.keys()):
            region_results = by_region[region]
            latencies = [r['avg_ms'] for r in region_results]
            region_summary_data.append([
                region,
                str(len(region_results)),
                f"{min(latencies):.3f}",
                f"{sum(latencies)/len(latencies):.3f}",
                f"{max(latencies):.3f}"
            ])
        
        region_table = Table(region_summary_data, colWidths=[1.5*inch, 0.8*inch, 0.8*inch, 0.8*inch, 0.8*inch])
        region_table.setStyle(table_style)
        story.append(region_table)
    
    # Methodology
    story.append(Spacer(1, 30))
    story.append(Paragraph("Methodology", heading_style))
    methodology_text = """
    <b>Measurement Method:</b><br/>
    • Tool: ICMP ping with 100 packets per measurement<br/>
    • Interval: 50ms between packets<br/>
    • Metric: Round-trip time (RTT) in milliseconds<br/>
    • Statistics: min/avg/max/mdev calculated by ping<br/><br/>
    <b>Infrastructure:</b><br/>
    • Instance type: t3.micro<br/>
    • One instance deployed per AZ<br/>
    • Measurements use private IPs within the same region<br/>
    • Full mesh: every AZ pair measured bidirectionally
    """
    story.append(Paragraph(methodology_text, normal_style))
    
    # Build PDF
    doc.build(story)
    print(f"Report generated: {output_file}")

def main():
    import argparse
    parser = argparse.ArgumentParser(description='Generate PDF report from latency results')
    parser.add_argument('--input', default='results.json', help='Input results JSON file')
    parser.add_argument('--output', default='latency_report.pdf', help='Output PDF file')
    args = parser.parse_args()
    
    print(f"Loading results from {args.input}...")
    results_data = load_results(args.input)
    
    print(f"Generating report...")
    generate_report(results_data, args.output)

if __name__ == '__main__':
    main()
