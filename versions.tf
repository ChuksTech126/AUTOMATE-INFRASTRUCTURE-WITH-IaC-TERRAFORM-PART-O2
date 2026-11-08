terraform {
  backend "s3" {
    bucket       = "chuksmet-bucket"
    use_lockfile = true
    key          = "terraform.tfstate"
    region       = "us-east-1"
  }
  required_providers {
    aws = {
      version = "~>6.0"
      source  = "hashicorp/aws"
    }
  }
  required_version = "~>1.14.0"
}

provider "aws" {
  region = var.region
}
