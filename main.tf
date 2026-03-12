terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

# ─────────────────────────────────────────────
# S3 BUCKETS
# ─────────────────────────────────────────────

resource "aws_s3_bucket" "csv_input" {
  bucket        = "${var.project_name}-csv-input-${var.environment}"
  force_destroy = true

  tags = local.common_tags
}

resource "aws_s3_bucket" "parquet_output" {
  bucket        = "${var.project_name}-parquet-output-${var.environment}"
  force_destroy = true

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "csv_input" {
  bucket = aws_s3_bucket.csv_input.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "csv_input" {
  bucket = aws_s3_bucket.csv_input.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "parquet_output" {
  bucket = aws_s3_bucket.parquet_output.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Autoriser Lambda à recevoir les notifications S3
resource "aws_s3_bucket_notification" "csv_upload_trigger" {
  bucket = aws_s3_bucket.csv_input.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.csv_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

# ─────────────────────────────────────────────
# IAM – LAMBDA
# ─────────────────────────────────────────────

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-lambda-policy-${var.environment}"
  description = "Permissions for Lambda to trigger Glue and access S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "S3ReadInput"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.csv_input.arn,
          "${aws_s3_bucket.csv_input.arn}/*"
        ]
      },
      {
        Sid    = "GlueTrigger"
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJob"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# ─────────────────────────────────────────────
# LAMBDA FUNCTION
# ─────────────────────────────────────────────

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda/handler.zip"
}

resource "aws_lambda_function" "csv_trigger" {
  function_name    = "${var.project_name}-csv-trigger-${var.environment}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      GLUE_JOB_NAME      = aws_glue_job.csv_to_parquet.name
      OUTPUT_BUCKET      = aws_s3_bucket.parquet_output.bucket
      OUTPUT_PREFIX      = "converted/"
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.csv_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.csv_input.arn
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.csv_trigger.function_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

# ─────────────────────────────────────────────
# IAM – GLUE
# ─────────────────────────────────────────────

resource "aws_iam_role" "glue_exec" {
  name = "${var.project_name}-glue-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_policy" "glue_s3_policy" {
  name = "${var.project_name}-glue-s3-policy-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadInput"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.csv_input.arn,
          "${aws_s3_bucket.csv_input.arn}/*"
        ]
      },
      {
        Sid    = "S3WriteOutput"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.parquet_output.arn,
          "${aws_s3_bucket.parquet_output.arn}/*"
        ]
      },
      {
        Sid      = "S3GlueScripts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.parquet_output.arn}/glue-scripts/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_s3_attach" {
  role       = aws_iam_role.glue_exec.name
  policy_arn = aws_iam_policy.glue_s3_policy.arn
}

# ─────────────────────────────────────────────
# GLUE JOB
# ─────────────────────────────────────────────

resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.parquet_output.bucket
  key    = "glue-scripts/csv_to_parquet.py"
  source = "${path.module}/glue/csv_to_parquet.py"
  etag   = filemd5("${path.module}/glue/csv_to_parquet.py")
}

resource "aws_glue_job" "csv_to_parquet" {
  name         = "${var.project_name}-csv-to-parquet-${var.environment}"
  role_arn     = aws_iam_role.glue_exec.arn
  glue_version = "4.0"

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.parquet_output.bucket}/glue-scripts/csv_to_parquet.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"                  = "false"
    "--TempDir"                          = "s3://${aws_s3_bucket.parquet_output.bucket}/tmp/"
    "--OUTPUT_BUCKET"                    = aws_s3_bucket.parquet_output.bucket
    "--OUTPUT_PREFIX"                    = "converted/"
  }

  number_of_workers = 2
  worker_type       = "G.1X"
  timeout           = 30

  tags = local.common_tags
}
