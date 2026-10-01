"""Network-free SDK boundary fixture for test_create_transaction.m.

The package name is deliberately unique; install/uninstall restore sys.modules.
Only fake identifiers and fake credentials are accepted. No SDK is imported.
"""

import json
import sys
import types

SERVICE = "acram_test_adi_transaction"
VALID_ID = "0123456789abcdef" * 4
PRIVATE_KEY = "TEST_PRIVATE_KEY_MUST_NOT_APPEAR_IN_ERRORS"
IDENTITY = "test-identity"
SECRET_DETAIL = "TEST_RESPONSE_SECRET_MUST_NOT_APPEAR_IN_ERRORS"
_previous = {}
_state = {}


class SignedTransaction:
    def __init__(self, payload):
        self.payload = payload


class Transaction:
    @staticmethod
    def sign_transaction(payload, private_key):
        assert private_key == PRIVATE_KEY, "Unexpected test credentials"
        assert isinstance(payload, dict), "Transaction map was not converted"
        assert payload["nested"]["items"] == ["first", 2.0], "Nested conversion failed"
        assert payload["subject"] == "test-subject", "Scalar string conversion failed"
        assert not _state["tokens"], "JWT was generated before signing"
        _state["events"].append("sign")
        _state["sign_count"] += 1
        signed = SignedTransaction(payload)
        _state["signed"] = signed
        return signed


class JWT:
    @staticmethod
    def token(identity, private_key):
        assert identity == IDENTITY and private_key == PRIVATE_KEY
        assert _state["sign_count"] == 1, "JWT must be generated after signing"
        token = "TEST_JWT_SECRET_%d" % (len(_state["tokens"]) + 1)
        _state["tokens"].append(token)
        _state["events"].append("token")
        return token


class API:
    def __init__(self, server, service):
        assert server == "http://adi-tests.invalid" and service == SERVICE

    def put_transaction(self, signed, token):
        assert signed is _state["signed"], "Retry must reuse the signed transaction"
        assert token == _state["tokens"][-1], "Request must use the latest token"
        assert token not in _state["used_tokens"], "Retry must refresh the token"
        _state["used_tokens"].append(token)
        _state["put_count"] += 1
        _state["events"].append("put")
        mode = _state["mode"]
        retry = _state["put_count"] > 1
        if mode == "valid":
            return VALID_ID
        if mode == "valid_upper":
            return VALID_ID.upper()
        if mode.startswith("401_error"):
            if mode.endswith("success") and retry:
                return VALID_ID
            return {"error": "HTTP error occurred: 401 Client Error: " + SECRET_DETAIL}
        if mode.startswith("401_status"):
            if mode.endswith("success") and retry:
                return VALID_ID
            return {"status_code": 401, "error": "Unauthorized " + SECRET_DETAIL}
        if mode == "400_error":
            return {"error": "HTTP error occurred: 400 Client Error: " + SECRET_DETAIL}
        if mode == "500_error":
            return {"error": "HTTP error occurred: 500 Server Error: " + SECRET_DETAIL}
        if mode == "4010_error":
            return {"error": "Request reference 4010 failed: " + SECRET_DETAIL}
        if mode == "garbage":
            return "not a transaction identifier"
        if mode == "json_error":
            return json.dumps({"error": "HTTP 401 " + SECRET_DETAIL})
        if mode == "empty":
            return ""
        if mode == "none":
            return None
        if mode == "list":
            return [VALID_ID]
        if mode == "dict_id":
            return {"id": VALID_ID}
        if mode == "short_id":
            return VALID_ID[:-1]
        if mode == "long_id":
            return VALID_ID + "0"
        if mode == "nonhex_id":
            return "g" * 64
        if mode == "prefixed_id":
            return "transactionId=" + VALID_ID
        if mode == "padded_id":
            return " " + VALID_ID + " "
        if mode == "integer":
            return 1234
        if mode == "bytes":
            return VALID_ID.encode("ascii")
        raise AssertionError("Unknown offline fixture mode: " + mode)


def install():
    if _previous:
        raise RuntimeError("ADI transaction fixture is already installed")
    package = types.ModuleType(SERVICE)
    package.__path__ = []
    modules = {SERVICE: package}
    for suffix, symbol, implementation in (
        ("api", "API", API),
        ("transaction", "Transaction", Transaction),
        ("jwt", "JWT", JWT),
    ):
        module = types.ModuleType(SERVICE + "." + suffix)
        setattr(module, symbol, implementation)
        modules[module.__name__] = module
        setattr(package, suffix, module)
    for name, module in modules.items():
        _previous[name] = sys.modules.get(name)
        sys.modules[name] = module
    reset("valid")
    return SERVICE


def reset(mode):
    _state.clear()
    _state.update(mode=mode, events=[], tokens=[], used_tokens=[], sign_count=0,
                  put_count=0, signed=None)


def snapshot_json():
    return json.dumps({"events": _state["events"],
                       "sign_count": _state["sign_count"],
                       "token_count": len(_state["tokens"]),
                       "put_count": _state["put_count"]})


def uninstall():
    for name, previous in _previous.items():
        if previous is None:
            sys.modules.pop(name, None)
        else:
            sys.modules[name] = previous
    _previous.clear()
    _state.clear()
