"""Read existing UC3 BACON/ATC events and verify ACRAM risk publications.

This module never creates contexts or input events. Only ACRAM risk writes
to the two configured existing output contexts are permitted in this process.
"""
from __future__ import annotations

import copy
import hashlib
import importlib
import json
import math
from pathlib import Path
import re
import threading
import time
from datetime import datetime, timezone
from urllib.parse import urlsplit

_ID = re.compile(r"^[0-9a-fA-F]{64}$")
_LOCK = threading.RLock()
_STATE = None
_ORIGINAL_PUT = None
_ORIGINAL_REQUEST = None
READBACK_ATTEMPTS = 10
READBACK_DELAY_SECONDS = 0.5
FINAL_FOLLOW_UP_PREFIX = "possible malware is present in the DuT"
_SECRET_KEYS = {"private_key", "public_key", "auth_public_key", "auth_id",
                "signature", "token", "authorization", "password", "credentials"}


def _now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _state():
    if _STATE is None:
        raise RuntimeError("UC3 ADI console is not initialized.")
    return _STATE


def _id(value):
    value = str(value).strip().strip('"').lower()
    if not _ID.fullmatch(value):
        raise ValueError("An ADI transaction/context ID must contain 64 hexadecimal characters.")
    return value


def _ids(value):
    values = value if isinstance(value, (list, tuple)) else [value]
    return list(dict.fromkeys(_id(item) for item in values))


def _safe(value):
    if isinstance(value, dict):
        return {str(k): _safe(v) for k, v in value.items() if str(k).lower() not in _SECRET_KEYS}
    if isinstance(value, (list, tuple)):
        return [_safe(item) for item in value]
    return value


def _entries(value):
    """Unwrap the SDK's direct records, history arrays, and response envelopes."""
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except ValueError:
            return
    if isinstance(value, list):
        for item in value:
            yield from _entries(item)
    elif isinstance(value, dict) and "error" not in value:
        if isinstance(value.get("data"), dict) and ("id" in value or "asset_id" in value):
            yield value
            return
        for key in ("transaction", "transactions", "context", "contexts", "payload",
                    "result", "results", "items", "data"):
            if key in value:
                yield from _entries(value[key])


def _token():
    s = _state()
    return s["jwt"].token(s["credentials"]["user_id"], s["credentials"]["private_key"])


def _audit(message):
    with _LOCK:
        with (_state()["run_dir"] / "adi-verification.log").open("a", encoding="utf-8") as output:
            output.write(f"[{_now()}] {message}\n")


def _record(record):
    s = _state()
    record = _safe(record)
    with _LOCK:
        with (s["run_dir"] / "transaction-receipts.jsonl").open("a", encoding="utf-8") as output:
            output.write(json.dumps(record, sort_keys=True) + "\n")
        s["records"].append(record)


def _validate_existing_context(label, aliases, output=False):
    s = _state()
    matches = []
    for context_id in aliases:
        response = s["api"].get_context_transaction(context_id, _token())
        for entry in _entries(response):
            identities = {str(entry.get(key, "")).lower() for key in ("id", "asset_id", "context_id")}
            if identities.intersection(aliases) and "context_data" in entry["data"]:
                matches.append(entry)
    if not matches:
        raise RuntimeError(f"Cannot read the existing {label} context from UC3 ADI. No context was created.")
    latest = max(matches, key=_timestamp)
    if output:
        writers = latest.get("metadata", {}).get("write_permissions")
        credentials = s["credentials"]
        identities = {credentials["user_id"], credentials.get("public_key", credentials["user_id"])}
        if isinstance(writers, list) and writers and not identities.intersection(writers):
            raise RuntimeError(f"The configured UC3 identity lacks write permission for the existing {label} context.")
    return latest


def _timestamp(entry):
    try:
        stamp = float(entry.get("timestamp", 0))
        return stamp if math.isfinite(stamp) else 0
    except (ValueError, TypeError):
        return 0


