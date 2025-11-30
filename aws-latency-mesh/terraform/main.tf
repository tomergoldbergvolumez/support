# main.tf - AWS Full-Mesh Latency Measurement Infrastructure

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Variables
variable "key_name" {
  description = "SSH key pair name (must exist in all regions)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "regions" {
  description = "List of AWS regions to deploy to"
  type        = list(string)
  default = [
    "us-east-1",
    "us-east-2",
    "us-west-1",
    "us-west-2",
    "ca-central-1",
    "eu-west-1",
    "eu-west-2",
    "eu-west-3",
    "eu-central-1",
    "eu-central-2",
    "eu-north-1",
    "eu-south-1",
    "eu-south-2",
    "ap-south-1",
    "ap-south-2",
    "ap-northeast-1",
    "ap-northeast-2",
    "ap-northeast-3",
    "ap-southeast-1",
    "ap-southeast-2",
    "ap-southeast-3",
    "ap-southeast-4",
    "ap-east-1",
    "sa-east-1",
    "me-south-1",
    "me-central-1",
    "af-south-1"
  ]
}

# Local values
locals {
  project_name = "latency-mesh"
  common_tags = {
    Project   = "aws-latency-measurement"
    ManagedBy = "terraform"
  }
}

# Generate provider configurations for each region
# Note: In practice, you'll need to create provider aliases for each region
# This is a template showing the structure

# Default provider (us-east-1)
provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = local.common_tags
  }
}

# Output the regions being used
output "target_regions" {
  value = var.regions
}
