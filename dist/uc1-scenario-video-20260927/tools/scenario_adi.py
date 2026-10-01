"""Genuine UC1 ADI scenario transactions and authenticated, sanitized receipts.

Import into the same Python interpreter used by MATLAB create_transaction.m.
initialize() patches that interpreter's contextchain.API, never production files.
No private keys, tokens, signatures, or complete credentials are persisted.
"""
from __future__ import annotations

import copy
import importlib
import json
import math
from pathlib import Path
import re
import threading
import time
from datetime import datetime, timezone
from urllib.parse import urlsplit

UAM_CONTEXT = "2718e8975fa329947434f1ac88d9f07a1438195b9c50e22e6401d7c054237ec8"
_ID = re.compile(r"^[0-9a-fA-F]{64}$")
_LOCK = threading.RLock()
_STATE = None
_ORIGINAL_PUT = None
_ORIGINAL_REQUEST = None


def _now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _log(message):
    # Keep verification diagnostics alongside the receipts. MATLAB owns the
    # normal operator-facing transaction and WebSocket messages.
    s = _require_state()
    with _LOCK:
        with s["audit_path"].open("a", encoding="utf-8") as out:
            out.write(f"[{_now()}] {message}\n")


def _require_state():
    if _STATE is None:
        raise RuntimeError("Call scenario_adi.initialize() first.")
    return _STATE


def _transaction_id(response):
    # The SDK returns HTTP error dictionaries, which MATLAB must never mistake
    # for successful transaction IDs. Do not echo error bodies (may be secret).
    if not isinstance(response, str):
        raise RuntimeError("ADI did not return a transaction ID; response rejected.")
    candidate = response.strip().strip('"')
    if not _ID.fullmatch(candidate):
        raise RuntimeError("ADI response is not a 64-character hexadecimal transaction ID.")
    return candidate.lower()


def _token():
    s = _require_state()
    return s["jwt"].token(s["credentials"]["user_id"], s["credentials"]["private_key"])


def _object_response(value):
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except (ValueError, TypeError):
            return None
    if isinstance(value, dict) and "error" not in value:
        return value
    return None


def _unpack_transaction(value, expected_id=None, expected_context=None, expected_data=None, require_id=False):
    """Find the requested original transaction inside optional history lists."""
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except (ValueError, TypeError):
            return None
    if isinstance(value, list):
        for item in value:
            found = _unpack_transaction(item, expected_id, expected_context, expected_data, require_id)
            if found is not None:
                return found
        return None
    obj = _object_response(value)
    if obj is None:
        return None
    for key in ("transaction", "payload", "result", "transactions", "results", "items"):
        if key in obj:
            nested = _unpack_transaction(obj[key], expected_id, expected_context, expected_data, require_id)
            if nested is not None:
                return nested
    # A GET may omit context_id, but it must still return the exact data.
    if isinstance(obj.get("data"), dict):
        if require_id and str(obj.get("id", "")).lower() != expected_id:
            return None
        if expected_id is not None and "id" in obj and str(obj["id"]).lower() != expected_id:
            return None
        if expected_context is not None and "context_id" in obj and str(obj["context_id"]) != expected_context:
            return None
        if expected_data is not None and obj["data"] != expected_data:
            return None
        return obj
    return None


def _safe_data(data):
    """Recursively strip auth-bearing keys, including unexpected SDK fields."""
    if isinstance(data, dict):
        return {str(k): _safe_data(v) for k, v in data.items()
                if str(k).lower() not in {"private_key", "public_key", "auth_public_key", "auth_id", "signature", "token", "authorization", "password", "credentials"}}
    if isinstance(data, (list, tuple)):
        return [_safe_data(v) for v in data]
    return data


def _kind(transaction):
    data = transaction.get("data", {})
    if str(data.get("source", "")).upper() != "ACRAM":
        return "input"
    typ = str(data.get("type", "")).lower()
    if "component" in typ and "risk" in typ:
        return "component"
    if "aggregated" in typ and "risk" in typ:
        return "aggregate"
    return "other"


def _append_receipt(receipt):
    s = _require_state()
    with _LOCK:
        with s["receipt_path"].open("a", encoding="utf-8") as out:
            out.write(json.dumps(receipt, sort_keys=True, ensure_ascii=False) + "\n")
        s["records"].append(receipt)


