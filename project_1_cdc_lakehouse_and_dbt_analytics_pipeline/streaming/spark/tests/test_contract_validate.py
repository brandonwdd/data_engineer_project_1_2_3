"""
Unit tests for contract validation. Quality-first: invalid events must raise.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import pytest

# Assume run from project root; contracts at contracts/cdc
PROJECT_ROOT = Path(__file__).resolve().parents[3]
CONTRACTS_DIR = str(PROJECT_ROOT / "contracts" / "cdc")


from streaming.spark.bronze_ingest.contract_validate import (
    load_contracts,
    entity_from_topic,
    validate_event,
    ContractViolation,
)


def test_load_contracts() -> None:
    if not Path(CONTRACTS_DIR).is_dir():
        pytest.skip("contracts/cdc not found")
    c = load_contracts(CONTRACTS_DIR)
    assert "users" in c
    assert "orders" in c
    assert "payments" in c
    assert c["users"]["primary_key"] == ["user_id"]
    assert "source.lsn" in c["users"]["deterministic_ordering"]["ordering_keys_priority"]


def test_entity_from_topic() -> None:
    assert entity_from_topic("dbserver_docker.public.users") == "users"
    assert entity_from_topic("dbserver_docker.public.orders") == "orders"
    assert entity_from_topic("dbserver_docker.public.payments") == "payments"


def test_entity_from_topic_unknown_raises() -> None:
    with pytest.raises(ContractViolation) as ex:
        entity_from_topic("unknown.topic")
    assert "Unknown topic" in str(ex.value)


def test_validate_event_insert_ok() -> None:
    if not Path(CONTRACTS_DIR).is_dir():
        pytest.skip("contracts/cdc not found")
    contracts = load_contracts(CONTRACTS_DIR)
    envelope = {
        "op": "c",
        "ts_ms": 1736942400000,
        "source": {"db": "project1", "schema": "public", "table": "users", "lsn": 26930080},
        "before": None,
        "after": {"user_id": 1, "email": "u@x.com", "status": "active", "created_at": "...", "updated_at": "..."},
    }
    key = {"user_id": 1}
    validate_event("users", envelope, key, contracts["users"], "t|0|1")


def test_validate_event_delete_ok() -> None:
    if not Path(CONTRACTS_DIR).is_dir():
        pytest.skip("contracts/cdc not found")
    contracts = load_contracts(CONTRACTS_DIR)
    envelope = {
        "op": "d",
        "ts_ms": 1736942700000,
        "source": {"db": "project1", "schema": "public", "table": "orders", "lsn": 26930100},
        "before": {"order_id": 1, "user_id": 1, "status": "cancelled", "updated_at": "..."},
        "after": None,
    }
    key = {"order_id": 1}
    validate_event("orders", envelope, key, contracts["orders"], "t|0|2")


def test_validate_event_missing_op_raises() -> None:
    if not Path(CONTRACTS_DIR).is_dir():
        pytest.skip("contracts/cdc not found")
    contracts = load_contracts(CONTRACTS_DIR)
    envelope = {"ts_ms": 1, "source": {}}
    with pytest.raises(ContractViolation) as ex:
        validate_event("users", envelope, None, contracts["users"], "uid")
    assert "op" in str(ex.value).lower() or "required" in str(ex.value).lower()


def test_validate_event_insert_missing_after_raises() -> None:
    if not Path(CONTRACTS_DIR).is_dir():
        pytest.skip("contracts/cdc not found")
    contracts = load_contracts(CONTRACTS_DIR)
    envelope = {"op": "c", "ts_ms": 1, "source": {}, "before": None, "after": None}
    with pytest.raises(ContractViolation):
        validate_event("users", envelope, None, contracts["users"], "uid")


def test_validate_event_delete_after_not_null_raises() -> None:
    if not Path(CONTRACTS_DIR).is_dir():
        pytest.skip("contracts/cdc not found")
    contracts = load_contracts(CONTRACTS_DIR)
    envelope = {"op": "d", "ts_ms": 1, "source": {}, "before": {"order_id": 1}, "after": {"order_id": 1}}
    with pytest.raises(ContractViolation):
        validate_event("orders", envelope, None, contracts["orders"], "uid")
