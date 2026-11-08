variable "region" {
  type        = string
  description = "region of the provider"
  default     = "us-east-1"
}

variable "block_public_acls" {
  type    = bool
  default = true
}

variable "block_public_policy" {
  type    = bool
  default = true
}

variable "ignore_public_acls" {
  type    = bool
  default = true
}

variable "restrict_public_buckets" {
  type    = bool
  default = true
}

variable "cidr_block" {
  type    = string
  default = "172.16.0.0/16"
}

variable "enable_dns_support" {
  type    = bool
  default = true
}

variable "enable_dns_hostnames" {
  type    = bool
  default = true
}

variable "preferred_number_of_subnets" {
  type    = number
  default = 2

  validation {
    condition     = var.preferred_number_of_subnets == null || var.preferred_number_of_subnets >= 2
    error_message = "At least two public subnets are required by the load balancers."
  }
}

variable "aws_internet_gateway" {
  type    = string
  default = "chuks_gateway"
}

variable "aws_route_table" {
  type    = string
  default = "chuks_route_table"
}

variable "preferred_number_of_private_subnets" {
  type    = number
  default = 4

  validation {
    condition     = var.preferred_number_of_private_subnets == null || var.preferred_number_of_private_subnets >= 2
    error_message = "At least two private subnets are required by the load balancers and RDS."
  }
}

variable "keypair" {
  type = string

}

variable "username" {
  type = string
}

variable "password" {
  type        = string
  sensitive   = true
  description = "database password is displayed in the cli"
}


variable "ami" {
  type = string
}

variable "account_no" {
  type = number
}
