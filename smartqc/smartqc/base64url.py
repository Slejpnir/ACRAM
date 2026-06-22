import base64
import json

class Base64Url:

    @staticmethod
    def encode(obj):
        if isinstance(obj, (dict, list)):
            obj = json.dumps(obj, separators=(',', ':'), sort_keys=True).encode('utf-8')
        elif isinstance(obj, str):
            obj = obj.encode('utf-8')
        return base64.urlsafe_b64encode(obj).decode('utf-8').rstrip('=').replace('+', '-').replace('/', '_')

    @staticmethod
    def decode(data):
        padding_needed = 4 - (len(data) % 4)
        if padding_needed and padding_needed != 4:
            data += "=" * padding_needed
        return base64.urlsafe_b64decode(data)