def _checked_put(api, transaction, token):
    s = _require_state()
    if api.base_url.rstrip("/") != s["base_url"] or api.blockchain != "contextchain":
        raise RuntimeError("Scenario recorder rejected a PUT to an unexpected ADI endpoint.")
    with _LOCK:
        stage = s["stage"]
    data = copy.deepcopy(transaction.get("data", {}))
    context = str(transaction.get("context_id", ""))
    kind = _kind(transaction)
    txid = _transaction_id(_ORIGINAL_PUT(api, transaction, token))
    subject = data.get("subject", data.get("user-id", "system"))
    label = f"stage={stage} source={data.get('source', '')} kind={kind} subject={subject} value={data.get('value', '')} txid={txid}"
    _log("INFO ADI transaction accepted | " + label)
    # Confirm storage through an independently authenticated GET. Regenerate
    # JWT each time because the SDK's token lifetime is only ten seconds.
    verified = False
    for attempt in range(30):
        stored = _unpack_transaction(api.get_transaction(txid, _token()), txid, context, data)
        if stored is not None:
            same_context = "context_id" not in stored or str(stored["context_id"]) == context
            same_id = "id" not in stored or str(stored["id"]).lower() == txid
            if same_context and same_id and stored.get("data") == data:
                verified = True
                break
        if attempt < 29:
            time.sleep(0.5)
    receipt = {"timestamp": _now(), "scenario_id": s["scenario_id"], "stage": stage,
               "kind": kind, "source": data.get("source", ""), "transaction_id": txid,
               "context_id": context, "verified": verified, "data": _safe_data(data)}
    _append_receipt(receipt)
    if not verified:
        raise RuntimeError(f"ADI accepted transaction {txid}, but authenticated read-back did not verify its data.")
    _log("INFO ADI transaction persisted | " + label)
    return txid


def _context_entries(value):
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except (ValueError, TypeError):
            return
    if isinstance(value, list):
        for item in value:
            yield from _context_entries(item)
    elif isinstance(value, dict):
        if "error" in value:
            raise RuntimeError("ADI context discovery failed; no test transaction was sent.")
        if isinstance(value.get("data"), dict) and "context_data" in value["data"]:
            yield value
        else:
            for key in ("context", "transaction", "payload", "result", "contexts", "transactions", "results", "items", "data"):
                if key in value:
                    yield from _context_entries(value[key])


def _context_id(entry):
    # asset_id remains stable for an updated context; id identifies the version.
    for key in ("asset_id", "id", "context_id"):
        candidate = str(entry.get(key, ""))
        if _ID.fullmatch(candidate):
            return candidate.lower()
    return ""


