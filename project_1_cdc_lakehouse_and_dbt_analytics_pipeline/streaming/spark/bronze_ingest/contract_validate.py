"""
Contract validation for CDC events. Quality-first: fail fast on violation.
Loads contracts from YAML; validates required envelope fields, op, after/before, PK.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

# Topic -> entity mapping (dbserver_docker.public.users -> users)
TOPIC_TO_ENTITY = {
    "dbserver_docker.public.users": "users",
    "dbserver_docker.public.orders": "orders",
    "dbserver_docker.public.payments": "payments",
}

ALLOWED_OPS = {"c", "u", "d", "r"}


class ContractViolation(Exception):
    """Raised when a CDC event fails contract validation."""

    def __init__(self, msg: str, entity: str, event_uid: Optional[str] = None) -> None:
        self.entity = entity
        self.event_uid = event_uid
        super().__init__(msg)


def load_contracts(contracts_dir: str) -> Dict[str, Dict[str, Any]]:
    """Load all contract YAMLs from contracts_dir. Returns entity -> contract."""
    out: Dict[str, Dict[str, Any]] = {}
    p = Path(contracts_dir)
    if not p.is_dir():
        raise FileNotFoundError(f"Contracts dir not found: {contracts_dir}")
    for f in p.glob("*.yaml"):
        with open(f, "r", encoding="utf-8") as fp:
            doc = yaml.safe_load(fp)
        entity = doc.get("entity")
        if entity:
            out[entity] = doc
    return out


def entity_from_topic(topic: str) -> str:
    """Map Kafka topic to entity (users|orders|payments)."""
    e = TOPIC_TO_ENTITY.get(topic)
    if e is None:
        raise ContractViolation(f"Unknown topic (not in contract): {topic}", "?")
    return e


def validate_event(
    entity: str,
    envelope: Dict[str, Any],
    key_payload: Optional[Dict[str, Any]],
    contract: Dict[str, Any],
    event_uid: str,
) -> None:
    """
    Validate a single CDC event against contract. Raises ContractViolation on failure.
    """
    # Required envelope fields
    for f in contract.get("required_envelope_fields", []):
        if f not in envelope:
            raise ContractViolation(
                f"Missing required envelope field: {f}", entity, event_uid
            )

    op = envelope.get("op")
    if op not in ALLOWED_OPS:
        raise ContractViolation(
            f"Invalid op: {op!r}; allowed {ALLOWED_OPS}", entity, event_uid
        )

    rules = contract.get("payload_rules", {})
    after_req = set(rules.get("after_required_when_op", []))
    del_rules = rules.get("delete_rules", {})

    if op in after_req:
        if "after" not in envelope or envelope["after"] is None:
            raise ContractViolation(
                f"op={op} requires 'after'; missing or null", entity, event_uid
            )
    if op == "d":
        if del_rules.get("after_must_be_null") and envelope.get("after") is not None:
            raise ContractViolation(
                "op=d: after must be null", entity, event_uid
            )
        if del_rules.get("before_should_exist") and "before" not in envelope:
            raise ContractViolation(
                "op=d: before should exist", entity, event_uid
            )

    # Primary key must be derivable (from key or after/before)
    pk_fields = contract.get("primary_key", [])
    if not pk_fields:
        return

    after = envelope.get("after") or {}
    before = envelope.get("before") or {}
    key = key_payload or {}

    for pk in pk_fields:
        val = after.get(pk) if op != "d" else before.get(pk)
        if val is None:
            val = key.get(pk)
        if val is None:
            raise ContractViolation(
                f"Primary key '{pk}' not found in key/after/before", entity, event_uid
            )
