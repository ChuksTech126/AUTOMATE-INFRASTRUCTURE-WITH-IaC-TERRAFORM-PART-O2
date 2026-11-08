resource "aws_acm_certificate" "chuksapp" {
  domain_name       = "chuksapp.online"
  validation_method = "DNS"

  subject_alternative_names = ["*.chuksapp.online"]
}

data "aws_route53_zone" "hosted_zone" {
  name         = "chuksapp.online"
  private_zone = false
}

resource "aws_route53_record" "chuksapp" {
  for_each = {
    for dvo in aws_acm_certificate.chuksapp.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.hosted_zone.zone_id
}

# VALIDATE THE CERTIFICATE THROUGH DNS METHOD 
resource "aws_acm_certificate_validation" "chuksapp" {
  certificate_arn         = aws_acm_certificate.chuksapp.arn
  validation_record_fqdns = [for record in aws_route53_record.chuksapp : record.fqdn]
}

# CREATE RECORDS FOR TOOLING
resource "aws_route53_record" "tooling" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = "tooling.chuksapp.online"
  type    = "A"

  alias {
    name                   = aws_lb.ext_lb.dns_name
    zone_id                = aws_lb.ext_lb.zone_id
    evaluate_target_health = true
  }
}


# CREATE RECORD FOR WORDPRESS
resource "aws_route53_record" "wordpress" {
  zone_id = data.aws_route53_zone.hosted_zone.zone_id
  name    = "wordpress.chuksapp.online"
  type    = "A"

  alias {
    name                   = aws_lb.ext_lb.dns_name
    zone_id                = aws_lb.ext_lb.zone_id
    evaluate_target_health = true
  }
}











