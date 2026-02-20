"""
Parse Bronze events into Silver rows. Extract fields from after/before JSON.
"""
from __future__ import annotations

import json
from typing import Any, Dict, List, Optional

from pyspark.sql import Row


def parse_after_to_silver_row(
    entity: str,
    after_json: str,
    event_uid: str,
    ordering_key: str,
    ts_ms: int,
    silver_updated_at: Any,
) -> Dict[str, Any]:
    """
    Parse 'after' JSON into Silver row fields. Returns dict for Spark Row.
    """
    after = json.loads(after_json) if after_json else {}
    row: Dict[str, Any] = {}

    if entity == "users":
        row = {
            "user_id": after.get("user_id"),
            "email": after.get("email"),
            "status": after.get("status"),
            "created_at": after.get("created_at"),
            "updated_at": after.get("updated_at"),
        }
    elif entity == "orders":
        row = {
            "order_id": after.get("order_id"),
            "user_id": after.get("user_id"),
            "order_ts": after.get("order_ts"),
            "status": after.get("status"),
            "total_amount": after.get("total_amount"),
            "updated_at": after.get("updated_at"),
        }
    elif entity == "payments":
        row = {
            "payment_id": after.get("payment_id"),
            "order_id": after.get("order_id"),
            "amount": after.get("amount"),
            "status": after.get("status"),
            "failure_reason": after.get("failure_reason"),
            "updated_at": after.get("updated_at"),
        }
    else:
        raise ValueError(f"Unknown entity: {entity}")

    # Add audit fields
    row["_bronze_event_uid"] = event_uid
    row["_bronze_ordering_key"] = ordering_key
    row["_bronze_ts_ms"] = ts_ms
    row["_silver_updated_at"] = silver_updated_at

    return row


def extract_entity_key_from_row(bronze_row: Row, entity: str) -> Any:
    """Extract primary key value from Bronze row for MERGE matching."""
    entity_key_str = bronze_row.entity_key
    if entity in ("users", "orders", "payments"):
        # Single-column PK
        return int(entity_key_str.split("|")[0])
    return entity_key_str


def build_latest_events_df(
    bronze_df: Any,
    entity: str,
    spark: Any,
) -> Any:
    """
    From Bronze events, keep only the latest event per entity_key (by ordering_key).
    Returns DataFrame with columns: entity_key, op, after, before, event_uid, ordering_key, ts_ms.
    """
    from pyspark.sql import functions as F
    from pyspark.sql.window import Window

    entity_events = bronze_df.filter(bronze_df.entity == entity)

    window = Window.partitionBy("entity_key").orderBy(F.desc("ordering_key"))
    latest = (
        entity_events.withColumn("_rn", F.row_number().over(window))
        .filter(F.col("_rn") == 1)
        .drop("_rn")
    )

    return latest.select(
        "entity_key",
        "op",
        "after",
        "before",
        "event_uid",
        "ordering_key",
        "ts_ms",
    )
