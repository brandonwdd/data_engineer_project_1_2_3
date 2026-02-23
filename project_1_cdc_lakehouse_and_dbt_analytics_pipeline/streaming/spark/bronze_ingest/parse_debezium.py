"""Parse Debezium CDC events with contract validation."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

from .contract_validate import (
    load_contracts,
    entity_from_topic,
    validate_event,
    ContractViolation,
)


def _safe_int(v: Any) -> Optional[int]:
    if v is None:
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def _ts_ms_to_ordering_component(ts_ms: Optional[int]) -> str:
    if ts_ms is None:
        return "0"
    return str(ts_ms).zfill(20)


def build_event_uid(topic: str, partition: int, offset: int) -> str:
    return f"{topic}|{partition}|{offset}"


def parse_ordering_key(
    envelope: Dict[str, Any],
    partition: int,
    offset: int,
) -> str:
    """
    Deterministic ordering key per contract: source.lsn > after.updated_at > partition > offset.
    """
    parts: List[str] = []

    source = envelope.get("source") or {}
    lsn = _safe_int(source.get("lsn"))
    if lsn is not None:
        parts.append(f"lsn_{lsn:020d}")
    else:
        after = envelope.get("after") or {}
        up = after.get("updated_at")
        if up is not None:
            # ISO string or ms; normalize to comparable string
            if isinstance(up, (int, float)):
                parts.append(f"ts_{int(up):020d}")
            else:
                parts.append(f"ts_{str(up)[:26]}")
        else:
            parts.append("ts_0")

    parts.append(f"p{partition:06d}")
    parts.append(f"o{offset:020d}")
    return "|".join(parts)


def parse_entity_key(
    envelope: Dict[str, Any],
    key_payload: Optional[Dict[str, Any]],
    entity: str,
    pk_fields: List[str],
    op: str,
) -> str:
    """Extract entity key (PK values) from key or after/before."""
    after = envelope.get("after") or {}
    before = envelope.get("before") or {}
    key = key_payload or {}

    vals: List[str] = []
    for pk in pk_fields:
        v = (after if op != "d" else before).get(pk)
        if v is None:
            v = key.get(pk)
        if v is None:
            raise ValueError(f"entity_key: missing PK {pk} for entity={entity} op={op}")
        vals.append(str(v))
    return "|".join(vals)


def parse_single(
    topic: str,
    partition: int,
    offset: int,
    kafka_ts: Optional[int],
    key_raw: Optional[str],
    value_raw: str,
    contracts: Dict[str, Dict[str, Any]],
) -> Dict[str, Any]:
    """
    Parse one Kafka record into a Bronze row. Validates via contract; raises on violation.
    Returns dict with keys: event_uid, entity, entity_key, ordering_key, kafka_*, op, ts_ms,
    source, before, after, ingest_time (all as Python types for Spark Row).
    """
    envelope = json.loads(value_raw)
    key_payload = json.loads(key_raw) if key_raw else None

    entity = entity_from_topic(topic)
    contract = contracts.get(entity)
    if not contract:
        raise ContractViolation(f"No contract for entity: {entity}", entity)

    event_uid = build_event_uid(topic, partition, offset)
    validate_event(entity, envelope, key_payload, contract, event_uid)

    op = envelope.get("op", "")
    pk_fields = contract.get("primary_key", [])
    entity_key = parse_entity_key(envelope, key_payload, entity, pk_fields, op)
    ordering_key = parse_ordering_key(envelope, partition, offset)

    source_str = json.dumps(envelope.get("source")) if envelope.get("source") else None
    before_str = json.dumps(envelope["before"]) if envelope.get("before") is not None else None
    after_str = json.dumps(envelope["after"]) if envelope.get("after") is not None else None

    return {
        "event_uid": event_uid,
        "entity": entity,
        "entity_key": entity_key,
        "ordering_key": ordering_key,
        "kafka_topic": topic,
        "kafka_partition": partition,
        "kafka_offset": offset,
        "kafka_timestamp": kafka_ts,
        "op": op,
        "ts_ms": envelope.get("ts_ms"),
        "source": source_str,
        "before": before_str,
        "after": after_str,
        "ingest_time": datetime.now(timezone.utc),
    }


def parse_batch(
    rows: List[Tuple[str, int, int, Optional[int], Optional[str], str]],
    contracts: Dict[str, Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """Parse a batch of Kafka records. Validates each; fails fast on first violation."""
    out: List[Dict[str, Any]] = []
    for topic, partition, offset, kafka_ts, key_raw, value_raw in rows:
        row = parse_single(
            topic, partition, offset, kafka_ts, key_raw, value_raw, contracts
        )
        out.append(row)
    return out
