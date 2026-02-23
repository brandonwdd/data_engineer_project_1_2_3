"""Bronze ingest configuration."""
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Optional


DEFAULT_TOPICS = ",".join([
    "dbserver_docker.public.orders",
    "dbserver_docker.public.users",
    "dbserver_docker.public.payments",
])


@dataclass
class BronzeConfig:
    # Kafka
    kafka_bootstrap: str = "kafka:9092"
    topics: str = DEFAULT_TOPICS
    starting_offsets: str = "earliest"
    consumer_group: str = "project1-bronze-ingest"
    max_offsets_per_trigger: Optional[int] = None
    fail_on_data_loss: bool = True

    # Iceberg
    catalog_name: str = "iceberg"
    catalog_warehouse: str = "s3a://warehouse/iceberg"
    bronze_namespace: str = "bronze"
    bronze_table: str = "raw_cdc"
    checkpoint_location: str = "s3a://warehouse/checkpoints/bronze/raw_cdc"

    # S3/MinIO
    s3_endpoint: str = "http://minio:9000"
    s3_access_key: str = "minioadmin"
    s3_secret_key: str = "minioadmin"
    s3_path_style: bool = True

    # Paths
    project_root: str = "/app"
    contracts_dir: str = "contracts/cdc"

    # Streaming
    trigger_interval: str = "10 seconds"

    @classmethod
    def from_env(cls) -> BronzeConfig:
        root = os.environ.get("PROJECT_ROOT", "/app")
        return cls(
            kafka_bootstrap=os.environ.get("KAFKA_BOOTSTRAP", "kafka:9092"),
            topics=os.environ.get("KAFKA_TOPICS", DEFAULT_TOPICS),
            starting_offsets=os.environ.get("KAFKA_STARTING_OFFSETS", "earliest"),
            consumer_group=os.environ.get("KAFKA_GROUP", "project1-bronze-ingest"),
            max_offsets_per_trigger=_opt_int("MAX_OFFSETS_PER_TRIGGER"),
            fail_on_data_loss=os.environ.get("FAIL_ON_DATA_LOSS", "true").lower() == "true",
            catalog_warehouse=os.environ.get("ICEBERG_WAREHOUSE", "s3a://warehouse/iceberg"),
            checkpoint_location=os.environ.get(
                "BRONZE_CKPT", "s3a://warehouse/checkpoints/bronze/raw_cdc"
            ),
            s3_endpoint=os.environ.get("S3_ENDPOINT", "http://minio:9000"),
            s3_access_key=os.environ.get("S3_ACCESS_KEY", "minioadmin"),
            s3_secret_key=os.environ.get("S3_SECRET_KEY", "minioadmin"),
            project_root=root,
            contracts_dir=os.path.join(root, os.environ.get("CONTRACTS_DIR", "contracts/cdc")),
            trigger_interval=os.environ.get("TRIGGER_INTERVAL", "10 seconds"),
        )


def _opt_int(key: str) -> Optional[int]:
    v = os.environ.get(key)
    if v is None or v == "":
        return None
    try:
        return int(v)
    except ValueError:
        return None
