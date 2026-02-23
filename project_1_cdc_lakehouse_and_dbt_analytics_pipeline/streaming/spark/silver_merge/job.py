"""Silver merge job from Bronze to Silver tables."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import StructType, StructField, StringType, LongType, TimestampType, DecimalType

from .config import SilverConfig
from .parse_bronze import build_latest_events_df


def build_spark(cfg: SilverConfig) -> SparkSession:
    """Create SparkSession with Iceberg + S3/MinIO config."""
    builder = (
        SparkSession.builder.appName("project1-silver-merge")
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.iceberg.type", "hadoop")
        .config("spark.sql.catalog.iceberg.warehouse", cfg.catalog_warehouse)
        .config("spark.sql.defaultCatalog", "iceberg")
    )

    builder = (
        builder.config("spark.hadoop.fs.s3a.endpoint", cfg.s3_endpoint)
        .config("spark.hadoop.fs.s3a.access.key", cfg.s3_access_key)
        .config("spark.hadoop.fs.s3a.secret.key", cfg.s3_secret_key)
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    )

    return builder.getOrCreate()


def ensure_silver_tables(spark: SparkSession, cfg: SilverConfig) -> None:
    """Create Silver tables if they don't exist."""
    ns = cfg.silver_namespace

    # Users
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS iceberg.{ns}")
    spark.sql(f"""
        CREATE TABLE IF NOT EXISTS iceberg.{ns}.users (
            user_id     BIGINT   NOT NULL,
            email       STRING,
            status      STRING,
            created_at  TIMESTAMP,
            updated_at  TIMESTAMP,
            _bronze_event_uid STRING,
            _bronze_ordering_key STRING,
            _bronze_ts_ms BIGINT,
            _silver_updated_at TIMESTAMP NOT NULL
        )
        USING iceberg
        PARTITIONED BY (days(_silver_updated_at))
        TBLPROPERTIES (
            'format-version' = '2',
            'write.parquet.compression-codec' = 'snappy'
        )
    """)

    # Orders
    spark.sql(f"""
        CREATE TABLE IF NOT EXISTS iceberg.{ns}.orders (
            order_id     BIGINT   NOT NULL,
            user_id      BIGINT   NOT NULL,
            order_ts     TIMESTAMP,
            status       STRING,
            total_amount DECIMAL(18,2),
            updated_at    TIMESTAMP,
            _bronze_event_uid STRING,
            _bronze_ordering_key STRING,
            _bronze_ts_ms BIGINT,
            _silver_updated_at TIMESTAMP NOT NULL
        )
        USING iceberg
        PARTITIONED BY (days(_silver_updated_at))
        TBLPROPERTIES (
            'format-version' = '2',
            'write.parquet.compression-codec' = 'snappy'
        )
    """)

    # Payments
    spark.sql(f"""
        CREATE TABLE IF NOT EXISTS iceberg.{ns}.payments (
            payment_id     BIGINT   NOT NULL,
            order_id       BIGINT   NOT NULL,
            amount         DECIMAL(18,2),
            status         STRING,
            failure_reason STRING,
            updated_at      TIMESTAMP,
            _bronze_event_uid STRING,
            _bronze_ordering_key STRING,
            _bronze_ts_ms BIGINT,
            _silver_updated_at TIMESTAMP NOT NULL
        )
        USING iceberg
        PARTITIONED BY (days(_silver_updated_at))
        TBLPROPERTIES (
            'format-version' = '2',
            'write.parquet.compression-codec' = 'snappy'
        )
    """)


