"""Bronze ingest job from Kafka to Iceberg."""
from __future__ import annotations

from typing import Any, Iterator, Optional

import pandas as pd

from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    LongType,
    IntegerType,
    TimestampType,
)

from .config import BronzeConfig
from .contract_validate import load_contracts
from .parse_debezium import parse_batch


def bronze_schema() -> StructType:
    return StructType([
        StructField("event_uid", StringType(), False),
        StructField("entity", StringType(), False),
        StructField("entity_key", StringType(), False),
        StructField("ordering_key", StringType(), False),
        StructField("kafka_topic", StringType(), False),
        StructField("kafka_partition", IntegerType(), False),
        StructField("kafka_offset", LongType(), False),
        StructField("kafka_timestamp", LongType(), True),
        StructField("op", StringType(), False),
        StructField("ts_ms", LongType(), True),
        StructField("source", StringType(), True),
        StructField("before", StringType(), True),
        StructField("after", StringType(), True),
        StructField("ingest_time", TimestampType(), False),
    ])


def build_spark(cfg: BronzeConfig) -> SparkSession:
    builder = (
        SparkSession.builder.appName("project1-bronze-ingest")
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.iceberg.type", "hadoop")
        .config("spark.sql.catalog.iceberg.warehouse", cfg.catalog_warehouse)
        .config("spark.sql.defaultCatalog", "iceberg")
    )

    # S3A / MinIO
    endpoint = cfg.s3_endpoint
    builder = (
        builder.config("spark.hadoop.fs.s3a.endpoint", endpoint)
        .config("spark.hadoop.fs.s3a.access.key", cfg.s3_access_key)
        .config("spark.hadoop.fs.s3a.secret.key", cfg.s3_secret_key)
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    )

    return builder.getOrCreate()


def ensure_bronze_table(spark: SparkSession, cfg: BronzeConfig) -> None:
    ns = cfg.bronze_namespace
    tbl = cfg.bronze_table
    full = f"iceberg.{ns}.{tbl}"

    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS iceberg.{ns}")
    spark.sql(f"""
        CREATE TABLE IF NOT EXISTS {full} (
            event_uid       STRING   NOT NULL,
            entity          STRING   NOT NULL,
            entity_key      STRING   NOT NULL,
            ordering_key    STRING   NOT NULL,
            kafka_topic     STRING   NOT NULL,
            kafka_partition INT      NOT NULL,
            kafka_offset    BIGINT   NOT NULL,
            kafka_timestamp BIGINT,
            op              STRING   NOT NULL,
            ts_ms           BIGINT,
            source          STRING,
            before          STRING,
            after           STRING,
            ingest_time     TIMESTAMP NOT NULL
        )
        USING iceberg
        PARTITIONED BY (days(ingest_time))
        TBLPROPERTIES (
            'format-version' = '2',
            'write.parquet.compression-codec' = 'snappy'
        )
    """)


def _decode(b: Optional[bytes]) -> Optional[str]:
    if b is None:
        return None
    return b.decode("utf-8", errors="replace")


def _map_batch(
    it: Iterator[pd.DataFrame],
    contracts_dir: str,
) -> Iterator[pd.DataFrame]:
    contracts = load_contracts(contracts_dir)
    for pdf in it:
        batch: list[tuple[str, int, int, Optional[int], Optional[str], str]] = []
        for _, r in pdf.iterrows():
            topic = str(r["topic"])
            partition = int(r["partition"])
            offset = int(r["offset"])
            ts = r["timestamp"]
            kafka_ts = int(ts.timestamp() * 1000) if pd.notna(ts) and ts is not None else None
            key_raw = _decode(r["key"]) if r.get("key") is not None else None
            raw_val = r["value"]
            value_raw = _decode(raw_val) if raw_val is not None else None
            if not value_raw:
                raise ValueError("Empty or null Kafka value (tombstone?)")
            batch.append((topic, partition, offset, kafka_ts, key_raw, value_raw))
        if not batch:
            yield pd.DataFrame()
            continue
        rows = parse_batch(batch, contracts)
        if not rows:
            yield pd.DataFrame()
            continue
        yield pd.DataFrame(rows)


def run(cfg: Optional[BronzeConfig] = None) -> None:
    cfg = cfg or BronzeConfig.from_env()
    spark = build_spark(cfg)

    ensure_bronze_table(spark, cfg)

    kafka = (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", cfg.kafka_bootstrap)
        .option("subscribe", cfg.topics)
        .option("startingOffsets", cfg.starting_offsets)
        .option("failOnDataLoss", str(cfg.fail_on_data_loss).lower())
    )
    if cfg.max_offsets_per_trigger is not None:
        kafka = kafka.option("maxOffsetsPerTrigger", cfg.max_offsets_per_trigger)

    stream = kafka.load()

    contracts_dir = cfg.contracts_dir
    schema = bronze_schema()

    def mapper(it: Iterator[pd.DataFrame]) -> Iterator[pd.DataFrame]:
        return _map_batch(it, contracts_dir)

    parsed = stream.mapInPandas(mapper, schema)

    full_table = f"iceberg.{cfg.bronze_namespace}.{cfg.bronze_table}"
    q = (
        parsed.writeStream.format("iceberg")
        .outputMode("append")
        .option("checkpointLocation", cfg.checkpoint_location)
        .option("fanout-enabled", "true")
        .trigger(processingTime=cfg.trigger_interval)
        .toTable(full_table)
    )
    q.awaitTermination()


if __name__ == "__main__":
    run()
