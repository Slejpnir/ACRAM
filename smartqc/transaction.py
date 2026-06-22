import copy
import hashlib
import json
import magic

from .base64url import Base64Url
from .ed25519 import Ed25519

class Transaction:
    @staticmethod
    def compute_hash(stream):
        sha3 = hashlib.sha3_256()
        size = 0
        while chunk := stream.read(8192):
            sha3.update(chunk)
            size += len(chunk)
        stream.seek(0)
        stream_hash = Base64Url.encode(sha3.digest())
        return size, stream_hash

    @staticmethod
    def detect_mime_type(stream):
        type = magic.Magic(mime=True).from_buffer(stream.read(2048))
        stream.seek(0)
        return type

    @staticmethod
    def make_create_blob_transaction(context_id, file_stream, mime_type, auth_user_id, auth_user_public_key):
        if mime_type is None:
            mime_type = Transaction.detect_mime_type(file_stream)
        size, hash_b64url = Transaction.compute_hash(file_stream)
        return {
            "data": {"hash": hash_b64url, "size": size, "type": mime_type},
            "metadata": {"context_id": context_id},
            'auth_id': auth_user_id,
            'auth_public_key': auth_user_public_key
        }

    @staticmethod
    def make_create_context_transaction(name, description, context_data, context_metadata, version, read_permissions, write_permissions, auth_user_id, auth_user_public_key):
        data = {}
        if context_data:
            data['context_data'] = context_data
        if context_metadata:
            data['context_metadata'] = context_metadata
        if version:
            data['version'] = version
        return {
            'data': data,
            'metadata': {
                'name': name,
                'description': description,
                'read_permissions': read_permissions,
                'write_permissions': write_permissions
            },
            'auth_id': auth_user_id,
            'auth_public_key': auth_user_public_key
        }

    @staticmethod
    def make_create_index_transaction(fields, auth_user_id, auth_user_public_key):
        return {
            'data': {
                'fields': fields
            },
            'metadata': {
                'action':"create"
            },
            'auth_id': auth_user_id,
            'auth_public_key': auth_user_public_key
        }

    @staticmethod
    def make_create_transaction(context_id, data, metadata, auth_user_id, auth_user_public_key):
        transaction = {
            'context_id': context_id,
            'auth_id': auth_user_id,
            'auth_public_key': auth_user_public_key
        }
        if data:
            transaction['data'] = data
        if metadata:
            transaction['metadata'] = metadata
        return transaction

    @staticmethod
    def make_create_user_transaction(name, public_key, users_admin, contexts_admin, auth_user_id, auth_user_public_key):
        metadata = {
            'name': name
        }
        if public_key:
            metadata['public_key'] = public_key
        if users_admin:
            metadata['users_admin'] = users_admin
        else:
            metadata['users_admin'] = False
        if contexts_admin:
            metadata['contexts_admin'] = contexts_admin
        else:
            metadata['contexts_admin'] = False
        return {
            'metadata': metadata,
            'auth_id': auth_user_id,
            'auth_public_key': auth_user_public_key
        }

    @staticmethod
    def make_update_blob_transaction(asset_id, input_id, context_id, auth_user_id, auth_user_public_key):
        return {
            'asset_id': asset_id,
            'input_id': input_id,
            'metadata': {
                'context_id': context_id
            },
            'auth_id': auth_user_id,
            'auth_public_key': auth_user_public_key
        }

    @staticmethod
    def make_update_context_transaction(asset_id, input_id, name, description, read_permissions, write_permissions, auth_user_id, auth_user_public_key):
        return {
            'asset_id': asset_id,
            'input_id': input_id,
            'metadata': {
                'name': name,
                'description': description,
                'read_permissions': read_permissions,
                'write_permissions': write_permissions
            },
            'auth_id': auth_user_id,
            'auth_public_key': auth_user_public_key
        }

    @staticmethod
    def make_update_index_transaction(asset_id, input_id, action, auth_user_id, auth_user_public_key):
        return {
            'asset_id': asset_id,
            'input_id': input_id,
            'metadata': {
                'action': action
            },
            'auth_id': auth_user_id,
            'auth_public_key': auth_user_public_key
        }

    @staticmethod
    def make_update_transaction(asset_id, input_id, context_id, metadata, auth_user_id, auth_user_public_key):
        return {
            'asset_id': asset_id,
            'input_id': input_id,
            'context_id': context_id,
            'metadata': metadata,
            'auth_id': auth_user_id,
            'auth_public_key': auth_user_public_key
        }

    @staticmethod
    def make_update_user_transaction(asset_id, input_id, name, public_key, users_admin, contexts_admin, auth_user_id, auth_user_public_key):
        metadata = {
            'name': name
        }
        if public_key:
            metadata['public_key'] = public_key
        if users_admin:
            metadata['users_admin'] = users_admin
        else:
            metadata['users_admin'] = False
        if contexts_admin:
            metadata['contexts_admin'] = contexts_admin
        else:
            metadata['contexts_admin'] = False
        return {
            'asset_id': asset_id,
            'input_id': input_id,
            'metadata': metadata,
            'auth_id': auth_user_id,
            'auth_public_key': auth_user_public_key
        }

    @staticmethod
    def remove_empty_objects(transaction):
        if isinstance(transaction, dict):
            for key in list(transaction.keys()):
                if isinstance(transaction[key], dict):
                    Transaction.remove_empty_objects(transaction[key])
                    if not transaction[key]:
                        del transaction[key]
                elif isinstance(transaction[key], list):
                    for item in transaction[key]:
                        Transaction.remove_empty_objects(item)
                    transaction[key] = [item for item in transaction[key] if item]
                    if not transaction[key]:
                        del transaction[key]
        elif isinstance(transaction, list):
            for item in transaction:
                Transaction.remove_empty_objects(item)
            transaction = [item for item in transaction if item]
        return transaction

    @staticmethod
    def serialize_transaction(transaction):
        cloned = copy.deepcopy(transaction)
        return json.dumps(cloned, separators=(',', ':'), sort_keys=True)

    @staticmethod
    def sign_transaction(transaction, private_key):
        signed_transaction = copy.deepcopy(transaction)
        Transaction.remove_empty_objects(signed_transaction)
        serialized_transaction = Transaction.serialize_transaction(signed_transaction)
        signed_transaction['signature'] = Ed25519.sign_sha_256(serialized_transaction, private_key)
        return signed_transaction
