"""Silver merge configuration."""
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Optional


@dataclass
class SilverConfig:
    # Iceberg
    catalog_name: str = "iceberg"
    catalog_warehouse: str = "s3a://warehouse/iceberg"
    bronze_namespace: str = "bronze"
    bronze_table: str = "raw_cdc"
    silver_namespace: str = "silver"

    # S3/MinIO (same as Bronze)
    s3_endpoint: str = "http://minio:9000"
    s3_access_key: str = "minioadmin"
    s3_secret_key: str = "minioadmin"
    s3_path_style: bool = True

    # Processing
    project_root: str = "/app"
    contracts_dir: str = "contracts/cdc"
    checkpoint_location: str = "s3a://warehouse/checkpoints/silver/merge"

    # Window / batch size
    window_duration: str = "1 minute"
    max_files_per_batch: Optional[int] = None

    @classmethod
    def from_env(cls) -> SilverConfig:
        root = os.environ.get("PROJECT_ROOT", "/app")
        return cls(
            catalog_warehouse=os.environ.get("ICEBERG_WAREHOUSE", "s3a://warehouse/iceberg"),
            checkpoint_location=os.environ.get(
                "SILVER_CKPT", "s3a://warehouse/checkpoints/silver/merge"
            ),
            s3_endpoint=os.environ.get("S3_ENDPOINT", "http://minio:9000"),
            s3_access_key=os.environ.get("S3_ACCESS_KEY", "minioadmin"),
            s3_secret_key=os.environ.get("S3_SECRET_KEY", "minioadmin"),
            project_root=root,
            contracts_dir=os.path.join(root, os.environ.get("CONTRACTS_DIR", "contracts/cdc")),
            window_duration=os.environ.get("SILVER_WINDOW_DURATION", "1 minute"),
        )
