resource "aws_iam_role" "iam_role" {
  name = "chuks_iam_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Effect = "Allow"
      Sid    = ""
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "policy" {
  name        = "chuks_policy"
  description = "A test policy"
  policy = jsonencode({

    Version = "2012-10-17"

    Statement = [{
      Action = [
        "ec2:Describe*"
      ]
      Resource = "*"
      Effect   = "Allow"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "role_policy_attachment" {
  role       = aws_iam_role.iam_role.name
  policy_arn = aws_iam_policy.policy.arn
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ip" {
  name = "aws_iam_instance_test"
  role = aws_iam_role.iam_role.name
}