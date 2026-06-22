import argparse
import json
import re
from pathlib import Path
from typing import Any, List, Tuple

import requests
from requests.utils import quote

from smartqc import JWT


DEFAULT_CREDS = "ws_credentials_nokia.json"
DEFAULT_OUT = "last_transaction_uc2.json"


def ws_to_http_base(ws_url: str, keep_port: bool) -> str:
    # ws://host:port/smartqc/ws  -> http://host:port
    # wss://...                  -> https://...
    url = ws_url.strip()
    url = re.sub(r"^ws://", "http://", url)
    url = re.sub(r"^wss://", "https://", url)
    m = re.match(r"^(https?://[^/]+)", url)
    if not m:
        raise ValueError(f"Unsupported websocket_address: {ws_url}")
    base = m.group(1)
    if keep_port:
        return base
    # Strip explicit port if present
    m2 = re.match(r"^(https?://[^/:]+)(?::\d+)?$", base)
    return m2.group(1) if m2 else base


def load_creds(path: str) -> Tuple[str, str, str, str]:
    p = Path(path)
    creds = json.loads(p.read_text(encoding="utf-8"))
    user_id = creds["user_id"]
    private_key = creds["private_key"]
    websocket_address = creds["websocket_address"]
    # Default: do NOT include explicit port in base_url
    base_url = ws_to_http_base(websocket_address, keep_port=False)
    return base_url, user_id, private_key, websocket_address


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="UC2 (Nokia) GET transactions via SmartQC REST API."
    )
    p.add_argument(
        "id",
        help="ID to query (context_id OR asset_id OR parent_id, depending on --by).",
    )
    p.add_argument(
        "--state",
        action="store_true",
        help="Use /state endpoints (state/transactions).",
    )
    p.add_argument(
        "--probe",
        action="store_true",
        help="Try multiple query types and print the first non-error response.",
    )
    p.add_argument(
        "--search",
        action="store_true",
        help=(
            "Use /state/transactions?search=<text> (full-text search). "
            "Useful fallback when context_id queries are slow/broken."
        ),
    )
    p.add_argument(
        "--by",
        choices=["context_id", "asset_id", "parent_id", "transaction_id"],
        default="context_id",
        help="Query type (default: context_id).",
    )
    p.add_argument(
        "--creds",
        default=DEFAULT_CREDS,
        help="Credentials JSON file (default: ws_credentials_nokia.json).",
    )
    p.add_argument(
        "--base-url",
        default=None,
        help="Override base URL, e.g. http://192.168.1.238:8080 (optional).",
    )
    p.add_argument(
        "--keep-port",
        action="store_true",
        help="Keep explicit port from websocket_address when deriving base_url.",
    )
    p.add_argument(
        "--auth",
        choices=["jwt", "none"],
        default="jwt",
        help=(
            "Auth mode. SmartQC REST endpoints typically require JWT auth (default: jwt). "
            "Use 'none' only if your server allows anonymous reads."
        ),
    )
    p.add_argument(
        "--jwt-exp",
        type=int,
        default=5,
        help="JWT token validity in seconds (default: 5).",
    )
    p.add_argument(
        "--jwt-hash",
        choices=["auto", "sha3", "sha256"],
        default="auto",
        help=(
            "Hash used when signing the JWT message. "
            "'auto' tries sha3 first, then sha256. "
            "The bundled SmartQC Python client uses sha3; SmartQC.pdf describes sha256."
        ),
    )
    p.add_argument(
        "--jwt-skew",
        type=int,
        default=2,
        help="Clock skew compensation in seconds (default: 2).",
    )
    p.add_argument(
        "--debug-jwt",
        action="store_true",
        help="Print JWT header/payload (and a short signature prefix) for debugging.",
    )
    p.add_argument(
        "--timeout",
        type=int,
        default=90,
        help="HTTP timeout in seconds (default: 90).",
    )
    p.add_argument(
        "--out",
        default=DEFAULT_OUT,
        help=f"Write only the newest transaction to this JSON file (default: {DEFAULT_OUT}).",
    )
    p.add_argument(
        "--no-out",
        action="store_true",
        help="Do not write output to a file.",
    )
    p.add_argument(
        "--quiet",
        action="store_true",
        help="Do not print the full response JSON to stdout.",
    )
    return p.parse_args()