def initialize(credentials_path, run_dir, scenario_id, sbom_context_id=""):
    """Read existing UC1 credentials, verify contexts, install the local SDK hook.

    No writes occur on ADI here. Context discovery never creates a context.
    A fresh run_dir is required if transaction-receipts.jsonl already exists.
    """
    global _STATE, _ORIGINAL_PUT, _ORIGINAL_REQUEST
    if _STATE is not None:
        raise RuntimeError("Scenario helper already initialized; use a fresh Python process.")
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,100}", str(scenario_id)):
        raise ValueError("scenario_id must be 1-100 letters, digits, dots, underscores or hyphens.")
    credentials = json.loads(Path(str(credentials_path)).read_text(encoding="utf-8-sig"))
    for key in ("websocket_address", "user_id", "private_key"):
        if not isinstance(credentials.get(key), str) or not credentials[key]:
            raise ValueError(f"UC1 credentials missing required field: {key}")
    address = urlsplit(credentials["websocket_address"])
    if address.scheme not in ("ws", "wss") or not address.hostname or address.username or address.password:
        raise ValueError("Invalid websocket_address in UC1 credentials.")
    scheme = "https" if address.scheme == "wss" else "http"
    # Match resolve_adi_connection.m for the Antonov/UC1 environment.
    base_url = f"{scheme}://{address.hostname}:83"
    output_dir = Path(str(run_dir)).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    receipt_path = output_dir / "transaction-receipts.jsonl"
    if receipt_path.exists():
        raise RuntimeError("Refusing to mix this recording with an existing receipt file.")
    api_class = importlib.import_module("contextchain.api").API
    transaction_class = importlib.import_module("contextchain.transaction").Transaction
    jwt_class = importlib.import_module("contextchain.jwt").JWT
    _ORIGINAL_REQUEST = api_class._send_request
    def bounded_request(self, method, url, token, responseType="json", **kwargs):
        kwargs.setdefault("timeout", (5, 12))
        return _ORIGINAL_REQUEST(self, method, url, token, responseType=responseType, **kwargs)
    api_class._send_request = bounded_request
    _STATE = {"credentials": credentials, "jwt": jwt_class, "transaction": transaction_class,
              "api": api_class(base_url, "contextchain"), "base_url": base_url,
              "scenario_id": str(scenario_id), "receipt_path": receipt_path,
              "audit_path": output_dir / "adi-verification.log",
              "stage": "setup", "records": []}
    try:
        contexts = list(_context_entries(_STATE["api"].get_context_transactions(_token())))
        explicit = str(sbom_context_id).strip().lower()
        if explicit and not _ID.fullmatch(explicit):
            raise ValueError("Explicit SBOM context must be a 64-character hexadecimal ID.")
        candidates = []
        for entry in contexts:
            schema = entry["data"]["context_data"]
            description = json.dumps({"schema": schema, "metadata": entry.get("metadata", {})}).lower()
            if "cve_list" in description or "cvelist" in description or "sbom" in description:
                cid = _context_id(entry)
                if cid:
                    candidates.append(cid)
        candidates = sorted(set(candidates))
        if explicit:
            # Context list may contain an updated version ID; read requested ID.
            context_history = list(_context_entries(_STATE["api"].get_context_transaction(explicit, _token())))
            matches = [entry for entry in context_history if explicit in
                       {str(entry.get(key, "")).lower() for key in ("id", "asset_id", "context_id")}]
            if not matches or not any("cve_list" in json.dumps(entry["data"]["context_data"]).lower()
                                      or "cvelist" in json.dumps(entry["data"]["context_data"]).lower()
                                      or "sbom" in json.dumps(entry["data"]["context_data"]).lower()
                                      for entry in matches):
                raise RuntimeError("Explicit SBOM context could not be read from UC1 ADI.")
            _STATE["sbom_context"] = explicit
        elif len(candidates) == 1:
            _STATE["sbom_context"] = candidates[0]
        elif not candidates:
            raise RuntimeError("No existing SBOM/CVE context found on UC1; supply the correct existing context ID.")
        else:
            raise RuntimeError("Multiple SBOM/CVE contexts found; supply the intended existing context ID.")
        uam_history = list(_context_entries(_STATE["api"].get_context_transaction(UAM_CONTEXT, _token())))
        if not any(UAM_CONTEXT in {str(entry.get(key, "")).lower() for key in ("id", "asset_id", "context_id")}
                   for entry in uam_history):
            raise RuntimeError("The existing UAM context could not be read from UC1 ADI.")
        _ORIGINAL_PUT = api_class.put_transaction
        api_class.put_transaction = _checked_put
    except Exception:
        api_class._send_request = _ORIGINAL_REQUEST
        _STATE = None
        raise
    _log(f"INFO ADI connection ready | endpoint={base_url} run={scenario_id} contexts=validated")
    return _STATE["sbom_context"]


def set_stage(stage):
    if str(stage) not in {"setup", "baseline", "sbom", "uam", "complete"}:
        raise ValueError("Unknown scenario stage.")
    with _LOCK:
        _require_state()["stage"] = str(stage)
    _log("INFO Risk stage started | stage=" + str(stage).upper())


def _send_fixture(context, data, metadata):
    s = _require_state()
    c = s["credentials"]
    transaction = s["transaction"].make_create_transaction(
        context, data, metadata, c["user_id"], c.get("public_key") or c["user_id"])
    signed = s["transaction"].sign_transaction(transaction, c["private_key"])
    return s["api"].put_transaction(signed, _token())


def send_sbom(subject):
    """Publish one clearly labelled synthetic CVE report for the chosen object."""
    s = _require_state()
    if s["stage"] != "sbom":
        raise RuntimeError("Set stage to sbom before submitting its fixture.")
    note = f"DEMONSTRATION FIXTURE; scenario_id={s['scenario_id']}; synthetic vulnerability for risk workflow; not a discovered production CVE."
    cve = {"vendor": "demonstration", "product": "uc1-scenario-fixture", "version": "1.0",
           "cve_number": "CVE-2099-00001", "severity": "HIGH", "score": "8.8", "source": "demonstration fixture",
           "cvss_version": "3.1", "cvss_vector": "CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:H",
           "paths": "scenario fixture", "remarks": "NewFound", "comments": note + " UI:R exercises the UAM user-behaviour risk pathway."}
    data = {"source": "SBOM Tool", "type": "CVE list", "value": "1", "subject": str(subject),
            "severity": "RED", "timestamp": _now(), "CVE_list": [cve]}
    return _send_fixture(s["sbom_context"], data, {"follow-up-actions": note})


