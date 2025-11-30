# modules/region-mesh/main.tf
# Deploys one EC2 instance per AZ in a region for latency measurement

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "key_name" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "project_name" {
  type    = string
  default = "latency-mesh"
}

# Get available AZs in this region
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Get current region
data "aws_region" "current" {}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC - use default VPC for simplicity
data "aws_vpc" "default" {
  default = true
}

# Security group allowing ICMP and SSH
resource "aws_security_group" "latency_test" {
  name        = "${var.project_name}-sg"
  description = "Security group for latency testing"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ICMP (ping)
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # iperf3 port
  ingress {
    from_port   = 5201
    to_port     = 5201
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # qperf ports
  ingress {
    from_port   = 19765
    to_port     = 19766
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# User data script to install measurement tools
locals {
  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y iperf3 qperf bind-utils jq

    # Create measurement script
    cat > /home/ec2-user/measure_latency.sh << 'SCRIPT'
    #!/bin/bash
    TARGET_IP=$1
    TARGET_AZ=$2
    SOURCE_AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone-id)
    
    # Run ping test (100 packets)
    PING_RESULT=$(ping -c 100 -i 0.1 $TARGET_IP 2>/dev/null | tail -1)
    
    # Parse results: rtt min/avg/max/mdev = 0.123/0.456/0.789/0.012 ms
    if [[ $PING_RESULT =~ ([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+) ]]; then
        MIN=${BASH_REMATCH[1]}
        AVG=${BASH_REMATCH[2]}
        MAX=${BASH_REMATCH[3]}
        MDEV=${BASH_REMATCH[4]}
    else
        MIN="N/A"
        AVG="N/A"
        MAX="N/A"
        MDEV="N/A"
    fi
    
    # Output JSON
    echo "{\"source_az\":\"$SOURCE_AZ\",\"target_az\":\"$TARGET_AZ\",\"target_ip\":\"$TARGET_IP\",\"min_ms\":\"$MIN\",\"avg_ms\":\"$AVG\",\"max_ms\":\"$MAX\",\"mdev_ms\":\"$MDEV\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
    SCRIPT
    chmod +x /home/ec2-user/measure_latency.sh
    chown ec2-user:ec2-user /home/ec2-user/measure_latency.sh
  EOF
}

# Deploy one instance per AZ
resource "aws_instance" "latency_node" {
  for_each = toset(data.aws_availability_zones.available.zone_ids)

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.latency_test.id]
  availability_zone      = [for az in data.aws_availability_zones.available.names : az if data.aws_availability_zones.available.zone_ids[index(data.aws_availability_zones.available.names, az)] == each.key][0]
  
  user_data = local.user_data

  tags = {
    Name   = "${var.project_name}-${each.key}"
    AZ_ID  = each.key
    Region = data.aws_region.current.name
  }
}

# Outputs
output "instances" {
  value = {
    for az_id, instance in aws_instance.latency_node : az_id => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
      az_id       = az_id
      az_name     = instance.availability_zone
      region      = data.aws_region.current.name
    }
  }
}

output "region" {
  value = data.aws_region.current.name
}

output "az_count" {
  value = length(data.aws_availability_zones.available.zone_ids)
}
