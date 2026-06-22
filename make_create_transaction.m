function transaction = make_create_transaction(user_id, context_id, data, metadata, public_key)
    % Initialize the transaction structure
    transaction = struct('user_id', user_id, 'context_id', context_id, 'public_key', public_key);

    % Add optional fields if provided
    if nargin >= 3 && ~isempty(data)
        transaction.data = data;
    end
    if nargin >= 4 && ~isempty(metadata)
        transaction.metadata = metadata;
    end
end