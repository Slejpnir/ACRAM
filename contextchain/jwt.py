import time

from .base64url import Base64Url
from .ed25519 import Ed25519

class JWT:
    @staticmethod
    def token(authorized_user_id, authorized_user_private_key, dataspace_id=None, exp = 10):
        header = {
            'alg': 'ES256',
            'typ': 'JWT'
        }
        now = int(time.time())
        payload = {
            'iss': authorized_user_id,
            'iat': now-2,
            'exp': now + exp,
            'sub': dataspace_id if dataspace_id else 'ContextChain'
        }
        message = f'{Base64Url.encode(header)}.{Base64Url.encode(payload)}'
        signature = Ed25519.sign_sha_256(message, authorized_user_private_key)
        return f'{message}.{signature}'
