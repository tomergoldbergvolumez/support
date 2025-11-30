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

variable "public_key" {
  description = "SSH public key (if provided, creates key pair in each region)"
  type        = string
  default     = ""
}

# Local values
locals {
  project_name = "latency-mesh"
  common_tags = {
    Project   = "aws-latency-measurement"
    ManagedBy = "terraform"
  }
}

# =============================================================================
# Provider configurations for each region
# =============================================================================

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "us-east-2"
  region = "us-east-2"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "us-west-1"
  region = "us-west-1"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "us-west-2"
  region = "us-west-2"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "ca-central-1"
  region = "ca-central-1"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "eu-west-1"
  region = "eu-west-1"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "eu-west-2"
  region = "eu-west-2"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "eu-west-3"
  region = "eu-west-3"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "eu-central-1"
  region = "eu-central-1"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "eu-north-1"
  region = "eu-north-1"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "ap-south-1"
  region = "ap-south-1"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "ap-northeast-1"
  region = "ap-northeast-1"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "ap-northeast-2"
  region = "ap-northeast-2"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "ap-northeast-3"
  region = "ap-northeast-3"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "ap-southeast-1"
  region = "ap-southeast-1"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "ap-southeast-2"
  region = "ap-southeast-2"
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "sa-east-1"
  region = "sa-east-1"
  default_tags { tags = local.common_tags }
}

# =============================================================================
# Module deployments per region
# =============================================================================

module "us_east_1" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.us-east-1 }
}

module "us_east_2" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.us-east-2 }
}

module "us_west_1" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.us-west-1 }
}

module "us_west_2" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.us-west-2 }
}

module "ca_central_1" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.ca-central-1 }
}

module "eu_west_1" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.eu-west-1 }
}

module "eu_west_2" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.eu-west-2 }
}

module "eu_west_3" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.eu-west-3 }
}

module "eu_central_1" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.eu-central-1 }
}

module "eu_north_1" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.eu-north-1 }
}

module "ap_south_1" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.ap-south-1 }
}

module "ap_northeast_1" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.ap-northeast-1 }
}

module "ap_northeast_2" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.ap-northeast-2 }
}

module "ap_northeast_3" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.ap-northeast-3 }
}

module "ap_southeast_1" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.ap-southeast-1 }
}

module "ap_southeast_2" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.ap-southeast-2 }
}

module "sa_east_1" {
  source        = "./modules/region-mesh"
  key_name      = var.key_name
  public_key    = var.public_key
  instance_type = var.instance_type
  project_name  = local.project_name
  providers     = { aws = aws.sa-east-1 }
}

# =============================================================================
# Outputs
# =============================================================================

output "instances" {
  description = "All instances across all regions"
  value = merge(
    module.us_east_1.instances,
    module.us_east_2.instances,
    module.us_west_1.instances,
    module.us_west_2.instances,
    module.ca_central_1.instances,
    module.eu_west_1.instances,
    module.eu_west_2.instances,
    module.eu_west_3.instances,
    module.eu_central_1.instances,
    module.eu_north_1.instances,
    module.ap_south_1.instances,
    module.ap_northeast_1.instances,
    module.ap_northeast_2.instances,
    module.ap_northeast_3.instances,
    module.ap_southeast_1.instances,
    module.ap_southeast_2.instances,
    module.sa_east_1.instances,
  )
}

output "regions" {
  value = [
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "ca-central-1",
    "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1", "eu-north-1",
    "ap-south-1", "ap-northeast-1", "ap-northeast-2", "ap-northeast-3",
    "ap-southeast-1", "ap-southeast-2",
    "sa-east-1"
  ]
}

output "instance_count" {
  value = {
    us_east_1      = module.us_east_1.az_count
    us_east_2      = module.us_east_2.az_count
    us_west_1      = module.us_west_1.az_count
    us_west_2      = module.us_west_2.az_count
    ca_central_1   = module.ca_central_1.az_count
    eu_west_1      = module.eu_west_1.az_count
    eu_west_2      = module.eu_west_2.az_count
    eu_west_3      = module.eu_west_3.az_count
    eu_central_1   = module.eu_central_1.az_count
    eu_north_1     = module.eu_north_1.az_count
    ap_south_1     = module.ap_south_1.az_count
    ap_northeast_1 = module.ap_northeast_1.az_count
    ap_northeast_2 = module.ap_northeast_2.az_count
    ap_northeast_3 = module.ap_northeast_3.az_count
    ap_southeast_1 = module.ap_southeast_1.az_count
    ap_southeast_2 = module.ap_southeast_2.az_count
    sa_east_1      = module.sa_east_1.az_count
  }
}
