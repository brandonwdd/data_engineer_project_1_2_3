"""
Register/copy Silver tables from Hadoop catalog to REST catalog so Trino/dbt can access them.
Uses a single SparkSession configured with two catalogs.
"""
from __future__ import annotations

from pyspark.sql import SparkSession


def build_spark() -> SparkSession:
    """Create SparkSession supporting both Hadoop and REST catalogs"""
    builder = (
        SparkSession.builder.appName("register-silver-catalogs")
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        # Hadoop catalog (source)
        .config("spark.sql.catalog.iceberg_hadoop", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.iceberg_hadoop.type", "hadoop")
        .config("spark.sql.catalog.iceberg_hadoop.warehouse", "s3a://warehouse/iceberg")
        # REST catalog (target)
        .config("spark.sql.catalog.iceberg_rest", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.iceberg_rest.type", "rest")
        .config("spark.sql.catalog.iceberg_rest.uri", "http://iceberg-rest:8181")
        .config("spark.sql.catalog.iceberg_rest.warehouse", "s3a://warehouse/")
        .config("spark.sql.defaultCatalog", "iceberg_rest")
    )
    
    builder = (
        builder.config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000")
        .config("spark.hadoop.fs.s3a.access.key", "minioadmin")
        .config("spark.hadoop.fs.s3a.secret.key", "minioadmin")
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
        # Support s3:// protocol mapping to s3a://
        .config("spark.hadoop.fs.s3.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
        .config("spark.hadoop.fs.s3.endpoint", "http://minio:9000")
        .config("spark.hadoop.fs.s3.access.key", "minioadmin")
        .config("spark.hadoop.fs.s3.secret.key", "minioadmin")
        .config("spark.hadoop.fs.s3.path.style.access", "true")
    )
    
    return builder.getOrCreate()


def register_silver_tables() -> None:
    """Copy Silver tables from Hadoop catalog to REST catalog"""
    spark = build_spark()
    
    entities = ["users", "orders", "payments"]
    
    for entity in entities:
        print(f"Processing {entity} table...")
        
        try:
            # Read from Hadoop catalog
            df = spark.table(f"iceberg_hadoop.silver.{entity}")
            row_count = df.count()
            print(f"  - Found {row_count} records in Hadoop catalog")
            
            # Ensure schema exists in REST catalog (register empty tables too for Trino/dbt access)
            spark.sql("CREATE SCHEMA IF NOT EXISTS iceberg_rest.silver")
            
            # Create temporary view
            df.createOrReplaceTempView(f"temp_{entity}")
            
            # Create table in REST catalog and insert data
            print(f"  - Writing data to REST catalog...")
            spark.sql(f"""
                CREATE OR REPLACE TABLE iceberg_rest.silver.{entity} 
                USING iceberg
                AS SELECT * FROM temp_{entity}
            """)
            
            # Verify
            rest_count = spark.table(f"iceberg_rest.silver.{entity}").count()
            print(f"  - Verified in REST catalog: {rest_count} records")
            print(f"  ✓ {entity} table registered successfully")
            
        except Exception as e:
            print(f"  ✗ {entity} table processing failed: {e}")
            import traceback
            traceback.print_exc()
            continue
    
    spark.stop()
    print("\nCompleted!")


if __name__ == "__main__":
    register_silver_tables()
