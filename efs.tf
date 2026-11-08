#-----------------------------------------------------------------------------------------
#               THE ELASTIC FILE SYSTEM, ITS MOUNT TARGET AND ACCESS POINT
#-----------------------------------------------------------------------------------------

# CREATE ELASTIC FILE SYSTEM
resource "aws_efs_file_system" "chuks_efs" {
  encrypted = true

}

#CREATE MOUNT TARGET
resource "aws_efs_mount_target" "subnet_0" {
  subnet_id       = aws_subnet.private_subnets[0].id
  security_groups = [aws_security_group.efs_sg.id]
  file_system_id  = aws_efs_file_system.chuks_efs.id
}

#CREATE MOUNT TARGET
resource "aws_efs_mount_target" "subnet_1" {
  file_system_id  = aws_efs_file_system.chuks_efs.id
  security_groups = [aws_security_group.efs_sg.id]
  subnet_id       = aws_subnet.private_subnets[1].id
}

#CREATE ACCESS POINT FOR EFS 
resource "aws_efs_access_point" "wordpress_efs_access" {
  file_system_id = aws_efs_file_system.chuks_efs.id

  posix_user {
    uid = 33
    gid = 33
  }

  root_directory {
    path = "/wordpress"

    creation_info {
      owner_uid   = 33
      owner_gid   = 33
      permissions = "0775"
    }
  }
}

resource "aws_efs_access_point" "tooling_efs_access" {
  file_system_id = aws_efs_file_system.chuks_efs.id

  posix_user {
    uid = 33
    gid = 33
  }

  root_directory {
    path = "/tooling"

    creation_info {
      owner_uid   = 33
      owner_gid   = 33
      permissions = "0775"
    }
  }
}  