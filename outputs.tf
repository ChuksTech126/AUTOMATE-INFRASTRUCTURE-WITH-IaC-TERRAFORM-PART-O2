output "vpc_id" {
  value = aws_vpc.chuks_vpc.id
}

output "subnet_cidr" {
  value = aws_subnet.public_subnet[*].cidr_block
}

output "subnet_id" {
  value = aws_subnet.public_subnet[*].id
}

output "subnet_cidrs" {
  value = aws_subnet.private_subnets[*].cidr_block
}

output "subnet_ids" {
  value = aws_subnet.private_subnets[*].id
}

output "tooling_url" {
  value = "https://tooling.chuksapp.online"
}

output "wordpress_url" {
  value = "https://wordpress.chuksapp.online"
}
