import json
import requests

from io import BytesIO
from requests.utils import quote

class API:
    def __init__(self, base_url, blockchain):
        self.base_url = base_url
        self.blockchain = blockchain

    def get_blob_transaction(self, blob_id, token):
        url = f"{self.base_url}/{self.blockchain}/blobs/{blob_id}"
        return self._send_request('GET', url, token)

    def get_blob_transaction_data(self, blob_id, token):
        url = f"{self.base_url}/{self.blockchain}/blobs/{blob_id}/data"
        response = self._send_request("GET", url, token, responseType="binary")

    def get_blob_transaction_data(self, blob_id, token):
        url = f"{self.base_url}/{self.blockchain}/blobs/{blob_id}/data"
        response = self._send_request("GET", url, token, responseType="binary")
        if isinstance(response, dict) and "error" in response:
            return response
        else:
            return BytesIO(response)

    def get_context_transaction(self, context_id, token):
        url = f"{self.base_url}/{self.blockchain}/contexts/{context_id}"
        return self._send_request('GET', url, token)

    def get_context_transactions(self, token):
        url = f"{self.base_url}/{self.blockchain}/contexts"
        return self._send_request('GET', url, token)

    def get_index_transaction(self, index_id, token):
        url = f"{self.base_url}/{self.blockchain}/indexes/{index_id}"
        return self._send_request('GET', url, token)

    def get_index_transactions(self, token):
        url = f"{self.base_url}/{self.blockchain}/indexes"
        return self._send_request('GET', url, token)

    def get_state_blob_transaction(self, blob_id, token):
        url = f"{self.base_url}/{self.blockchain}/state/blobs/{blob_id}"
        return self._send_request('GET', url, token)

    def get_state_context_transaction(self, context_id, token):
        url = f"{self.base_url}/{self.blockchain}/state/contexts/{context_id}"
        return self._send_request('GET', url, token)

    def get_state_context_transactions(self, token):
        url = f"{self.base_url}/{self.blockchain}/state/contexts"
        return self._send_request('GET', url, token)

    def get_state_index_transaction(self, index_id, token):
        url = f"{self.base_url}/{self.blockchain}/state/indexes/{index_id}"
        return self._send_request('GET', url, token)

    def get_state_index_transactions(self, token):
        url = f"{self.base_url}/{self.blockchain}/state/indexes"
        return self._send_request('GET', url, token)

    def get_state_transactions_by_asset_id(self, asset_id, token):
        url = f"{self.base_url}/{self.blockchain}/state/transactions?asset_id={asset_id}"
        return self._send_request('GET', url, token)

    def get_state_transactions_by_context_id(self, context_id, token):
        url = f"{self.base_url}/{self.blockchain}/state/transactions?context_id={context_id}"
        return self._send_request('GET', url, token)

    def get_state_transactions_by_parent_id(self, parent_id, token):
        url = f"{self.base_url}/{self.blockchain}/state/transactions?parent_id={parent_id}"
        return self._send_request('GET', url, token)

    def get_state_user_transaction(self, user_id, token):
        url = f"{self.base_url}/{self.blockchain}/state/users/{user_id}"
        return self._send_request('GET', url, token)

    def get_state_user_transactions(self, token):
        url = f"{self.base_url}/{self.blockchain}/state/users"
        return self._send_request('GET', url, token)

    def get_transaction(self, transaction_id, token):
        url = f"{self.base_url}/{self.blockchain}/transactions/{transaction_id}"
        return self._send_request('GET', url, token)

    def get_transactions_by_asset_id(self, asset_id, token):
        url = f"{self.base_url}/{self.blockchain}/transactions?asset_id={asset_id}"
        return self._send_request('GET', url, token)

    def get_transactions_by_context_id(self, context_id, token):
        url = f"{self.base_url}/{self.blockchain}/transactions?context_id={context_id}"
        return self._send_request('GET', url, token)

    def get_transactions_by_parent_id(self, parent_id, token):
        url = f"{self.base_url}/{self.blockchain}/transactions?parent_id={parent_id}"
        return self._send_request('GET', url, token)

    def get_user_transaction(self, user_id, token):
        url = f"{self.base_url}/{self.blockchain}/users/{user_id}"
        return self._send_request('GET', url, token)

    def get_user_transactions(self, token):
        url = f"{self.base_url}/{self.blockchain}/users"
        return self._send_request('GET', url, token)

    def put_blob_transaction(self, blob_transaction, stream, token):
        url = f"{self.base_url}/{self.blockchain}/blob"
        if stream is None:
            headers = {"Content-Type": "application/json"}
            return self._send_request('PUT', url, token, responseType="text", json=blob_transaction, headers=headers)
        else:
            files = {
                "blob": ("blob.json", json.dumps(blob_transaction), "application/json"),
                "data": ("file", stream, "application/octet-stream")
            }
            return self._send_request("PUT", url, token, responseType="text", files=files)

    def put_context_transaction(self, context_transaction, token):
        url = f"{self.base_url}/{self.blockchain}/context"
        headers = {"Content-Type": "application/json"}
        return self._send_request('PUT', url, token, responseType="text", json=context_transaction, headers=headers)

    def put_index_transaction(self, index_transaction, token):
        url = f"{self.base_url}/{self.blockchain}/index"
        headers = {"Content-Type": "application/json"}
        return self._send_request('PUT', url, token, responseType="text", json=index_transaction, headers=headers)

    def put_transaction(self, transaction, token):
        url = f"{self.base_url}/{self.blockchain}/transaction"
        headers = {"Content-Type": "application/json"}
        return self._send_request('PUT', url, token, responseType="text", json=transaction, headers=headers)

    def put_user_transaction(self, user_transaction, token):
        url = f"{self.base_url}/{self.blockchain}/user"
        headers = {"Content-Type": "application/json"}
        return self._send_request('PUT', url, token, responseType="text", json=user_transaction, headers=headers)

    def query_state_transactions(self, filters, token):
        query = quote(json.dumps(filters))
        url = f"{self.base_url}/{self.blockchain}/state/transactions?query={query}"
        return self._send_request("GET", url, token)

    def search_state_transactions(self, text, token):
        search = quote(text)
        url = f"{self.base_url}/{self.blockchain}/state/transactions?search={search}"
        return self._send_request('GET', url, token)

    def _send_request(self, method, url, token, responseType="json", **kwargs):
        headers = kwargs.pop('headers', {})
        headers["Authorization"] = f"Bearer {token}"
        try:
            response = requests.request(method, url, headers=headers, **kwargs)
            response.raise_for_status()
        except requests.exceptions.HTTPError as http_err:
            if response.status_code == 400:
                return {"error": "Bad request", "details": response.text}
            elif response.status_code == 404:
                return {"error": "Not found", "details": response.text}
            elif response.status_code == 500:
                return {"error": "Internal server error", "details": response.text}
            else:
                return {"error": f"HTTP error occurred: {http_err}"}
        except Exception as err:
            return {"error": f"Other error occurred: {err}"}
        else:
            if responseType == "json":
                return self._process_response(response)
            elif responseType == "text":
                return response.text
            else:
                return response.content

    def _process_response(self, response):
        try:
            return response.json()
        except ValueError:
            return response.text
