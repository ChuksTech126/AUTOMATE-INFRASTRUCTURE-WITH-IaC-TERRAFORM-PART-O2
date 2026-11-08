#----------------------------------------------------------------------------------------------------
#                              THE SUBNET GROUP AND aws_db_instance
#----------------------------------------------------------------------------------------------------

#DB_SUBNET_GROUP 

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds_subnet_group"
  subnet_ids = aws_subnet.private_subnets[*].id
}


#DB_INSTANCE CREATION
resource "aws_db_instance" "rds" {
  engine                    = "mysql"
  engine_version            = "8.0"
  instance_class            = "db.t3.micro"
  username                  = var.username
  password                  = var.password
  skip_final_snapshot       = false
  final_snapshot_identifier = "chuks-db-final-backup-20261104"

  identifier          = "chuks-db-encrypted"
  allocated_storage   = 20
  publicly_accessible = false
  storage_encrypted   = true
  kms_key_id          = aws_kms_key.ACS-kms.arn
  storage_type        = "gp2"

  db_name              = "chuks_db"
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [
    aws_security_group.db_sg.id
  ]
  port = 3306
}