"""Network-free tests for stored UC3 input replay and verified risk writes.

The fake SDK exposes the real SDK method signatures, but its only transport is
an in-memory store. All identifiers and credentials in this file are fixtures.
Run from the repository root: py -3.12 -m unittest discover -s tests -p test_uc3_adi_console.py -v
"""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest import mock
from urllib.parse import parse_qs, urlsplit


ROOT = Path(__file__).resolve().parents[1]
BACON_CONTEXT = "c91f82042835e3265ca38a92bc3a49a80c23ab320066169308e18259f33a4168"
ATC_CONTEXT = "524e1931f88652a66acec6c0af1795a34d120bdce8cb058808093ea6d0bf953a"
ATC_VERSION = "d3ce45c86789793e43161697f1e89aff0439686db61bc60ce657cb89086d1e3a"
BACON_ID = "63116c06cde76a1ef38a8992d2b7dd8de86508967a3e78b28a987a3c0c54a703"
ATC_ID = "a" * 64
COMPONENT_CONTEXT = "b" * 64
AGGREGATE_CONTEXT = "c" * 64
IDENTITY = "d" * 64
PRIVATE_KEY = "TEST_PRIVATE_KEY_DO_NOT_SAVE"
TOKEN = "TEST_JWT_DO_NOT_SAVE"
BASE_URL = "http://uc3-tests.invalid:8080"
MALWARE_PREFIX = "possible malware is present in the DuT"


def context_record(context_id, version_id=None):
    return {
        "asset_id": context_id,
        "id": version_id or context_id,
        "timestamp": 1,
        "data": {"context_data": {
            "timestamp": {"type": "string"},
            "severity": {"type": "string"},
            "value": {"type": "number"},
            "root_cause": {"type": "string"},
            "traffic_participants": {"type": "string"},
            "involved_ports": {"type": "string"},
            "packets_exchanged": {"type": "number"},
        }, "context_metadata": {}},
        "metadata": {"name": "rMon", "read_permissions": [IDENTITY],
                     "write_permissions": [IDENTITY]},
    }


def bacon_record():
    return {
        "asset_id": BACON_ID, "id": BACON_ID,
        "context_id": BACON_CONTEXT, "timestamp": 1790360196614,
        "data": {
            "involved_ports": [61779, 8088], "packets_exchanged": 19,
            "severity": "ON", "source": "BACON",
            "subject": "Flow anomaly detection event",
            "supplementary-details": {
                "root_cause": "src_ip_type",
                "traffic_participants": ["163.162.228.6", "163.162.228.251"],
                "proto": "TCP", "client_bytes": "4742", "server_bytes": "3510",
                "dir": "C25", "flowstart_time": 1790360196,
            },
            "timestamp": "09/25 18:16:36.5746", "type": "anomaly", "value": 1,
        }, "metadata": {"follow-up-actions": ""},
    }


def atc_record(transaction_id=ATC_ID, timestamp=1790360197000):
    # The supplied ATC schema does not require a source or type field.
    return {
        "asset_id": transaction_id, "id": transaction_id,
        "context_id": ATC_CONTEXT, "timestamp": timestamp,
        "data": {
            "timestamp": "2026-09-25T18:16:37Z", "severity": "HIGH", "value": 0.8,
            "root_cause": "flow anomaly",
            "traffic_participants": "163.162.228.6,163.162.228.251",
            "involved_ports": "61779,8088", "packets_exchanged": 19,
        }, "metadata": {"follow-up-actions": ""},
    }


