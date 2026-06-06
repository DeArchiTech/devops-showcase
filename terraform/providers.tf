terraform {
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.21"
    }
  }

  # Remote state — reproducible by any team member
  backend "s3" {
    bucket                      = "dev-ops-bucket"
    key                         = "terraform.tfstate"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
    endpoints = {
      s3 = "https://sjc1.vultrobjects.com"
    }
  }
}

provider "vultr" {
  # Reads VULTR_API_KEY from environment automatically
  rate_limit  = 100
  retry_limit = 3
}
