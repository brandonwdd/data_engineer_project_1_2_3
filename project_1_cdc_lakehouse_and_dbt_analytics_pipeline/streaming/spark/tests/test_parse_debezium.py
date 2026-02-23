"""Unit tests for Debezium parsing utilities."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[3]
CONTRACTS_DIR = str(PROJECT_ROOT / "contracts" / "cdc")
FIXTURES = Path(__file__).resolve().parent / "fixtures"

from streaming.spark.bronze_ingest.contract_validate import load_contracts
from streaming.spark.bronze_ingest.parse_debezium import (
    build_event_uid,
    parse_ordering_key,
    parse_entity_key,
    parse_single,
    parse_batch,
)


def _load_fixture(name: str) -> dict:
    p = FIXTURES / name
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)


def test_build_event_uid() -> None:
    assert build_event_uid("t", 0, 1) == "t|0|1"
    assert build_event_uid("dbserver_docker.public.users", 2, 100) == "dbserver_docker.public.users|2|100"


def test_parse_ordering_key_with_lsn() -> None:
    envelope = {"source": {"lsn": 26930080}, "after": {"updated_at": "2026-01-15T12:00:00Z"}}
    key = parse_ordering_key(envelope, 0, 1)
    assert "lsn_" in key
    assert "p000000" in key
    assert "o00000000000000000001" in key


def test_parse_ordering_key_fallback_updated_at() -> None:
    envelope = {"source": {}, "after": {"updated_at": "2026-01-15T12:00:00Z"}}
    key = parse_ordering_key(envelope, 1, 2)
    assert "ts_" in key
    assert "p000001" in key


def test_parse_entity_key_from_after() -> None:
    envelope = {"after": {"user_id": 1}, "before": None}
    key = parse_entity_key(envelope, None, "users", ["user_id"], "c")
    assert key == "1"


def test_parse_entity_key_from_before_delete() -> None:
    envelope = {"after": None, "before": {"order_id": 99}}
    key = parse_entity_key(envelope, None, "orders", ["order_id"], "d")
    assert key == "99"


def test_parse_single_insert() -> None:
    if not Path(CONTRACTS_DIR).is_dir():
        pytest.skip("contracts/cdc not found")
    value = _load_fixture("users_cdc_value.json")
    key = _load_fixture("users_cdc_key.json")
    contracts = load_contracts(CONTRACTS_DIR)
    row = parse_single(
        "dbserver_docker.public.users",
        0, 1, 1736942400000,
        json.dumps(key),
        json.dumps(value),
        contracts,
    )
    assert row["event_uid"] == "dbserver_docker.public.users|0|1"
    assert row["entity"] == "users"
    assert row["entity_key"] == "1"
    assert "ordering_key" in row
    assert row["op"] == "c"
    assert row["ts_ms"] == 1736942400000
    assert row["ingest_time"] is not None


def test_parse_batch() -> None:
    if not Path(CONTRACTS_DIR).is_dir():
        pytest.skip("contracts/cdc not found")
    value = _load_fixture("users_cdc_value.json")
    key = _load_fixture("users_cdc_key.json")
    contracts = load_contracts(CONTRACTS_DIR)
    batch = [
        ("dbserver_docker.public.users", 0, 1, 1736942400000, json.dumps(key), json.dumps(value)),
    ]
    rows = parse_batch(batch, contracts)
    assert len(rows) == 1
    assert rows[0]["entity"] == "users"


def test_parse_single_unknown_topic_raises() -> None:
    if not Path(CONTRACTS_DIR).is_dir():
        pytest.skip("contracts/cdc not found")
    contracts = load_contracts(CONTRACTS_DIR)
    value = {"op": "c", "ts_ms": 1, "source": {}, "after": {"user_id": 1}}
    with pytest.raises(Exception):
        parse_single("unknown.topic", 0, 1, None, None, json.dumps(value), contracts)
