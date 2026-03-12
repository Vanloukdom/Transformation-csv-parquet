output "csv_input_bucket" {
  description = "S3 bucket to upload CSV files"
  value       = aws_s3_bucket.csv_input.bucket
}

output "parquet_output_bucket" {
  description = "S3 bucket where Parquet files are stored"
  value       = aws_s3_bucket.parquet_output.bucket
}

output "lambda_function_name" {
  description = "Lambda function that triggers Glue"
  value       = aws_lambda_function.csv_trigger.function_name
}

output "glue_job_name" {
  description = "Glue job that converts CSV to Parquet"
  value       = aws_glue_job.csv_to_parquet.name
}