def merge_entity(
    spark: SparkSession,
    cfg: SilverConfig,
    entity: str,
    latest_events: Any,
) -> None:
    """
    MERGE latest_events into Silver table for entity.
    - op='d': DELETE matching PK (from 'before' JSON)
    - op in ('c','u','r'): MERGE (upsert) using ordering_key comparison (from 'after' JSON)
    """
    ns = cfg.silver_namespace
    table_name = f"iceberg.{ns}.{entity}"
    silver_updated_at = datetime.now(timezone.utc)

    # Separate deletes and upserts BEFORE parsing
    deletes = latest_events.filter(F.col("op") == "d")
    upserts = latest_events.filter(F.col("op").isin(["c", "u", "r"]))

    # Handle deletes: extract PK from 'before' JSON
    if deletes.count() > 0:
        if entity == "users":
            delete_schema = StructType([StructField("user_id", LongType())])
            delete_pks = deletes.select(
                F.from_json(F.col("before"), delete_schema).alias("before_data")
            ).select(F.col("before_data.user_id").alias("user_id"))
            pk_col = "user_id"
        elif entity == "orders":
            delete_schema = StructType([StructField("order_id", LongType())])
            delete_pks = deletes.select(
                F.from_json(F.col("before"), delete_schema).alias("before_data")
            ).select(F.col("before_data.order_id").alias("order_id"))
            pk_col = "order_id"
        elif entity == "payments":
            delete_schema = StructType([StructField("payment_id", LongType())])
            delete_pks = deletes.select(
                F.from_json(F.col("before"), delete_schema).alias("before_data")
            ).select(F.col("before_data.payment_id").alias("payment_id"))
            pk_col = "payment_id"
        else:
            raise ValueError(f"Unknown entity: {entity}")

        delete_pks.createOrReplaceTempView("_delete_pks")
        spark.sql(f"""
            DELETE FROM {table_name}
            WHERE {pk_col} IN (SELECT {pk_col} FROM _delete_pks)
        """)

    # Handle upserts: parse after JSON into Silver columns
    if upserts.count() > 0:
        if entity == "users":
            pk_col = "user_id"
            after_schema = StructType([
                StructField("user_id", LongType()),
                StructField("email", StringType()),
                StructField("status", StringType()),
                StructField("created_at", TimestampType()),
                StructField("updated_at", TimestampType()),
            ])
            parsed = upserts.select(
                F.from_json(F.col("after"), after_schema).alias("after_data"),
                F.col("event_uid"),
                F.col("ordering_key"),
                F.col("ts_ms"),
            ).select(
                F.col("after_data.user_id").alias("user_id"),
                F.col("after_data.email").alias("email"),
                F.col("after_data.status").alias("status"),
                F.col("after_data.created_at").alias("created_at"),
                F.col("after_data.updated_at").alias("updated_at"),
                F.col("event_uid").alias("_bronze_event_uid"),
                F.col("ordering_key").alias("_bronze_ordering_key"),
                F.col("ts_ms").cast("bigint").alias("_bronze_ts_ms"),
                F.lit(silver_updated_at).alias("_silver_updated_at"),
            )
        elif entity == "orders":
            pk_col = "order_id"
            after_schema = StructType([
                StructField("order_id", LongType()),
                StructField("user_id", LongType()),
                StructField("order_ts", TimestampType()),
                StructField("status", StringType()),
                StructField("total_amount", DecimalType(18, 2)),
                StructField("updated_at", TimestampType()),
            ])
            parsed = upserts.select(
                F.from_json(F.col("after"), after_schema).alias("after_data"),
                F.col("event_uid"),
                F.col("ordering_key"),
                F.col("ts_ms"),
            ).select(
                F.col("after_data.order_id").alias("order_id"),
                F.col("after_data.user_id").alias("user_id"),
                F.col("after_data.order_ts").alias("order_ts"),
                F.col("after_data.status").alias("status"),
                F.col("after_data.total_amount").alias("total_amount"),
                F.col("after_data.updated_at").alias("updated_at"),
                F.col("event_uid").alias("_bronze_event_uid"),
                F.col("ordering_key").alias("_bronze_ordering_key"),
                F.col("ts_ms").cast("bigint").alias("_bronze_ts_ms"),
                F.lit(silver_updated_at).alias("_silver_updated_at"),
            )
        elif entity == "payments":
            pk_col = "payment_id"
            after_schema = StructType([
                StructField("payment_id", LongType()),
                StructField("order_id", LongType()),
                StructField("amount", DecimalType(18, 2)),
                StructField("status", StringType()),
                StructField("failure_reason", StringType()),
                StructField("updated_at", TimestampType()),
            ])
            parsed = upserts.select(
                F.from_json(F.col("after"), after_schema).alias("after_data"),
                F.col("event_uid"),
                F.col("ordering_key"),
                F.col("ts_ms"),
            ).select(
                F.col("after_data.payment_id").alias("payment_id"),
                F.col("after_data.order_id").alias("order_id"),
                F.col("after_data.amount").alias("amount"),
                F.col("after_data.status").alias("status"),
                F.col("after_data.failure_reason").alias("failure_reason"),
                F.col("after_data.updated_at").alias("updated_at"),
                F.col("event_uid").alias("_bronze_event_uid"),
                F.col("ordering_key").alias("_bronze_ordering_key"),
                F.col("ts_ms").cast("bigint").alias("_bronze_ts_ms"),
                F.lit(silver_updated_at).alias("_silver_updated_at"),
            )
        else:
            raise ValueError(f"Unknown entity: {entity}")

        # MERGE INTO with ordering_key comparison
        parsed.createOrReplaceTempView("_upsert_source")

        # Build column list for UPDATE SET (all columns except PK)
        cols = [c for c in parsed.columns if c != pk_col]
        update_set = ", ".join([f"target.{c} = source.{c}" for c in cols])
        insert_cols = ", ".join(parsed.columns)
        insert_vals = ", ".join([f"source.{c}" for c in parsed.columns])

        merge_sql = f"""
            MERGE INTO {table_name} AS target
            USING _upsert_source AS source
            ON target.{pk_col} = source.{pk_col}
            WHEN MATCHED AND source._bronze_ordering_key > target._bronze_ordering_key
                THEN UPDATE SET {update_set}
            WHEN NOT MATCHED
                THEN INSERT ({insert_cols}) VALUES ({insert_vals})
        """
        spark.sql(merge_sql)


def run_batch(spark: SparkSession, cfg: SilverConfig) -> None:
    """
    Process one batch: read Bronze, dedupe, merge into Silver.
    This is idempotent: same Bronze window processed multiple times yields same Silver.
    """
    bronze_table = f"iceberg.{cfg.bronze_namespace}.{cfg.bronze_table}"
    bronze_df = spark.table(bronze_table)

    for entity in ["users", "orders", "payments"]:
        latest = build_latest_events_df(bronze_df, entity, spark)
        if latest.count() > 0:
            merge_entity(spark, cfg, entity, latest)


def run(cfg: SilverConfig | None = None) -> None:
    """Main entry: create tables, process Bronze -> Silver."""
    cfg = cfg or SilverConfig.from_env()
    spark = build_spark(cfg)
    ensure_silver_tables(spark, cfg)
    run_batch(spark, cfg)


if __name__ == "__main__":
    run()