def _risk_kind(transaction):
    s = _state()
    data = transaction.get("data", {})
    context = str(transaction.get("context_id", "")).lower()
    if not isinstance(data, dict) or data.get("source") != "ACRAM":
        raise RuntimeError("UC3 console permits ACRAM risk publications only; input events are read-only.")
    typ = str(data.get("type", "")).lower()
    if context == s["outputs"]["component"] and "component" in typ and "risk" in typ:
        return "component"
    if context == s["outputs"]["aggregate"] and "aggregated" in typ and "risk" in typ:
        return "aggregate"
    raise RuntimeError("UC3 console rejected a write outside its existing risk output contexts.")


def _bounded_request(api, method, url, token, responseType="json", **kwargs):
    s = _state()
    if api.base_url.rstrip("/") != s["base_url"] or api.blockchain != "contextchain":
        raise RuntimeError("UC3 console rejected an unexpected ADI endpoint.")
    endpoint = s["base_url"] + "/contextchain/"
    if not url.startswith(endpoint):
        raise RuntimeError("UC3 console rejected an unexpected ADI request URL.")
    if method.upper() != "GET":
        if method.upper() != "PUT" or url != endpoint + "transaction":
            raise RuntimeError("UC3 console cannot create or modify contexts, users, indexes, or input events.")
        _risk_kind(kwargs.get("json", {}))
    kwargs.setdefault("timeout", (5, 12))
    return _ORIGINAL_REQUEST(api, method, url, token, responseType=responseType, **kwargs)


def _checked_put(api, transaction, token):
    s = _state()
    if api.base_url.rstrip("/") != s["base_url"] or api.blockchain != "contextchain":
        raise RuntimeError("UC3 console rejected a risk write to an unexpected ADI endpoint.")
    kind = _risk_kind(transaction)
    data = copy.deepcopy(transaction["data"])
    metadata = copy.deepcopy(transaction.get("metadata", {}))
    context = str(transaction["context_id"]).lower()
    stage = s["stage"]
    key = hashlib.sha256(json.dumps([context, data, metadata], sort_keys=True).encode()).hexdigest()
    response = _ORIGINAL_PUT(api, transaction, token)
    if isinstance(response, dict) and "error" in response:
        # Let create_transaction.m refresh an expired JWT and retry the same
        # signed payload; never claim this error dictionary is a transaction ID.
        s["pending_failures"][key] = stage
        return response
    try:
        if not isinstance(response, str):
            raise ValueError("Non-string ADI response")
        transaction_id = _id(response)
    except ValueError as exc:
        s["pending_failures"][key] = stage
        raise RuntimeError("ADI did not return a valid risk transaction ID.") from exc
    verified = False
    for attempt in range(READBACK_ATTEMPTS):
        stored = api.get_transaction(transaction_id, _token())
        verified = any(str(item.get("id", "")).lower() == transaction_id
                       and str(item.get("context_id", "")).lower() == context
                       and item.get("data") == data
                       and item.get("metadata", {}) == metadata for item in _entries(stored))
        if verified:
            break
        if attempt + 1 < READBACK_ATTEMPTS:
            time.sleep(READBACK_DELAY_SECONDS)
    _record({"timestamp": _now(), "stage": stage, "kind": kind,
             "transaction_id": transaction_id, "context_id": context,
             "verified": verified, "data": data, "metadata": metadata})
    if not verified:
        s["pending_failures"][key] = stage
        raise RuntimeError(f"ADI accepted risk {transaction_id}, but authenticated read-back did not verify it.")
    s["pending_failures"].pop(key, None)
    if kind == "aggregate":
        s["last_aggregate"] = {"data": data, "metadata": metadata}
    _audit(f"Risk stored and verified: stage={stage} kind={kind} transactionId={transaction_id}")
    return transaction_id


