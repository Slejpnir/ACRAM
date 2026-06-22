import base58
from nacl.signing import SigningKey

class Ed25519Keypair:
    def __init__(self, private_key_base58, public_key_base58):
        self.private_key = private_key_base58
        self.public_key = public_key_base58

    @staticmethod
    def from_seed(seed=None):
        keypair = SigningKey(seed) if seed else SigningKey.generate()
        private_key = base58.b58encode(keypair.encode()).decode('utf-8')
        public_key = base58.b58encode(keypair.verify_key.encode()).decode('utf-8')
        return Ed25519Keypair(private_key, public_key)

    @staticmethod
    def from_base58_private_key(base58_private_key):
        seed = base58.b58decode(base58_private_key)
        keypair = SigningKey(seed)
        private_key = base58.b58encode(keypair.encode()).decode('utf-8')
        public_key = base58.b58encode(keypair.verify_key.encode()).decode('utf-8')
        return Ed25519Keypair(private_key, public_key)
