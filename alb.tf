resource "aws_lb" "ext_lb" {
  name = "ext-lb"
  security_groups = [
    aws_security_group.ext_alb_sg.id
  ]
  internal           = false
  load_balancer_type = "application"
  tags = {
    Name = "ext-lb"
  }
  subnets = [
    aws_subnet.public_subnet[0].id,
    aws_subnet.public_subnet[1].id
  ]
}


resource "aws_lb_target_group" "ext_target_group" {
  name        = "ext-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.chuks_vpc.id

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/healthstatus"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 5
  }
}



resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.ext_lb.arn
  port              = 443
  protocol          = "HTTPS"

  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn = aws_acm_certificate_validation.chuksapp.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ext_target_group.arn
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ext_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}



#------------------------------------------------------------------------------------------
resource "aws_lb" "int_lb" {
  name = "int-lb"
  security_groups = [
    aws_security_group.int_alb_sg.id
  ]
  internal           = true
  load_balancer_type = "application"
  tags = {
    Name = "ext-lb"
  }
  subnets = [
    aws_subnet.private_subnets[0].id,
    aws_subnet.private_subnets[1].id
  ]
}

resource "aws_lb_target_group" "int_target_group" {
  name     = "tooling-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.chuks_vpc.id

  health_check {
    interval            = 10
    healthy_threshold   = 5
    unhealthy_threshold = 5
    timeout             = 5
    port                = 80
    protocol            = "HTTP"
    path                = "/healthstatus"
    matcher             = "200"
  }
}


resource "aws_lb_target_group" "wordpress_target_group" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.chuks_vpc.id

  health_check {
    enabled             = true
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    port                = "traffic-port"
    protocol            = "HTTP"
    path                = "/healthstatus"
    matcher             = "200"
  }
}



resource "aws_lb_listener" "int_listener" {
  load_balancer_arn = aws_lb.int_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "No matching application"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "tooling_rule" {
  listener_arn = aws_lb_listener.int_listener.arn
  priority     = 10

  condition {
    host_header {
      values = ["tooling.chuksapp.online"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.int_target_group.arn
  }
}

resource "aws_lb_listener_rule" "wordpress_rule" {
  listener_arn = aws_lb_listener.int_listener.arn
  priority     = 20

  condition {
    host_header {
      values = ["wordpress.chuksapp.online"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_target_group.arn
  }
}