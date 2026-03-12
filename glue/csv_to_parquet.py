import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

# ── Arguments ────────────────────────────────────────────────────────────────
args = getResolvedOptions(
    sys.argv,
    ["JOB_NAME", "INPUT_PATH", "OUTPUT_PATH"],
)

# ── Glue / Spark context ──────────────────────────────────────────────────────
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

input_path  = args["INPUT_PATH"]
output_path = args["OUTPUT_PATH"]

print(f"[INFO] Reading CSV from : {input_path}")
print(f"[INFO] Writing Parquet to: {output_path}")

# ── Read CSV ──────────────────────────────────────────────────────────────────
datasource = glueContext.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={"paths": [input_path]},
    format="csv",
    format_options={
        "withHeader": True,
        "separator": ",",
        "quoteChar": '"',
    },
)

print(f"[INFO] Record count: {datasource.count()}")
datasource.printSchema()

# ── Write Parquet ─────────────────────────────────────────────────────────────
glueContext.write_dynamic_frame.from_options(
    frame=datasource,
    connection_type="s3",
    connection_options={"path": output_path},
    format="parquet",
    format_options={"compression": "snappy"},
)

print("[INFO] Conversion complete.")
job.commit()
