resource "aws_kms_key" "ACS-kms" {
  description             = "KMS key for encrypting AWS resources"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "kms-key-policy"

    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${var.account_no}:root"
        }

        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}


#CREATE KEY ALIAS
resource "aws_kms_alias" "alias" {
  name          = "alias/kms"
  target_key_id = aws_kms_key.ACS-kms.key_id
}