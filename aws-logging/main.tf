terraform {
  required_version = ">= 0.14"
}

# TODO: Log storage in the root account

variable "account_name" {
  type = string
}

locals {
  cloudtrail_bucket_name = "${var.account_name}-logs-cloudtrail"
  cloudfront_bucket_name = "${var.account_name}-logs-cloudfront"
}

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}


data "aws_iam_policy_document" "bucket_policy" {
  statement {
    actions = [
      "s3:PutObject",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${local.cloudtrail_bucket_name}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"

      values = ["bucket-owner-full-control"]
    }

    principals {
      type = "Service"
      identifiers = [
        "cloudtrail.amazonaws.com",
      ]
    }
  }

  statement {
    actions = [
      "s3:GetBucketAcl",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${local.cloudtrail_bucket_name}",
    ]

    principals {
      type = "Service"
      identifiers = [
        "cloudtrail.amazonaws.com",
      ]
    }
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = local.cloudtrail_bucket_name
  acl    = "log-delivery-write"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule {
    enabled = true

    noncurrent_version_transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_transition {
      days          = 60
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.bucket_policy.json

  depends_on = [
    aws_s3_bucket_public_access_block.logs,
  ]
}

resource "aws_kms_key" "cloudtrail" {
  description = "cloudtrail"
  policy      = <<EOF
{
    "Version": "2012-10-17",
    "Id": "CloudTrail key policy",
    "Statement": [
        {
            "Sid": "Enable IAM User Permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root",
                    "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/BootstrapAccessRole"
                ]
            },
            "Action": "kms:*",
            "Resource": "*"
        },
        {
            "Sid": "Allow CloudTrail to encrypt logs",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "kms:GenerateDataKey*",
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "kms:EncryptionContext:aws:cloudtrail:arn": "arn:${data.aws_partition.current.partition}:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"
                }
            }
        },
        {
            "Sid": "Allow CloudTrail to describe key",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "kms:DescribeKey",
            "Resource": "*"
        },
        {
            "Sid": "Allow principals in the account to decrypt log files",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": [
                "kms:Decrypt",
                "kms:ReEncryptFrom"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "kms:CallerAccount": "${data.aws_caller_identity.current.account_id}"
                },
                "StringLike": {
                    "kms:EncryptionContext:aws:cloudtrail:arn": "arn:${data.aws_partition.current.partition}:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"
                }
            }
        },
        {
            "Sid": "Allow alias creation during setup",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": "kms:CreateAlias",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "kms:CallerAccount": "${data.aws_caller_identity.current.account_id}",
                    "kms:ViaService": "ec2.${data.aws_region.current.name}.amazonaws.com"
                }
            }
        },
        {
            "Sid": "Enable cross account log decryption",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": [
                "kms:Decrypt",
                "kms:ReEncryptFrom"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "kms:CallerAccount": "${data.aws_caller_identity.current.account_id}"
                },
                "StringLike": {
                    "kms:EncryptionContext:aws:cloudtrail:arn": "arn:${data.aws_partition.current.partition}:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"
                }
            }
        }
    ]
}
EOF
}

resource "aws_cloudtrail" "cloudtrail" {
  name                          = "cloudtrail"
  enable_logging                = true
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  s3_bucket_name = local.cloudtrail_bucket_name
  kms_key_id     = aws_kms_key.cloudtrail.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:${data.aws_partition.current.partition}:s3:::"]
    }
  }

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:${data.aws_partition.current.partition}:lambda"]
    }
  }

  depends_on = [
    aws_s3_bucket_policy.bucket_policy,
  ]
}

data "aws_iam_policy_document" "cloudfront_bucket_policy" {
  statement {
    actions = [
      "s3:PutObject",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${local.cloudfront_bucket_name}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"

      values = ["bucket-owner-full-control"]
    }

    principals {
      type = "Service"
      identifiers = [
        "delivery.logs.amazonaws.com",
      ]
    }
  }

  statement {
    actions = [
      "s3:GetBucketAcl",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:s3:::${local.cloudfront_bucket_name}",
    ]

    principals {
      type = "Service"
      identifiers = [
        "delivery.logs.amazonaws.com",
      ]
    }
  }
}

resource "aws_s3_bucket" "cloudfront_logs" {
  bucket = local.cloudfront_bucket_name
  acl    = "log-delivery-write"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule {
    enabled = true

    noncurrent_version_transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_transition {
      days          = 60
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudfront_bucket_policy" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  policy = data.aws_iam_policy_document.cloudfront_bucket_policy.json

  depends_on = [
    aws_s3_bucket_public_access_block.cloudfront_logs,
  ]
}
