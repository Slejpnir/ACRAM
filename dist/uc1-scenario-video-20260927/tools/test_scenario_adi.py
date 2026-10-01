"""Offline error-path tests. No network use and no retained simulated receipts."""
import copy
from contextlib import redirect_stdout
import importlib
import io
import json
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch

import scenario_adi


class RecorderTests(unittest.TestCase):
    def setUp(self):
        self.helper = importlib.reload(scenario_adi)
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.sbom_context = "b" * 64
        self.creds = self.root / "credentials.json"
        self.creds.write_text(json.dumps({"websocket_address": "ws://unit-test.invalid:83/contextchain/ws",
                                         "user_id": "fake-user", "private_key": "fake-private-key"}), encoding="utf-8")
        context_id = self.sbom_context
        class FakeAPI:
            response = "a" * 64
            mismatch = False
            read_error = False
            def __init__(self, base_url, blockchain):
                self.base_url, self.blockchain = base_url, blockchain
            def _send_request(self, *args, **kwargs):
                raise AssertionError("Network function must never execute in this test.")
            def get_context_transactions(self, token):
                return [{"id": context_id, "data": {"context_data": {"CVE_list": []}}}]
            def get_context_transaction(self, cid, token):
                return [{"id": "f" * 64, "asset_id": cid, "operation": "TRANSFER"},
                        {"id": cid, "data": {"context_data": {"CVE_list": []}}}]
            def put_transaction(self, transaction, token):
                self.last = copy.deepcopy(transaction)
                return self.response
            def get_transaction(self, txid, token):
                if self.read_error:
                    return {"error": "read denied", "details": "sensitive-details"}
                result = copy.deepcopy(self.last)
                result["id"] = txid
                if self.mismatch:
                    result["data"]["value"] = -1
                unrelated = copy.deepcopy(result)
                unrelated["id"] = "d" * 64
                unrelated["data"]["value"] = 0.01
                return [{"id": "e" * 64, "asset_id": txid, "operation": "TRANSFER"}, unrelated, result]
        self.api_class = FakeAPI
        transaction_class = types.SimpleNamespace(
            make_create_transaction=lambda cid, data, metadata, user, public: {
                "context_id": cid, "data": data, "metadata": metadata, "auth_id": user, "auth_public_key": public},
            sign_transaction=lambda transaction, private: {**transaction, "signature": "fake-signature"})
        modules = {"contextchain.api": types.SimpleNamespace(API=FakeAPI),
                   "contextchain.transaction": types.SimpleNamespace(Transaction=transaction_class),
                   "contextchain.jwt": types.SimpleNamespace(JWT=types.SimpleNamespace(token=lambda *args: "fake-token"))}
        with patch.object(self.helper.importlib, "import_module", side_effect=lambda name: modules[name]):
            self.helper.initialize(str(self.creds), str(self.root / "run"), "offline-unit-test", self.sbom_context)

    def tearDown(self):
        self.temp.cleanup()

    def test_uam_numeric_payload_and_receipt_redaction(self):
        self.helper.set_stage("uam")
        txid = self.helper.send_uam("user-2", 0.89)
        self.assertEqual(txid, "a" * 64)
        api = self.helper._STATE["api"]
        self.assertEqual(api.last["data"]["value"], 0.89)
        self.assertEqual(api.last["data"]["type"], "UAM user anomaly indicator")
        receipt_text = (self.root / "run" / "transaction-receipts.jsonl").read_text()
        for forbidden in ("fake-private-key", "fake-token", "fake-signature", "auth_id", "auth_public_key"):
            self.assertNotIn(forbidden, receipt_text)
        self.assertTrue(json.loads(receipt_text)["verified"])

    def test_sdk_error_dictionary_does_not_count_as_success(self):
        self.api_class.response = {"error": "HTTP 400", "details": "sensitive-response"}
        self.helper.set_stage("sbom")
        with self.assertRaisesRegex(RuntimeError, "did not return a transaction ID"):
            self.helper.send_sbom("scenario-object")
        self.assertEqual(self.helper.verified_risk_count("sbom"), 0)
        self.assertFalse((self.root / "run" / "transaction-receipts.jsonl").exists())

    def test_readback_mismatch_is_not_verified(self):
        self.api_class.mismatch = True
        self.helper.set_stage("sbom")
        with patch.object(self.helper.time, "sleep"), self.assertRaisesRegex(RuntimeError, "did not verify"):
            self.helper.send_sbom("scenario-object")
        receipt = json.loads((self.root / "run" / "transaction-receipts.jsonl").read_text())
        self.assertFalse(receipt["verified"])
        with self.assertRaisesRegex(RuntimeError, "incomplete"):
            self.helper.assert_stage("sbom")

    def test_sdk_risk_hook_counts_and_stage_isolation(self):
        self.helper.set_stage("sbom")
        api = self.helper._STATE["api"]
        for typ in ("Component level access control risk", "Aggregated access control risk"):
            api.put_transaction({"context_id": "c" * 64,
                                 "data": {"type": typ, "source": "ACRAM", "value": 0.77}}, "fake-token")
        self.assertTrue(self.helper.assert_stage("sbom"))
        self.assertEqual(self.helper.verified_risk_count("sbom"), 2)
        self.assertEqual(self.helper.verified_risk_count("uam"), 0)

    def test_verification_diagnostics_are_saved_without_duplicate_console_output(self):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            self.helper.set_stage("baseline")
            api = self.helper._STATE["api"]
            for typ in ("Component level access control risk", "Aggregated access control risk"):
                api.put_transaction({"context_id": "c" * 64,
                                     "data": {"type": typ, "source": "ACRAM", "value": 0.1},
                                     "auth_id": "fake-user", "signature": "fake-signature"}, "fake-token")
            self.helper.assert_stage("baseline")
        self.assertEqual(stdout.getvalue(), "")
        audit = (self.root / "run" / "adi-verification.log").read_text(encoding="utf-8")
        self.assertIn("ADI connection ready", audit)
        self.assertIn("Risk stage started | stage=BASELINE", audit)
        self.assertEqual(audit.count("ADI transaction accepted"), 2)
        self.assertEqual(audit.count("ADI transaction persisted"), 2)
        self.assertIn("Risk publication complete", audit)
        for forbidden in ("fake-private-key", "fake-token", "fake-signature", "auth_id", "auth_public_key"):
            self.assertNotIn(forbidden, audit)
        receipts = [json.loads(line) for line in
                    (self.root / "run" / "transaction-receipts.jsonl").read_text(encoding="utf-8").splitlines()]
        self.assertEqual(len(receipts), 2)
        self.assertTrue(all(receipt["verified"] for receipt in receipts))

    def test_history_selects_requested_id_context_and_data(self):
        expected_data = {"value": .89}
        matching = {"id": "a" * 64, "context_id": "b" * 64, "data": expected_data}
        history = [{"id": "f" * 64, "operation": "TRANSFER"},
                   {**matching, "id": "c" * 64},
                   {**matching, "context_id": "d" * 64},
                   {**matching, "data": {"value": .01}}, matching]
        self.assertEqual(self.helper._unpack_transaction(history, "a" * 64, "b" * 64, expected_data), matching)
        self.assertIsNone(self.helper._unpack_transaction(history[:-1], "a" * 64, "b" * 64, expected_data))

    def test_initial_risks_are_counted_and_included_before_event_updates(self):
        self.helper.set_stage("baseline")
        api = self.helper._STATE["api"]
        for index in range(9):
            api.put_transaction({"context_id": "c" * 64,
                                 "data": {"type": "Component level access control risk", "source": "ACRAM",
                                          "subject": f"asset-{index}", "value": 0.1}}, "fake-token")
        with self.assertRaisesRegex(RuntimeError, "incomplete"):
            self.helper.assert_stage("baseline", 9, 1)
        api.put_transaction({"context_id": "d" * 64,
                             "data": {"type": "Aggregated access control risk", "source": "ACRAM", "value": 0.1}}, "fake-token")
        self.assertTrue(self.helper.assert_stage("baseline", 9, 1))
        summary = json.loads(self.helper.summary_json())
        self.assertEqual(summary["stages"]["baseline"]["verified_components"], 9)
        self.assertEqual(summary["stages"]["baseline"]["verified_aggregates"], 1)
        self.assertEqual(len(summary["stages"]["baseline"]["verified_transaction_ids"]), 10)
        self.assertEqual(summary["stages"]["sbom"]["verified_components"], 0)
        self.assertEqual(summary["stages"]["uam"]["verified_components"], 0)

    def test_read_error_instead_of_history_is_not_verified(self):
        self.api_class.read_error = True
        self.helper.set_stage("sbom")
        with patch.object(self.helper.time, "sleep"), self.assertRaisesRegex(RuntimeError, "did not verify"):
            self.helper.send_sbom("scenario-object")
        self.assertEqual(self.helper.verified_risk_count("sbom"), 0)
        with self.assertRaisesRegex(RuntimeError, "discovery failed"):
            list(self.helper._context_entries({"error": "denied", "details": "sensitive-details"}))

    def test_http_recovery_fetches_exact_stored_input_with_fresh_token(self):
        self.helper.set_stage("uam")
        txid = self.helper.send_uam("user-1", 0.89)
        api = self.helper._STATE["api"]
        before = copy.deepcopy(self.helper._STATE["records"])
        with patch.object(self.helper, "_token", return_value="fresh-token") as token, \
                patch.object(api, "get_transaction", wraps=api.get_transaction) as fetch:
            stored = json.loads(self.helper.read_input_json("uam", txid))
        token.assert_called_once_with()
        fetch.assert_called_once_with(txid, "fresh-token")
        self.assertEqual(stored["id"], txid)
        self.assertEqual(stored["context_id"], self.helper.UAM_CONTEXT)
        self.assertEqual(stored["data"], api.last["data"])
        self.assertNotIn("signature", stored)
        self.assertNotIn("auth_id", stored)
        self.assertEqual(self.helper._STATE["records"], before)

    def test_http_recovery_rejects_unverified_or_wrong_stage_receipt_before_fetch(self):
        self.helper.set_stage("uam")
        txid = self.helper.send_uam("user-1", 0.89)
        api = self.helper._STATE["api"]
        with patch.object(api, "get_transaction") as fetch:
            with self.assertRaisesRegex(RuntimeError, "verified input receipt"):
                self.helper.read_input_json("sbom", txid)
            with self.assertRaisesRegex(RuntimeError, "verified input receipt"):
                self.helper.read_input_json("uam", "f" * 64)
            self.helper._STATE["records"][0]["verified"] = False
            with self.assertRaisesRegex(RuntimeError, "verified input receipt"):
                self.helper.read_input_json("uam", txid)
        fetch.assert_not_called()

    def test_http_recovery_rejects_changed_payload_and_missing_or_wrong_id(self):
        self.helper.set_stage("uam")
        txid = self.helper.send_uam("user-1", 0.89)
        api = self.helper._STATE["api"]
        stored = {**copy.deepcopy(api.last), "id": txid}
        changed = copy.deepcopy(stored)
        changed["data"]["value"] = 0.01
        missing_id = {k: v for k, v in stored.items() if k != "id"}
        wrong_id = {**stored, "id": "f" * 64}
        wrong_context = {**stored, "context_id": "e" * 64}
        for response in (changed, missing_id, wrong_id, wrong_context, {"error": "denied"}):
            with self.subTest(response=response), patch.object(api, "get_transaction", return_value=response):
                with self.assertRaisesRegex(RuntimeError, "exact verified input"):
                    self.helper.read_input_json("uam", txid)


if __name__ == "__main__":
    unittest.main()
