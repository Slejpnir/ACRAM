import time

from .base64url import Base64Url
from .ed25519 import Ed25519

class JWT:
    @staticmethod
    def token(authorized_user_id, authorized_user_private_key, exp = 5):
        header = {
            'alg': 'ES256',
            'typ': 'JWT'
        }
        now = int(time.time())-2
        payload = {
            'iss': authorized_user_id,
            'iat': now,
            'exp': now + exp,
            'sub': 'SmartQC'
        }
        message = f'{Base64Url.encode(header)}.{Base64Url.encode(payload)}'
        # Note: SmartQC reference client signs SHA3-256(message) with Ed25519.
        # This matches the bundled SmartQC Python library used in this workspace.
        signature = Ed25519.sign_sha_256(message, authorized_user_private_key)
        return f'{message}.{signature}'