def _is_error(resp: Any) -> bool:
    return isinstance(resp, dict) and "error" in resp


def _extract_last_transaction(resp: Any) -> Any:
    """
    SmartQC returns arrays sorted ascending by timestamp (per docs), but we also
    defensively select max(timestamp) if present.
    """
    if isinstance(resp, list):
        if not resp:
            return None

        def ts(x: Any) -> int:
            try:
                v = x.get("timestamp")
                if v is None:
                    return -1
                return int(v)
            except Exception:
                return -1

        # Prefer max(timestamp); fallback to last element
        best = max(resp, key=ts)
        if ts(best) == -1:
            return resp[-1]
        return best

    if isinstance(resp, dict):
        # A single transaction object
        if "id" in resp and ("timestamp" in resp or "asset_id" in resp or "context_id" in resp):
            return resp

    return None


def main() -> None:
    args = parse_args()
    base_url, user_id, private_key, ws_addr = load_creds(args.creds)
    base_url_with_port = ws_to_http_base(ws_addr, keep_port=True)
    if args.keep_port:
        base_url = base_url_with_port
    if args.base_url:
        base_url = args.base_url
        base_url_with_port = args.base_url

    def make_jwt(jwt_hash: str) -> str:
        # SHA3 path: use bundled SmartQC JWT implementation (sha3_256).
        if jwt_hash == "sha3":
            return JWT.token(user_id, private_key, exp=args.jwt_exp)

        # SHA256 alternative: as described in SmartQC.pdf.
        # Implemented locally so we can switch without touching the library.
        import base58
        import hashlib
        import nacl.signing
        from smartqc.base64url import Base64Url
        import time as _time

        header = {"alg": "ES256", "typ": "JWT"}
        now = int(_time.time()) - int(args.jwt_skew)
        payload = {"iss": user_id, "iat": now, "exp": now + int(args.jwt_exp), "sub": "SmartQC"}
        message = f"{Base64Url.encode(header)}.{Base64Url.encode(payload)}"
        message_hash = hashlib.sha256(message.encode("utf-8")).digest()
        keypair = nacl.signing.SigningKey(base58.b58decode(private_key))
        signature = Base64Url.encode(keypair.sign(message_hash).signature)
        token = f"{message}.{signature}"

        if args.debug_jwt:
            print("jwt.hash:", jwt_hash)
            print("jwt.header:", header)
            print("jwt.payload:", payload)
            print("jwt.signature_prefix:", signature[:16])

        return token

    # Some SmartQC endpoints use asset_id as the stable identifier (context_id).
    # Users sometimes paste the *current state transaction id* instead of asset_id.
    def resolve_context_asset_id(base: str, maybe_id: str) -> str:
        if args.auth != "jwt":
            return maybe_id
        try:
            headers = {"Accept": "application/json", "Authorization": "Bearer " + make_jwt("sha3")}
            r = requests.get(f"{base}/smartqc/state/contexts", headers=headers, timeout=args.timeout)
            if r.status_code != 200:
                return maybe_id
            ctxs = r.json()
            for c in ctxs:
                try:
                    if c.get("asset_id") == maybe_id:
                        return maybe_id
                    if c.get("id") == maybe_id and isinstance(c.get("asset_id"), str) and c.get("asset_id"):
                        return c["asset_id"]
                except Exception:
                    continue
        except Exception:
            return maybe_id
        return maybe_id

    query_id = args.id
    if args.by == "context_id" and not args.search:
        resolved = resolve_context_asset_id(base_url_with_port, query_id)
        if resolved != query_id:
            print(f"resolved context id -> asset_id: {query_id} -> {resolved}")
            query_id = resolved

    def build_url(base: str, by: str, state: bool) -> str:
        prefix = f"{base}/smartqc"
        if args.search:
            # Search is only defined on /state endpoints
            return f"{prefix}/state/transactions?search={quote(query_id)}"
        if by == "transaction_id":
            return f"{prefix}/transactions/{query_id}"
        # list endpoints
        if state:
            return f"{prefix}/state/transactions?{by}={query_id}"
        return f"{prefix}/transactions?{by}={query_id}"

    def request_once(base: str, by: str, state: bool, jwt_hash: str | None) -> Any:
        url = build_url(base, by, state)
        headers = {"Accept": "application/json"}
        if args.auth == "jwt":
            token = make_jwt(jwt_hash or "sha3")
            headers["Authorization"] = f"Bearer {token}"
        try:
            r = requests.get(url, headers=headers, timeout=args.timeout)
        except requests.exceptions.Timeout as e:
            return {
                "error": "HTTP timeout",
                "details": str(e),
                "url": url,
                "base_url": base,
                "by": by,
                "state": state,
                "auth": args.auth,
                "jwt_hash": jwt_hash,
                "timeout_s": args.timeout,
            }
        except requests.exceptions.RequestException as e:
            return {
                "error": "HTTP request failed",
                "details": str(e),
                "url": url,
                "base_url": base,
                "by": by,
                "state": state,
                "auth": args.auth,
                "jwt_hash": jwt_hash,
            }
        if r.status_code >= 400:
            return {
                "error": f"HTTP {r.status_code}",
                "details": r.text,
                "url": url,
                "base_url": base,
                "by": by,
                "state": state,
                "auth": args.auth,
                "jwt_hash": jwt_hash,
            }
        try:
            return r.json()
        except Exception:
            return r.text

    def call(base: str, by: str, state: bool) -> Any:
        if args.auth != "jwt" or args.jwt_hash in {"sha3", "sha256"}:
            return request_once(base, by, state, None if args.auth != "jwt" else args.jwt_hash)

        # auto: try sha3 then sha256
        r1 = request_once(base, by, state, "sha3")
        if not _is_error(r1):
            return r1
        # If sha3 errored, try sha256 once
        r2 = request_once(base, by, state, "sha256")
        if not _is_error(r2):
            return r2
        return {"error": "Both jwt_hash variants failed", "sha3": r1, "sha256": r2}

    resp: Any
    if args.probe:
        base_candidates: List[str] = []
        for b in [base_url, base_url_with_port]:
            if b and b not in base_candidates:
                base_candidates.append(b)
        attempts: List[Tuple[str, bool]] = [
            ("transaction_id", False),
            ("asset_id", False),
            ("context_id", False),
            ("parent_id", False),
            ("asset_id", True),
            ("context_id", True),
            ("parent_id", True),
        ]
        resp = None
        last_err: Any = None
        for b in base_candidates:
            for by, st in attempts:
                # search mode overrides by/state
                if args.search:
                    by = args.by
                    st = True
                r = call(b, by, st)
                if not _is_error(r):
                    resp = r
                    print(f"probe hit: base_url={b} by={by}, state={st}")
                    break
                else:
                    last_err = r
                    print(f"probe miss: base_url={b} by={by}, state={st} -> {r.get('error')}")
            if resp is not None:
                break
        if resp is None:
            resp = last_err  # last error
    else:
        state = True if args.search else args.state
        resp = call(base_url, args.by, state)
        # Helpful fallback: if base_url was derived without port and it fails,
        # retry once with the websocket port variant.
        if (
            _is_error(resp)
            and base_url_with_port
            and base_url_with_port != base_url
            and isinstance(resp, dict)
            and resp.get("error") in {"HTTP 401", "HTTP 404", "HTTP 500"}
        ):
            resp2 = call(base_url_with_port, args.by, state)
            if not _is_error(resp2):
                print(f"retry succeeded with base_url={base_url_with_port}")
                base_url = base_url_with_port
                resp = resp2
            else:
                # Preserve both errors for debugging.
                resp = {
                    "error": "Both base_url variants failed",
                    "first": resp,
                    "second": resp2,
                }

    print("websocket_address:", ws_addr)
    print("base_url:", base_url)

    # Write only the newest/last transaction to file (user-friendly for large responses).
    if not args.no_out and not _is_error(resp):
        last_tx = _extract_last_transaction(resp)
        if last_tx is None:
            print("[WARN] No transaction found to write.")
        else:
            out_path = Path(args.out)
            out_path.write_text(json.dumps(last_tx, indent=2), encoding="utf-8")
            try:
                tx_id = last_tx.get("id")
                tx_ts = last_tx.get("timestamp")
                print(f"Wrote last transaction to: {out_path} (id={tx_id}, timestamp={tx_ts})")
            except Exception:
                print(f"Wrote last transaction to: {out_path}")

    if not args.quiet:
        print(json.dumps(resp, indent=2) if isinstance(resp, (dict, list)) else resp)


if __name__ == "__main__":
    main()