def initialize(config_path, run_dir):
    global _STATE, _ORIGINAL_PUT, _ORIGINAL_REQUEST
    if _STATE is not None:
        raise RuntimeError("UC3 console is already initialized in this Python process.")
    config_path = Path(str(config_path)).resolve()
    config = json.loads(config_path.read_text(encoding="utf-8-sig"))
    credentials_path = Path(config["credentialsFileName"])
    if not credentials_path.is_absolute():
        credentials_path = config_path.parent / credentials_path
    credentials = json.loads(credentials_path.read_text(encoding="utf-8-sig"))
    for key in ("websocket_address", "user_id", "private_key"):
        if not isinstance(credentials.get(key), str) or not credentials[key]:
            raise ValueError(f"UC3 credentials missing {key}.")
    address = urlsplit(credentials["websocket_address"])
    if address.scheme not in {"ws", "wss"} or not address.hostname or address.username or address.password:
        raise ValueError("Invalid UC3 websocket_address.")
    base_url = ("https://" if address.scheme == "wss" else "http://") + address.netloc
    contexts = {kind: _ids(config["adiInputContexts"][kind]) for kind in ("bacon", "atc")}
    outputs = {"component": _id(credentials["context_id_component"]),
               "aggregate": _id(credentials["context_id_aggregated"])}
    if set(contexts["bacon"]).intersection(contexts["atc"]) or set(outputs.values()).intersection(contexts["bacon"] + contexts["atc"]):
        raise ValueError("UC3 input and risk output contexts must be distinct.")
    destination = Path(str(run_dir)).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    if (destination / "transaction-receipts.jsonl").exists():
        raise RuntimeError("Use a fresh run directory to preserve transaction receipts.")
    api_class = importlib.import_module("contextchain.api").API
    jwt_class = importlib.import_module("contextchain.jwt").JWT
    _ORIGINAL_REQUEST = api_class._send_request
    _ORIGINAL_PUT = api_class.put_transaction
    _STATE = {"config": config, "credentials": credentials, "contexts": contexts,
              "outputs": outputs, "base_url": base_url, "api_class": api_class,
              "api": api_class(base_url, "contextchain"), "jwt": jwt_class,
              "run_dir": destination, "records": [], "stage": "setup", "pending_failures": {}}
    api_class._send_request = _bounded_request
    api_class.put_transaction = _checked_put
    try:
        for kind, aliases in contexts.items():
            _validate_existing_context(kind.upper(), aliases)
        for kind, context_id in outputs.items():
            _validate_existing_context(kind + " risk", [context_id], output=True)
    except Exception:
        restore()
        raise
    _audit(f"Existing UC3 contexts validated: endpoint={base_url}")
    return True


def _input_matches(transaction, aliases, expected_id=None):
    data = transaction.get("data", {})
    transaction_id = str(transaction.get("id", "")).lower()
    return (bool(_ID.fullmatch(transaction_id))
            and (expected_id is None or transaction_id == expected_id)
            and str(transaction.get("context_id", "")).lower() in aliases
            and isinstance(data, dict) and "context_data" not in data
            and ("severity" in data or "value" in data))


def read_inputs():
    """Read exact existing transactions; do not manufacture or submit inputs."""
    s = _state()
    result = []
    preferred = s["config"].get("uc3StoredTransactions", {})
    for kind in ("bacon", "atc"):
        aliases = s["contexts"][kind]
        explicit = preferred.get(kind)
        if explicit:
            transaction_id = _id(explicit)
            candidates = [item for item in _entries(s["api"].get_transaction(transaction_id, _token()))
                          if _input_matches(item, aliases, transaction_id)]
        else:
            candidates = []
            for context_id in aliases:
                candidates.extend(item for item in _entries(s["api"].get_transactions_by_context_id(context_id, _token()))
                                  if _input_matches(item, aliases))
        if not candidates:
            raise RuntimeError(f"No readable stored {kind.upper()} transaction was found in its configured context. No input was created.")
        selected = max(candidates, key=lambda item: (_timestamp(item), str(item.get("id", ""))))
        # Independently confirm the selected record by its immutable ID.
        actual = [item for item in _entries(s["api"].get_transaction(selected["id"], _token()))
                  if _input_matches(item, aliases, selected["id"])
                  and item["data"] == selected["data"]]
        if not actual:
            raise RuntimeError(f"Stored {kind.upper()} transaction could not be verified by ID.")
        result.append({"kind": kind, "transaction": _safe(actual[0])})
    # Commit receipts only after both inputs have been found successfully.
    for item in result:
        transaction = item["transaction"]
        _record({"timestamp": _now(), "stage": item["kind"], "kind": "input",
                 "transaction_id": transaction["id"], "context_id": transaction["context_id"],
                 "verified": True, "transport": "stored-transaction-readback", "data": transaction["data"]})
        (s["run_dir"] / (item["kind"] + "-input.json")).write_text(json.dumps(transaction, indent=2) + "\n", encoding="utf-8")
    return json.dumps(result)


