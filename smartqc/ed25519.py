import base58
import hashlib
import nacl.signing

from .base64url import Base64Url

class Ed25519:

    @staticmethod
    def sign_sha_256(message, private_key):
        message_hash = hashlib.sha3_256(message.encode('utf-8')).digest()
        keypair = nacl.signing.SigningKey(base58.b58decode(private_key))
        signature = keypair.sign(message_hash).signature
        return Base64Url.encode(signature)
