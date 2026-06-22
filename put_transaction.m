function response = put_transaction(base_url, blockchain, transaction)
    % Construct the URL
    url = sprintf('%s/%s/transaction', base_url, blockchain);
    
    % Set headers as a cell array
    headers = {'Content-Type', 'application/json'};
    
    % Send the request
    response = send_request('PUT', url, transaction, headers);
end