def set_stage(stage):
    stage = str(stage)
    if stage not in {"setup", "baseline", "bacon", "atc", "final", "monitoring"}:
        raise ValueError("Unknown UC3 risk stage.")
    _state()["stage"] = stage


def publish_final_summary():
    """Publish the final aggregate with its requested follow-up annotation.

    A final summary is explicit because ATC may leave numeric risk unchanged.
    Re-sign a new risk transaction; never alter an already signed payload.
    """
    s = _state()
    if "final_summary" in s:
        return json.dumps(s["final_summary"])
    if s["stage"] not in {"atc", "final"}:
        raise RuntimeError("The final UC3 summary follows the stored BACON/ATC sequence.")
    save_summary()  # A prior failed publication must not be covered by a summary.
    if "last_aggregate" not in s:
        raise RuntimeError("No verified aggregate risk is available for the final summary.")
    previous = copy.deepcopy(s["last_aggregate"])
    metadata = previous["metadata"]
    field = "follow_up_actions"
    if field not in metadata and "follow-up-actions" in metadata:
        field = "follow-up-actions"
    existing = str(metadata.get(field, ""))
    if not existing.startswith(FINAL_FOLLOW_UP_PREFIX):
        metadata[field] = FINAL_FOLLOW_UP_PREFIX + (". " + existing if existing else "")
    # Preserve the risk values and their original calculation timestamp.
    transaction_class = importlib.import_module("contextchain.transaction").Transaction
    credentials = s["credentials"]
    transaction = transaction_class.make_create_transaction(
        s["outputs"]["aggregate"], previous["data"], metadata,
        credentials["user_id"], credentials.get("public_key") or credentials["user_id"])
    signed = transaction_class.sign_transaction(transaction, credentials["private_key"])
    set_stage("final")
    for attempt in range(2):
        response = s["api"].put_transaction(signed, _token())
        if isinstance(response, dict) and "error" in response:
            if attempt == 0 and re.search(r"(?<!\d)401(?!\d)", str(response.get("error", ""))):
                continue
            raise RuntimeError("ADI rejected the final UC3 risk summary.")
        transaction_id = _id(response)
        break
    result = {"transaction_id": transaction_id, "data": previous["data"],
              "metadata": metadata, "verified": True}
    s["final_summary"] = _safe(result)
    (s["run_dir"] / "final-aggregate.json").write_text(
        json.dumps(_safe(result), indent=2) + "\n", encoding="utf-8")
    save_summary()
    return json.dumps(_safe(result))


def assert_stage(stage, min_components=1, min_aggregates=1):
    records = [r for r in _state()["records"] if r["stage"] == str(stage) and r["verified"]]
    components = sum(r["kind"] == "component" for r in records)
    aggregates = sum(r["kind"] == "aggregate" for r in records)
    if components < int(min_components) or aggregates < int(min_aggregates):
        raise RuntimeError(f"Incomplete {stage} publication: {components} component and {aggregates} aggregate risks verified.")
    return True


def summary_json():
    s = _state()
    summary = {"timestamp": _now(), "endpoint": s["base_url"], "stages": {}}
    for stage in ("baseline", "bacon", "atc", "final", "monitoring"):
        records = [r for r in s["records"] if r["stage"] == stage]
        summary["stages"][stage] = {
            "verified_components": sum(r["kind"] == "component" and r["verified"] for r in records),
            "verified_aggregates": sum(r["kind"] == "aggregate" and r["verified"] for r in records),
            "verified_inputs": sum(r["kind"] == "input" and r["verified"] for r in records)}
    return json.dumps(summary, indent=2)


def save_summary():
    s = _state()
    (s["run_dir"] / "live-summary.json").write_text(summary_json() + "\n", encoding="utf-8")
    if s["pending_failures"]:
        raise RuntimeError("One or more UC3 risk publications failed; see the actual console errors and saved receipts.")
    return True


def restore():
    global _STATE, _ORIGINAL_PUT, _ORIGINAL_REQUEST
    if _STATE is not None:
        _STATE["api_class"].put_transaction = _ORIGINAL_PUT
        _STATE["api_class"]._send_request = _ORIGINAL_REQUEST
    _STATE = None
    _ORIGINAL_PUT = None
    _ORIGINAL_REQUEST = None
