import json
import os
import boto3
import logging
import urllib.parse

logger = logging.getLogger()
logger.setLevel(logging.INFO)

glue_client = boto3.client("glue")


def lambda_handler(event, context):
    """
    Triggered by S3 PutObject event on CSV files.
    Starts a Glue job passing the S3 key as argument.
    """
    glue_job_name = os.environ["GLUE_JOB_NAME"]
    output_bucket = os.environ["OUTPUT_BUCKET"]
    output_prefix = os.environ["OUTPUT_PREFIX"]

    for record in event.get("Records", []):
        source_bucket = record["s3"]["bucket"]["name"]
        source_key = urllib.parse.unquote_plus(
            record["s3"]["object"]["key"], encoding="utf-8"
        )

        logger.info(f"New CSV uploaded: s3://{source_bucket}/{source_key}")

        # Derive a unique output prefix per file
        file_stem = source_key.replace("/", "_").replace(".csv", "")
        job_output_prefix = f"{output_prefix}{file_stem}/"

        response = glue_client.start_job_run(
            JobName=glue_job_name,
            Arguments={
                "--INPUT_PATH": f"s3://{source_bucket}/{source_key}",
                "--OUTPUT_PATH": f"s3://{output_bucket}/{job_output_prefix}",
            },
        )

        job_run_id = response["JobRunId"]
        logger.info(
            f"Glue job '{glue_job_name}' started. JobRunId: {job_run_id}"
        )

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Glue job triggered successfully"}),
    }
