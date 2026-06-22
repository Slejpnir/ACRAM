import json
import os
import qrcode

from .base64url import Base64Url
from Crypto.Cipher import AES
from Crypto.Protocol.KDF import PBKDF2
from Crypto.Random import get_random_bytes
from Crypto.Util.Padding import pad, unpad
from pyzbar.pyzbar import decode
from PIL import Image

class Wallet:
    def __init__(self, file_path="smartqc_wallet.json"):
        self.file_path = file_path

    def add_user(self, name, id, private_key, password):
        wallet = self.load_wallet()
        if any(user['name'] == name for user in wallet):
            raise ValueError("User already exists")
        encrypted_data = self.encrypt_data({'id': id, 'private_key': private_key}, password)
        wallet.append({'name': name, 'data': encrypted_data})
        self.save_wallet(wallet)

    @staticmethod
    def decode_qr_code(filename, password):
        img = Image.open(filename)
        decoded_objects = decode(img)
        if not decoded_objects:
            raise ValueError("QR code not found or unreadable.")
        encrypted_data = decoded_objects[0].data.decode("utf-8")
        return Wallet.decrypt_user_data(encrypted_data, password)

    @staticmethod
    def decrypt_data(ciphertext_b64, password):
        try:
            combined = Base64Url.decode(ciphertext_b64)
            salt = combined[-8:]
            iv = combined[-24:-8]
            encrypted = combined[:-24]
            key = Wallet.derive_key(password, salt)
            cipher = AES.new(key, AES.MODE_CBC, iv)
            decrypted = cipher.decrypt(encrypted)
            return json.loads(unpad(decrypted, AES.block_size).decode("utf-8"))
        except Exception as e:
            print("Decrypt failed:", e)
            return None

    @staticmethod
    def decrypt_user_data(json_string, password):
        try:
            user_data = json.loads(json_string)
            decrypted = Wallet.decrypt_data(user_data["data"], password)
            return {"name": user_data["name"], "data": decrypted}
        except Exception as e:
            print(f"Decrypt failed: {e}")
            return None

    @staticmethod
    def derive_key(password, salt):
        iterations = 256
        return PBKDF2(password, salt, dkLen=32, count=iterations)

    @staticmethod
    def encrypt_data(data, password):
        salt = get_random_bytes(8)
        iv = get_random_bytes(16)
        key = Wallet.derive_key(password, salt)
        cipher = AES.new(key, AES.MODE_CBC, iv)
        padded_data = pad(json.dumps(data).encode("utf-8"), AES.block_size)
        encrypted = cipher.encrypt(padded_data)
        combined = encrypted + iv + salt
        return Base64Url.encode(combined)

    @staticmethod
    def encrypt_user_data(name, data, password):
        encrypted_data = Wallet.encrypt_data(data, password)
        return json.dumps({"name": name, "data": encrypted_data})

    @staticmethod
    def generate_qr_code(name, data, password, filename):
        encrypted_data = Wallet.encrypt_user_data(name, data, password)
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(encrypted_data)
        qr.make(fit=True)
        img = qr.make_image(fill="black", back_color="white")
        img.save(filename)

    def get_user_data(self, name, password):
        wallet = self.load_wallet()
        user = next((u for u in wallet if u['name'] == name), None)
        if not user:
            raise ValueError("User not found")
        decrypted = self.decrypt_data(user['data'], password)
        if not decrypted:
            raise ValueError("Incorrect password")
        return decrypted

    def load_wallet(self):
        try:
            with open(self.file_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            return []

    def save_wallet(self, wallet):
        with open(self.file_path, 'w', encoding='utf-8') as f:
            json.dump(wallet, f, indent=2)