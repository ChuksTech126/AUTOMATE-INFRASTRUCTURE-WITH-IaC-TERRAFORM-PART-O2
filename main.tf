resource "aws_s3_bucket" "chuks_bucket" {
  bucket = "chuksmet-bucket"
  tags = {
    Name = "chuksmet"
  }
}

resource "aws_s3_bucket_versioning" "chuks_bucket_versioning" {
  bucket = aws_s3_bucket.chuks_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "chuks_bucket_encryption" {
  bucket = aws_s3_bucket.chuks_bucket.id


  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "chuks_bucket_access_control" {
  bucket = aws_s3_bucket.chuks_bucket.id

  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}

resource "aws_vpc" "chuks_vpc" {
  cidr_block = var.cidr_block

  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames
  tags = {
    Name = "chuks_vpc"
  }
}

data "aws_availability_zones" "existing_Azs" {
  state = "available"
}

data "aws_ssm_parameter" "ubuntu_2204_ami" {
  name = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.chuks_vpc.id
  count                   = var.preferred_number_of_subnets == null ? length(data.aws_availability_zones.existing_Azs.names) : var.preferred_number_of_subnets
  cidr_block              = cidrsubnet(aws_vpc.chuks_vpc.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.existing_Azs.names[count.index]
  tags = {
    Name = "public_subnet ${count.index + 1}"
  }
}

resource "aws_internet_gateway" "chuks_gateway" {
  vpc_id = aws_vpc.chuks_vpc.id

  tags = {
    Name = var.aws_internet_gateway
  }
}

resource "aws_route_table" "chuks_route_table" {
  vpc_id = aws_vpc.chuks_vpc.id

  route {
    gateway_id = aws_internet_gateway.chuks_gateway.id
    cidr_block = "0.0.0.0/0"
  }
  tags = {
    Name = var.aws_route_table
  }
}

resource "aws_route_table_association" "chuks_route_table_subnet_association" {
  count          = length(aws_subnet.public_subnet)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.chuks_route_table.id
}

resource "aws_subnet" "private_subnets" {
  vpc_id            = aws_vpc.chuks_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.chuks_vpc.cidr_block, 8, count.index + length(aws_subnet.public_subnet))
  count             = var.preferred_number_of_private_subnets == null ? length(data.aws_availability_zones.existing_Azs.names) : var.preferred_number_of_private_subnets
  availability_zone = data.aws_availability_zones.existing_Azs.names[count.index]
  tags = {
    Name = "private_subnet ${count.index + 1}"
  }

}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.chuks_vpc.id

  tags = {
    Name = "private"
  }
  route {
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
    cidr_block     = "0.0.0.0/0"
  }
}

resource "aws_route_table_association" "private_Association" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "nat_eip"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  depends_on = [
    aws_internet_gateway.chuks_gateway
  ]
  subnet_id = aws_subnet.public_subnet[0].id
  tags = {
    Name = "chuks_nat_gateway"
  }
}