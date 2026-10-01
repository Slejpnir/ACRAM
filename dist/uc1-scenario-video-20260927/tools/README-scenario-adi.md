# Real UC1 ADI helper

`scenario_adi.py` must run inside the same Python interpreter MATLAB uses for
`create_transaction.m`. It signs genuine ADI transactions with the existing UC1
credential file, verifies returned transaction IDs and authenticated GET data,
and hooks the current process's `contextchain.API.put_transaction` to record
ACRAM component and aggregate results as well as the two scenario inputs.

Interface (Python strings/numbers; callable through MATLAB `py`):

1. `initialize(credentials_path, run_dir, scenario_id, sbom_context_id='')` reads
   credentials without printing or copying them. It validates existing SBOM and
   UAM contexts. If no SBOM ID is supplied, exactly one matching existing context
   must be discoverable. No context is ever created. Use a fresh `run_dir`.
   Before sending input events, set stage to `baseline`, call the normal MATLAB
   `export_results` with publishing enabled, and require
   `assert_stage('baseline', min_components=9, min_aggregates=1)`.
2. `set_stage('sbom')`, then `send_sbom(subject)` sends a labelled demonstration
   CVE report with a synthetic `CVE-2099-00001`, score 8.8 and UI:R CVSS vector.
   This is scenario input, not a factual finding about the specified object.
3. Poll `verified_component_count('sbom')` and `verified_aggregate_count('sbom')`;
   call `assert_stage('sbom', min_components=1, min_aggregates=1)` before UAM.
4. `set_stage('uam')`, then `send_uam('user-N', 0.89)` sends the second labelled
   fixture. Poll the same counters with `'uam'`, then assert the stage.
5. `summary_json()` returns sanitized proof counts and IDs. `verified_ids_json`
   returns IDs for one stage. `verified_risk_count` combines the two risk kinds.
6. `read_input_json(stage, transaction_id)` retrieves a previously verified
   input from ADI with a fresh authentication token. It requires the stored ID,
   context (when returned), and payload to match the original receipt. The
   console runner uses this only when no WebSocket notification arrives within
   15 seconds, and records the HTTP delivery path explicitly. This operation
   does not create a transaction or count as a risk update.

`transaction-receipts.jsonl` contains actual sent data, returned IDs, stage and
authenticated verification result. Failed read-back produces an unverified
receipt and raises an exception. A server error dictionary or malformed ID
raises without being treated as success. Keys, credentials, authorization
headers, JWTs and signatures are never written to receipts. A stage counts only
verified risk messages, so a receipt alone is not a success criterion.

Helper diagnostics are written to `adi-verification.log` in the run directory.
The console shows the application's normal transaction messages, avoiding
duplicate accepted/persisted messages. HTTP recovery remains visible in the
console and in the stage delivery record.

The helper modifies no production source files. HTTP calls have bounded
timeouts, and GET verification retries up to thirty times. Launch in a fresh process for
each recording. It expects UC1's Antonov ADI port 83, matching the application.

`python -m unittest test_scenario_adi.py` runs offline negative/positive tests
with a fake API in temporary directories. These temporary receipts are deleted;
they must never be presented as evidence of real ADI activity.
