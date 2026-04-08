# AWS Provider Configuration for Multi-Region Deployment
# Frankfurt (eu-central-1) and North Virginia (us-east-1)

# Default provider (required by Terraform even when all resources use aliased providers)
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      auto-delete = "no"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
  alias  = "frankfurt"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      auto-delete = "no"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "virginia"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      auto-delete = "no"
    }
  }
}