def send_uam(user_id, value=0.89):
    s = _require_state()
    if s["stage"] != "uam":
        raise RuntimeError("Set stage to uam before submitting its fixture.")
    if not re.fullmatch(r"user-[1-9][0-9]*", str(user_id)):
        raise ValueError("UAM user ID must have the form user-N, starting at 1.")
    value = float(value)
    if not math.isfinite(value) or not 0 <= value <= 1:
        raise ValueError("UAM value must be a finite number between 0 and 1.")
    note = f"DEMONSTRATION FIXTURE; scenario_id={s['scenario_id']}; synthetic user anomaly for authorized risk workflow recording."
    data = {"source": "UAM", "type": "UAM user anomaly indicator", "user-id": str(user_id),
            "value": value, "severity": "RED" if value >= .66 else "YELLOW", "timestamp": _now()}
    return _send_fixture(UAM_CONTEXT, data, {"follow_up_actions": note})


def _verified(stage, kinds):
    with _LOCK:
        return [r for r in _require_state()["records"] if r["stage"] == str(stage) and r["verified"] and r["kind"] in kinds]


def read_input_json(stage, transaction_id):
    """Fetch a previously verified input through authenticated HTTP recovery.

    Return the actual stored transaction with auth fields removed. No receipt
    or WebSocket event is created, and missing fields are never reconstructed.
    """
    s = _require_state()
    stage = str(stage)
    if stage not in {"sbom", "uam"}:
        raise ValueError("HTTP recovery requires an SBOM or UAM input stage.")
    txid = _transaction_id(str(transaction_id))
    with _LOCK:
        matches = [r for r in s["records"]
                   if r.get("stage") == stage and r.get("kind") == "input"
                   and r.get("transaction_id") == txid and r.get("verified") is True]
        if len(matches) != 1:
            raise RuntimeError("HTTP recovery requires exactly one verified input receipt for this stage and transaction ID.")
        receipt = copy.deepcopy(matches[0])
    stored = _unpack_transaction(
        s["api"].get_transaction(txid, _token()), txid,
        receipt["context_id"], receipt["data"], require_id=True)
    if stored is None:
        raise RuntimeError("ADI HTTP recovery did not return the exact verified input transaction.")
    _log(f"INFO ADI input fetched | stage={stage} txid={txid} transport=authenticated-http storage=confirmed")
    return json.dumps(_safe_data(stored), sort_keys=True)


def verified_risk_count(stage):
    return len(_verified(stage, {"component", "aggregate"}))


def verified_component_count(stage):
    return len(_verified(stage, {"component"}))


def verified_aggregate_count(stage):
    return len(_verified(stage, {"aggregate"}))


def verified_ids_json(stage):
    return json.dumps([r["transaction_id"] for r in _verified(stage, {"input", "component", "aggregate"})])


def assert_stage(stage, min_components=1, min_aggregates=1):
    ncomponent = verified_component_count(stage)
    naggregate = verified_aggregate_count(stage)
    if ncomponent < int(min_components) or naggregate < int(min_aggregates):
        raise RuntimeError(f"Stage {stage} incomplete: only {ncomponent} verified component and {naggregate} verified aggregate risk transactions.")
    _log(f"INFO Risk publication complete | trigger={str(stage).upper()} component={ncomponent} aggregate={naggregate} storage=confirmed")
    return True


def summary_json():
    s = _require_state()
    summary = {"scenario_id": s["scenario_id"], "real_adi": True, "timestamp": _now(), "stages": {}}
    for stage in ("baseline", "sbom", "uam"):
        summary["stages"][stage] = {"verified_components": verified_component_count(stage),
                                     "verified_aggregates": verified_aggregate_count(stage),
                                     "verified_transaction_ids": json.loads(verified_ids_json(stage))}
    return json.dumps(summary, sort_keys=True)