class UC3HelperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="uc3-helper-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run_dir = self.root / "run"
        self.calls = []
        self.put_responses = []
        self.readback_override = None
        self.created_payloads = []
        self.signed_payloads = []
        self.contexts = {
            BACON_CONTEXT: context_record(BACON_CONTEXT),
            ATC_CONTEXT: context_record(ATC_CONTEXT, ATC_VERSION),
            ATC_VERSION: context_record(ATC_CONTEXT, ATC_VERSION),
            COMPONENT_CONTEXT: context_record(COMPONENT_CONTEXT),
            AGGREGATE_CONTEXT: context_record(AGGREGATE_CONTEXT),
        }
        self.transactions = {BACON_ID: bacon_record(), ATC_ID: atc_record()}
        self.history = {
            BACON_CONTEXT: [bacon_record()],
            ATC_CONTEXT: [atc_record()],
            ATC_VERSION: [atc_record()],
        }
        fixture = self

        class API:
            def __init__(self, base_url, blockchain):
                self.base_url = base_url
                self.blockchain = blockchain

            def _send_request(self, method, url, token, responseType="json", **kwargs):
                fixture.calls.append({"method": method, "url": url, "kwargs": copy.deepcopy(kwargs)})
                path = urlsplit(url).path
                if method.upper() == "GET":
                    if "/contexts/" in path:
                        return copy.deepcopy(fixture.contexts.get(path.rsplit("/", 1)[-1], {"error": "Not found"}))
                    if path.endswith("/contexts"):
                        return copy.deepcopy(list(fixture.contexts.values()))
                    if path.endswith("/transactions"):
                        context_id = parse_qs(urlsplit(url).query).get("context_id", [""])[0]
                        return copy.deepcopy(fixture.history.get(context_id, []))
                    if "/transactions/" in path:
                        txid = path.rsplit("/", 1)[-1]
                        value = fixture.transactions.get(txid, {"error": "Not found"})
                        if fixture.readback_override and txid.startswith("e"):
                            value = fixture.readback_override(copy.deepcopy(value))
                        return copy.deepcopy(value)
                if method.upper() == "PUT" and path.endswith("/transaction"):
                    response = fixture.put_responses.pop(0) if fixture.put_responses else "e" + f"{len(fixture.transactions):063x}"
                    if isinstance(response, str) and len(response) == 64:
                        payload = copy.deepcopy(kwargs["json"])
                        payload["id"] = response
                        fixture.transactions[response] = payload
                    return response
                raise AssertionError(f"Unexpected fixture transport: {method} {url}")

            def get_context_transaction(self, context_id, token, dataspace_id=None):
                return self._send_request("GET", f"{self.base_url}/{self.blockchain}/contexts/{context_id}", token)

            def get_context_transactions(self, token, dataspace_id=None):
                return self._send_request("GET", f"{self.base_url}/{self.blockchain}/contexts", token)

            def get_transactions_by_context_id(self, context_id, token, dataspace_id=None):
                return self._send_request("GET", f"{self.base_url}/{self.blockchain}/transactions?context_id={context_id}", token)

            def get_state_transactions_by_context_id(self, context_id, token, dataspace_id=None):
                return self._send_request("GET", f"{self.base_url}/{self.blockchain}/state/transactions?context_id={context_id}", token)

            def get_transaction(self, transaction_id, token, dataspace_id=None):
                return self._send_request("GET", f"{self.base_url}/{self.blockchain}/transactions/{transaction_id}", token)

            def put_transaction(self, transaction, token):
                return self._send_request("PUT", f"{self.base_url}/{self.blockchain}/transaction", token,
                                          responseType="text", json=transaction,
                                          headers={"Content-Type": "application/json"})

            def put_context_transaction(self, transaction, token):
                return self._send_request("PUT", f"{self.base_url}/{self.blockchain}/context", token,
                                          responseType="text", json=transaction)

        class JWT:
            @staticmethod
            def token(user_id, private_key):
                fixture.assertEqual(user_id, IDENTITY)
                fixture.assertEqual(private_key, PRIVATE_KEY)
                return TOKEN

        class Transaction:
            @staticmethod
            def make_create_transaction(context_id, data, metadata, auth_user_id,
                                        auth_user_public_key, dataspace_id=None):
                fixture.assertEqual(auth_user_id, IDENTITY)
                fixture.assertEqual(auth_user_public_key, IDENTITY)
                transaction = {"context_id": context_id, "auth_id": auth_user_id,
                               "auth_public_key": auth_user_public_key}
                if data:
                    transaction["data"] = copy.deepcopy(data)
                if metadata:
                    transaction["metadata"] = copy.deepcopy(metadata)
                if dataspace_id:
                    transaction["dataspace_id"] = dataspace_id
                fixture.created_payloads.append(copy.deepcopy(transaction))
                return transaction

            @staticmethod
            def sign_transaction(transaction, private_key):
                fixture.assertEqual(private_key, PRIVATE_KEY)
                signed = copy.deepcopy(transaction)
                signed["signature"] = "TEST_FINAL_SIGNATURE_DO_NOT_SAVE"
                fixture.signed_payloads.append(copy.deepcopy(signed))
                return signed

        package = types.ModuleType("contextchain")
        package.__path__ = []
        modules = {"contextchain": package}
        for suffix, name, implementation in (("api", "API", API), ("jwt", "JWT", JWT),
                                            ("transaction", "Transaction", Transaction)):
            module = types.ModuleType(f"contextchain.{suffix}")
            setattr(module, name, implementation)
            setattr(package, suffix, module)
            modules[module.__name__] = module
        self.module_patch = mock.patch.dict(sys.modules, modules)
        self.module_patch.start()
        self.addCleanup(self.module_patch.stop)
        spec = importlib.util.spec_from_file_location("_uc3_adi_console_under_test", ROOT / "uc3_adi_console.py")
        self.helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.helper)
        self.addCleanup(self.helper.restore)
        self.API = API
        self.original_put = API.put_transaction
        self.original_request = API._send_request
        self.credentials = {
            "websocket_address": "ws://uc3-tests.invalid:8080/contextchain/ws",
            "user_id": IDENTITY, "private_key": PRIVATE_KEY,
            "context_id_component": COMPONENT_CONTEXT,
            "context_id_aggregated": AGGREGATE_CONTEXT,
        }
        self.credentials_path = self.root / "credentials.json"
        self.credentials_path.write_text(json.dumps(self.credentials), encoding="utf-8")
        self.config = {
            "env": "telco", "credentialsFileName": str(self.credentials_path),
            "adiInputContexts": {"bacon": [BACON_CONTEXT], "atc": [ATC_CONTEXT, ATC_VERSION]},
            "uc3StoredTransactions": {"bacon": BACON_ID, "atc": ""},
        }
        self.config_path = self.root / "config.json"

    def initialize(self):
        self.config_path.write_text(json.dumps(self.config), encoding="utf-8")
        self.helper.initialize(str(self.config_path), str(self.run_dir))
        self.api = self.API(BASE_URL, "contextchain")

    def input_records(self):
        value = self.helper.read_inputs()
        return json.loads(value) if isinstance(value, str) else value

    def risk(self, kind="component"):
        return {
            "context_id": COMPONENT_CONTEXT if kind == "component" else AGGREGATE_CONTEXT,
            "data": {"source": "ACRAM", "type": "Component risk" if kind == "component" else "Aggregated risk",
                     "subject": "UC3 asset", "severity": "ORANGE", "value": 0.7},
            "signature": "TEST_SIGNATURE_DO_NOT_SAVE", "auth_id": IDENTITY,
        }

    def receipt_records(self):
        path = self.run_dir / "transaction-receipts.jsonl"
        return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []

    def prepare_final_sequence(self, atc_aggregate=True, followup_key="follow_up_actions"):
        self.initialize()
        self.input_records()
        self.helper.set_stage("baseline")
        baseline = self.risk("aggregate")
        baseline["data"]["value"] = 0.1
        baseline["metadata"] = {followup_key: "Continue monitoring."}
        self.api.put_transaction(self.risk(), TOKEN)
        self.api.put_transaction(baseline, TOKEN)
        self.helper.set_stage("bacon")
        bacon = self.risk("aggregate")
        bacon["data"]["value"] = 0.6
        bacon["metadata"] = {followup_key: "Inspect BACON traffic. Preserve existing recommendations.",
                             "operator-note": "Retain diagnostic details"}
        self.api.put_transaction(bacon, TOKEN)
        self.helper.set_stage("atc")
        self.api.put_transaction(self.risk(), TOKEN)
        latest = bacon
        if atc_aggregate:
            atc = self.risk("aggregate")
            atc["data"]["value"] = 0.8
            atc["metadata"] = {followup_key: "Investigate ATC event. Retain the packet capture.",
                               "operator-note": "Retain diagnostic details"}
            self.api.put_transaction(atc, TOKEN)
            latest = atc
        return copy.deepcopy(latest)

    def final_summary(self):
        value = self.helper.publish_final_summary()
        return json.loads(value) if isinstance(value, str) else value

    def test_reads_exact_bacon_and_source_less_atc_without_writes(self):
        self.initialize()
        records = self.input_records()
        self.assertEqual([entry["kind"] for entry in records], ["bacon", "atc"])
        self.assertEqual(records[0]["transaction"], bacon_record())
        self.assertEqual(records[1]["transaction"], atc_record())
        self.assertTrue(self.calls)
        self.assertTrue(all(call["method"].upper() == "GET" for call in self.calls))
        self.assertTrue(all(call["kwargs"].get("timeout") for call in self.calls))

    def test_selects_newest_atc_data_event_and_excludes_schema(self):
        newer = atc_record("f" * 64, timestamp=1790360199000)
        schema = context_record(ATC_CONTEXT, ATC_VERSION)
        schema["timestamp"] = 9999999999999
        self.history[ATC_CONTEXT] = [atc_record(), schema, newer]
        self.history[ATC_VERSION] = [schema, atc_record()]
        self.transactions[newer["id"]] = newer
        self.initialize()
        records = self.input_records()
        self.assertEqual(records[1]["transaction"], newer)
        self.assertNotIn("source", records[1]["transaction"]["data"])

    def test_missing_atc_fails_before_any_risk_write(self):
        self.history[ATC_CONTEXT] = []
        self.history[ATC_VERSION] = [context_record(ATC_CONTEXT, ATC_VERSION)]
        self.initialize()
        with self.assertRaises((RuntimeError, ValueError)):
            self.input_records()
        self.assertFalse(any(call["method"].upper() != "GET" for call in self.calls))
        self.assertFalse(self.receipt_records(), "Both stored inputs must validate before any receipt is committed")

    def test_requested_bacon_id_does_not_fall_back_to_another_event(self):
        self.transactions.pop(BACON_ID)
        other = bacon_record()
        other["id"] = other["asset_id"] = "9" * 64
        self.history[BACON_CONTEXT] = [other]
        self.initialize()
        with self.assertRaises((RuntimeError, ValueError)):
            self.input_records()

    def test_requested_bacon_rejects_wrong_stored_id(self):
        self.transactions[BACON_ID]["id"] = "9" * 64
        self.initialize()
        with self.assertRaises((RuntimeError, ValueError)):
            self.input_records()

    def test_requested_bacon_rejects_wrong_stored_context(self):
        self.transactions[BACON_ID]["context_id"] = ATC_CONTEXT
        self.initialize()
        with self.assertRaises((RuntimeError, ValueError)):
            self.input_records()

    def test_missing_existing_context_restores_sdk_hooks(self):
        self.contexts.pop(COMPONENT_CONTEXT)
        with self.assertRaises((RuntimeError, ValueError)):
            self.initialize()
        self.assertIs(self.API.put_transaction, self.original_put)
        self.assertIs(self.API._send_request, self.original_request)
        self.assertFalse(any(call["method"].upper() != "GET" for call in self.calls))

    def test_component_and_aggregate_writes_are_read_back_and_counted(self):
        self.initialize()
        self.input_records()
        self.helper.set_stage("baseline")
        first = self.api.put_transaction(self.risk(), TOKEN)
        second = self.api.put_transaction(self.risk("aggregate"), TOKEN)
        self.assertNotEqual(first, second)
        self.helper.assert_stage("baseline", 1, 1)
        self.helper.save_summary()
        records = self.receipt_records()
        risks = [record for record in records if record.get("kind") in {"component", "aggregate"}]
        self.assertEqual(len(risks), 2)
        self.assertTrue(all(record["verified"] for record in risks))
        self.assertTrue(all(record["stage"] == "baseline" for record in risks))
        persisted = "\n".join(path.read_text(encoding="utf-8") for path in self.run_dir.rglob("*") if path.is_file())
        for secret in (PRIVATE_KEY, TOKEN, "TEST_SIGNATURE_DO_NOT_SAVE"):
            self.assertNotIn(secret, persisted)

    def test_refuses_input_nonrisk_and_wrong_output_context(self):
        self.initialize()
        invalid = [bacon_record(), atc_record(), self.risk(), self.risk("aggregate"), self.risk()]
        invalid[2]["context_id"] = AGGREGATE_CONTEXT
        invalid[3]["context_id"] = COMPONENT_CONTEXT
        invalid[4]["data"]["type"] = "unrelated ACRAM event"
        for payload in invalid:
            with self.subTest(payload=payload["data"].get("type", "ATC")):
                before = len(self.calls)
                with self.assertRaises((RuntimeError, ValueError)):
                    self.api.put_transaction(payload, TOKEN)
                self.assertEqual(len(self.calls), before)

    def test_transport_refuses_context_creation(self):
        self.initialize()
        before = len(self.calls)
        with self.assertRaises((RuntimeError, ValueError)):
            self.api.put_context_transaction(context_record("8" * 64), TOKEN)
        self.assertEqual(len(self.calls), before)

    def test_transport_refuses_unexpected_host_and_destructive_methods(self):
        self.initialize()
        before = len(self.calls)
        for api, method, url in (
            (self.API("http://other-tests.invalid", "contextchain"), "PUT", BASE_URL + "/contextchain/transaction"),
            (self.api, "GET", "http://other-tests.invalid/contextchain/transactions"),
            (self.api, "DELETE", BASE_URL + "/contextchain/transaction"),
            (self.api, "PUT", BASE_URL + "/contextchain/user"),
        ):
            with self.subTest(method=method, url=url):
                with self.assertRaises((RuntimeError, ValueError)):
                    api._send_request(method, url, TOKEN, json=self.risk())
        self.assertEqual(len(self.calls), before)

    def test_401_error_response_is_returned_unchanged_for_matlab_retry(self):
        self.initialize()
        error = {"error": "HTTP error occurred: 401 Client Error: Unauthorized"}
        self.put_responses.append(error)
        response = self.api.put_transaction(self.risk(), TOKEN)
        self.assertIs(response, error)
        self.assertFalse(any(record.get("verified") for record in self.receipt_records()))
        with self.assertRaises((RuntimeError, ValueError, AssertionError)):
            self.helper.assert_stage("baseline", 1, 1)
        with self.assertRaises(RuntimeError):
            self.helper.save_summary()

    def test_successful_retry_clears_only_its_failed_publication(self):
        self.initialize()
        self.helper.set_stage("bacon")
        payload = self.risk()
        error = {"error": "HTTP error occurred: 401 Client Error: Unauthorized"}
        self.put_responses.append(error)
        self.assertIs(self.api.put_transaction(payload, TOKEN), error)
        self.assertIsInstance(self.api.put_transaction(payload, TOKEN), str)
        self.helper.assert_stage("bacon", 1, 0)
        self.assertTrue(self.helper.save_summary())
        records = self.receipt_records()
        self.assertEqual(len(records), 1)
        self.assertTrue(records[0]["verified"])
        summary = json.loads((self.run_dir / "live-summary.json").read_text(encoding="utf-8"))
        self.assertEqual(summary["stages"]["bacon"]["verified_components"], 1)

    def test_wrong_readback_cannot_count_as_verified_success(self):
        self.initialize()
        self.helper.set_stage("baseline")
        self.readback_override = lambda record: dict(record, context_id=ATC_CONTEXT)
        with mock.patch.object(self.helper.time, "sleep"):
            with self.assertRaises((RuntimeError, ValueError)):
                self.api.put_transaction(self.risk(), TOKEN)
        with self.assertRaises((RuntimeError, ValueError, AssertionError)):
            self.helper.assert_stage("baseline", 1, 0)
        self.assertFalse(any(record.get("verified") for record in self.receipt_records()))

    def test_readback_requires_exact_transaction_id_and_data(self):
        self.initialize()
        self.helper.set_stage("atc")
        for changed in ("id", "data"):
            def mismatch(record):
                if changed == "id":
                    record["id"] = "7" * 64
                else:
                    record["data"]["value"] = 0.001
                return record

            self.readback_override = mismatch
            with self.subTest(changed=changed), mock.patch.object(self.helper.time, "sleep"):
                with self.assertRaises(RuntimeError):
                    self.api.put_transaction(self.risk(), TOKEN)
        self.assertFalse(any(record.get("verified") for record in self.receipt_records()))
        with self.assertRaises(RuntimeError):
            self.helper.assert_stage("atc", 1, 0)

    def test_selected_history_input_requires_matching_data_by_id(self):
        self.transactions[ATC_ID]["data"]["packets_exchanged"] = 999
        self.initialize()
        with self.assertRaises(RuntimeError):
            self.input_records()
        self.assertFalse(self.receipt_records())

    def test_receipts_strip_nested_secret_fields(self):
        self.initialize()
        self.helper.set_stage("baseline")
        risk = self.risk()
        risk["data"]["details"] = [{"Authorization": TOKEN, "private_key": PRIVATE_KEY, "keep": 3}]
        self.api.put_transaction(risk, TOKEN)
        records = self.receipt_records()
        self.assertEqual(records[0]["data"]["details"], [{"keep": 3}])
        persisted = (self.run_dir / "transaction-receipts.jsonl").read_text(encoding="utf-8")
        self.assertNotIn(TOKEN, persisted)
        self.assertNotIn(PRIVATE_KEY, persisted)

    def test_restore_restores_original_sdk_methods_and_is_idempotent(self):
        self.initialize()
        self.assertIsNot(self.API.put_transaction, self.original_put)
        self.assertIsNot(self.API._send_request, self.original_request)
        self.helper.restore()
        self.helper.restore()
        self.assertIs(self.API.put_transaction, self.original_put)
        self.assertIs(self.API._send_request, self.original_request)

    def test_final_summary_preserves_risk_and_prepends_exact_followup(self):
        latest = self.prepare_final_sequence()
        prior_transactions = copy.deepcopy(self.transactions)
        put_count = sum(call["method"] == "PUT" for call in self.calls)
        summary = self.final_summary()
        self.assertTrue(summary["verified"])
        self.assertEqual(summary["data"], latest["data"])
        self.assertEqual(summary["metadata"]["follow_up_actions"],
                         MALWARE_PREFIX + ". " + latest["metadata"]["follow_up_actions"])
        self.assertEqual(summary["metadata"]["operator-note"], latest["metadata"]["operator-note"])
        self.assertEqual(len(self.created_payloads), 1)
        self.assertEqual(len(self.signed_payloads), 1)
        self.assertEqual(self.created_payloads[0]["context_id"], AGGREGATE_CONTEXT)
        self.assertNotIn("input_id", self.created_payloads[0])
        self.assertNotIn(summary["transaction_id"], prior_transactions)
        self.assertEqual(sum(call["method"] == "PUT" for call in self.calls), put_count + 1)
        for transaction_id, transaction in prior_transactions.items():
            self.assertEqual(self.transactions[transaction_id], transaction)
        self.assertTrue(all(call["url"] == BASE_URL + "/contextchain/transaction"
                            and call["kwargs"]["json"]["context_id"] in {COMPONENT_CONTEXT, AGGREGATE_CONTEXT}
                            for call in self.calls if call["method"] == "PUT"))
        receipt = next(record for record in self.receipt_records() if record["stage"] == "final")
        self.assertEqual(receipt["kind"], "aggregate")
        self.assertTrue(receipt["verified"])
        self.assertEqual(receipt["metadata"], summary["metadata"])
        self.helper.assert_stage("final", 0, 1)
        self.assertTrue(self.helper.save_summary())
        persisted = "\n".join(path.read_text(encoding="utf-8") for path in self.run_dir.rglob("*") if path.is_file())
        self.assertNotIn("TEST_FINAL_SIGNATURE_DO_NOT_SAVE", persisted)

    def test_final_summary_uses_latest_bacon_aggregate_when_atc_publishes_none(self):
        latest = self.prepare_final_sequence(atc_aggregate=False)
        summary = self.final_summary()
        self.assertEqual(summary["data"], latest["data"])
        self.assertEqual(summary["data"]["value"], 0.6)
        self.assertEqual(summary["metadata"]["follow_up_actions"],
                         MALWARE_PREFIX + ". " + latest["metadata"]["follow_up_actions"])

    def test_final_summary_preserves_hyphenated_followup_key(self):
        latest = self.prepare_final_sequence(followup_key="follow-up-actions")
        summary = self.final_summary()
        self.assertNotIn("follow_up_actions", summary["metadata"])
        self.assertEqual(summary["metadata"]["follow-up-actions"],
                         MALWARE_PREFIX + ". " + latest["metadata"]["follow-up-actions"])

    def test_final_summary_is_idempotent(self):
        self.prepare_final_sequence()
        first = self.final_summary()
        calls_after_first = len(self.calls)
        second = self.final_summary()
        self.assertEqual(second, first)
        self.assertEqual(len(self.calls), calls_after_first)
        self.assertEqual(len(self.signed_payloads), 1)
        self.assertEqual(sum(record["stage"] == "final" for record in self.receipt_records()), 1)

    def test_final_summary_rejects_modified_metadata_on_readback(self):
        self.prepare_final_sequence()
        self.readback_override = lambda record: dict(record, metadata={"follow_up_actions": "Incorrect replacement"})
        with mock.patch.object(self.helper.time, "sleep"):
            with self.assertRaises(RuntimeError):
                self.final_summary()
        self.assertFalse(any(record["stage"] == "final" and record["verified"]
                             for record in self.receipt_records()))
        with self.assertRaises(RuntimeError):
            self.helper.assert_stage("final", 0, 1)

    def test_final_summary_requires_atc_stage_before_publication(self):
        self.initialize()
        self.input_records()
        self.helper.set_stage("baseline")
        self.api.put_transaction(self.risk("aggregate"), TOKEN)
        before = len(self.calls)
        with self.assertRaises(RuntimeError):
            self.final_summary()
        self.assertEqual(len(self.calls), before)

    def test_final_summary_requires_a_verified_aggregate(self):
        self.initialize()
        self.input_records()
        self.helper.set_stage("atc")
        self.api.put_transaction(self.risk(), TOKEN)
        before = len(self.calls)
        with self.assertRaises(RuntimeError):
            self.final_summary()
        self.assertEqual(len(self.calls), before)


if __name__ == "__main__":
    unittest.main()
