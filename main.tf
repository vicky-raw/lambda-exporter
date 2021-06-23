data "archive_file" "log_exporter" {
  type        = "zip"
  source_file = "${path.module}/code/cloudwatch-to-s3.py"
  output_path = "${path.module}/code/cloudwatch-to-s3.zip"
}

resource "aws_iam_role" "log_exporter" {
  name = var.exporter_name 
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "log_exporter" {
  name =  var.exporter_name  
  role = aws_iam_role.log_exporter.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateExportTask",
        "logs:Describe*",
        "logs:ListTagsLogGroup",
        "ssm:DescribeParameters",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath",
        "ssm:PutParameter",
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}
data "aws_caller_identity" "account" {}
data "aws_region" "region" {}

resource "aws_lambda_function" "log_exporter" {
  filename         = data.archive_file.log_exporter.output_path
  function_name    = var.exporter_name 
  role             = aws_iam_role.log_exporter.arn
  handler          = "cloudwatch-to-s3.lambda_handler"
  source_code_hash = data.archive_file.log_exporter.output_base64sha256
  timeout          = 300

  runtime = "python3.8"

  environment {
    variables = {
      S3_BUCKET = var.bucket_name
      log_groups = var.log_group_names
    }
  }
}

resource "aws_cloudwatch_event_rule" "log_exporter" {
  name                = var.exporter_name 
  description         = "Fires periodically to export logs to S3"
  schedule_expression = var.schedule_period #"rate(4 hours)"
}

resource "aws_cloudwatch_event_target" "log_exporter" {
  rule      = aws_cloudwatch_event_rule.log_exporter.name
  arn       = aws_lambda_function.log_exporter.arn
}

resource "aws_lambda_permission" "log_exporter" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_exporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.log_exporter.arn
}

resource "aws_s3_bucket" "log_exporter_bucket" {
  bucket = var.bucket_name
  tags = map("Name", var.bucket_name)
  lifecycle_rule {
    id      = "LifeCycleRule_GLC"
    enabled = true
    prefix  = "/"
    transition {
      days          = 182
      storage_class = "GLACIER"
    }
  }

  grant {
    permissions = ["READ_ACP", "WRITE"]
    type        = "Group"
    uri         = "http://acs.amazonaws.com/groups/s3/LogDelivery"
  }

  lifecycle {
    prevent_destroy = false
  }
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "S3BucketPolicy",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${data.aws_caller_identity.account.account_id}:root"
            },
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${var.bucket_name}",
                "arn:aws:s3:::${var.bucket_name}/*"
            ]
        }
    ]
}
POLICY
}