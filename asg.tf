#--------------------------------------------------------------------------------
#                          SNS NOTIFICATIONS FOR ASG
#--------------------------------------------------------------------------------
#SNS TOPIC
# SNS TOPIC
resource "aws_sns_topic" "chuks_topic" {
  name = "default_cloud_watch_topic"
}

# SNS NOTIFICATIONS
resource "aws_autoscaling_notification" "chuks_notified" {
  topic_arn = aws_sns_topic.chuks_topic.arn

  group_names = [
    aws_autoscaling_group.bastion_asg.name,
    aws_autoscaling_group.wordpress_asg.name,
    aws_autoscaling_group.tooling_asg.name,
    aws_autoscaling_group.nginx_asg.name
  ]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"
  ]
}


#----------------------------------------------------------------------------------------


resource "aws_launch_template" "nginx_template" {
  name_prefix   = "nginx-template-"
  image_id      = var.ami
  instance_type = "t2.micro"
  key_name      = var.keypair

  vpc_security_group_ids = [
    aws_security_group.nginx_sg.id
  ]

  user_data = base64encode(templatefile("${path.module}/nginx.sh", {
    internal_lb_dns = aws_lb.int_lb.dns_name
  }))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "nginx"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}



resource "aws_autoscaling_group" "nginx_asg" {
  name             = "nginx-asg"
  desired_capacity = 2
  min_size         = 1
  max_size         = 4

  vpc_zone_identifier = [
    aws_subnet.public_subnet[0].id,
    aws_subnet.public_subnet[1].id
  ]

  target_group_arns = [
    aws_lb_target_group.ext_target_group.arn
  ]

  health_check_type         = "ELB"
  health_check_grace_period = 900
  wait_for_capacity_timeout = "20m"

  launch_template {
    id      = aws_launch_template.nginx_template.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    triggers = ["tag"]

    preferences {
      min_healthy_percentage = 50
      max_healthy_percentage = 150
      instance_warmup        = 300
    }
  }

  tag {
    key                 = "BootstrapRevision"
    value               = "ubuntu-22.04-proxy-https"
    propagate_at_launch = true
  }

  depends_on = [
    aws_lb_listener.https,
    aws_lb_listener.http
  ]

  lifecycle {
    create_before_destroy = true
  }
}


#----------------------------------------------------------------------------------------
#                             BASTION 
resource "aws_launch_template" "bastion_template" {
  image_id = var.ami
  vpc_security_group_ids = [
    aws_security_group.bastion_sg.id
  ]
  key_name      = var.keypair
  instance_type = "t2.micro"
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "bastion"
    }
  }
  user_data = filebase64("${path.module}/bastion.sh")
}

resource "aws_autoscaling_group" "bastion_asg" {
  vpc_zone_identifier = [
    aws_subnet.public_subnet[0].id,
    aws_subnet.public_subnet[1].id
  ]
  min_size                  = 1
  max_size                  = 4
  desired_capacity          = 2
  health_check_type         = "EC2"
  health_check_grace_period = 900
  launch_template {
    id      = aws_launch_template.bastion_template.id
    version = "$Latest"
  }
  name = "bastion-asg"

}


#------------------------------------------------------------------------------------------
#
#------------------------------------------------------------------------------------------


resource "aws_launch_template" "tooling_template" {
  name_prefix   = "tooling-template"
  image_id      = data.aws_ssm_parameter.ubuntu_2204_ami.value
  instance_type = "t2.micro"
  key_name      = var.keypair

  iam_instance_profile {
    name = aws_iam_instance_profile.ip.name
  }

  vpc_security_group_ids = [
    aws_security_group.webserver_sg.id
  ]



  user_data = base64encode(templatefile("${path.module}/tooling.sh", {
    efs_file_system_id  = aws_efs_file_system.chuks_efs.id
    efs_access_point_id = aws_efs_access_point.tooling_efs_access.id

    db_host_b64     = base64encode(aws_db_instance.rds.address)
    db_port_b64     = base64encode(tostring(aws_db_instance.rds.port))
    db_name_b64     = base64encode(aws_db_instance.rds.db_name)
    db_username_b64 = base64encode(var.username)
    db_password_b64 = base64encode(var.password)
  }))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "tooling"
    }
  }
}

resource "aws_autoscaling_group" "tooling_asg" {
  vpc_zone_identifier = [
    aws_subnet.private_subnets[0].id,
    aws_subnet.private_subnets[1].id
  ]
  target_group_arns = [
    aws_lb_target_group.int_target_group.arn
  ]
  min_size                  = 1
  max_size                  = 4
  desired_capacity          = 2
  health_check_type         = "ELB"
  health_check_grace_period = 1800
  wait_for_capacity_timeout = "45m"
  launch_template {
    id      = aws_launch_template.tooling_template.id
    version = "$Latest"
  }
  instance_refresh {
    strategy = "Rolling"
    triggers = ["tag"]

    preferences {
      min_healthy_percentage = 50
      max_healthy_percentage = 150
      instance_warmup        = 300
    }
  }
  tag {
    key                 = "BootstrapRevision"
    value               = "2026-11-08-efs-stunnel-v1.36.0-rsync"
    propagate_at_launch = true
  }
  name = "tooling-asg"

}

#----------------------------------------------------------------------------
#                                 wordpress
#----------------------------------------------------------------------------


resource "aws_launch_template" "wordpress_template" {
  name_prefix   = "wordpress-template"
  image_id      = data.aws_ssm_parameter.ubuntu_2204_ami.value
  instance_type = "t2.micro"
  key_name      = var.keypair

  iam_instance_profile {
    name = aws_iam_instance_profile.ip.name
  }

  vpc_security_group_ids = [
    aws_security_group.webserver_sg.id
  ]

  user_data = base64encode(templatefile("${path.module}/wordpress.sh", {
    efs_file_system_id  = aws_efs_file_system.chuks_efs.id
    efs_access_point_id = aws_efs_access_point.wordpress_efs_access.id

    db_host_b64     = base64encode(aws_db_instance.rds.address)
    db_port_b64     = base64encode(tostring(aws_db_instance.rds.port))
    db_name_b64     = base64encode(aws_db_instance.rds.db_name)
    db_username_b64 = base64encode(var.username)
    db_password_b64 = base64encode(var.password)
  }))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "wordpress"
    }
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  vpc_zone_identifier = [
    aws_subnet.private_subnets[0].id,
    aws_subnet.private_subnets[1].id
  ]
  target_group_arns = [
    aws_lb_target_group.wordpress_target_group.arn
  ]
  min_size                  = 1
  max_size                  = 4
  desired_capacity          = 2
  health_check_type         = "ELB"
  health_check_grace_period = 1800
  wait_for_capacity_timeout = "45m"
  launch_template {
    id      = aws_launch_template.wordpress_template.id
    version = "$Latest"
  }
  instance_refresh {
    strategy = "Rolling"
    triggers = ["tag"]

    preferences {
      min_healthy_percentage = 50
      max_healthy_percentage = 150
      instance_warmup        = 300
    }
  }
  tag {
    key                 = "BootstrapRevision"
    value               = "ubuntu-22.04-efs-stunnel-v1.36.0-rsync-proxy-https"
    propagate_at_launch = true
  }
  name = "wordpress-asg"

}