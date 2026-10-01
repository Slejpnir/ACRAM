function transaction_id = create_transaction(transactionMap, private_key,id, serverBaseHttp, serviceName)
    transaction_id = "";
    % Import Python modules
    %py.importlib.import_module('nacl.signing');
    %py.importlib.import_module('base58');
    %py.importlib.import_module('base64');
    %py.importlib.import_module('json');
    %py.importlib.import_module('hashlib');
    if nargin < 5 || isempty(serviceName)
        serviceName = 'smartqc';
    end
    serviceName = scalarTextToChar(serviceName, 'serviceName');
    private_key = scalarTextToChar(private_key, 'private_key');
    id = scalarTextToChar(id, 'id');
    % Dynamically import selected Python package (smartqc or contextchain)
    py.importlib.import_module(serviceName);
    py.importlib.import_module([serviceName '.api']);

    apiMod = py.importlib.import_module([serviceName '.api']);
    transactionMod=py.importlib.import_module([serviceName '.transaction']);
    if nargin < 4 || isempty(serverBaseHttp)
        error('create_transaction:MissingServer', ...
            'serverBaseHttp is required. Resolve it from credentials/config before sending.');
    end
    serverBaseHttp = scalarTextToChar(serverBaseHttp, 'serverBaseHttp');
    api    = apiMod.API(serverBaseHttp, serviceName);

    %signed_transaction = transactionStruct;

    %signed_transaction = remove_empty_objects(signed_transaction);
    
    %transactionString= char(py.json.dumps(mapToPyDict(signed_transaction),pyargs('separators', py.tuple({',', ':'}), 'sort_keys', true)));
    %transactionString=jsonencode(signed_transaction);
    % Compute SHA3-256 hash
    %hash = py.hashlib.sha3_256(uint8(transactionString)).digest();

    % Decode Base58 private key
    %keypair = py.nacl.signing.SigningKey(py.base58.b58decode(private_key));

    % Sign the hash
    %signed = keypair.sign(hash);

    % Extract signature and encode it in Base64 URL-safe format
    %signature = base64_urlsafe_encode(uint8(signed.signature));
    %encoded=py.base64.urlsafe_b64encode(signed.signature).decode('utf-8').rstrip('=').replace('+', '-').replace('/', '_');
    
    % Add signature to transaction
    %decoded = encoded.decode('utf-8');  % This is a Python string
    % Convert Python string to MATLAB char
    %decoded = char(encoded);
    % Remove trailing '=' characters using regex
    %decoded = regexprep(decoded, '=+$', '');
    % Replace '+' with '-' and '/' with '_'
    %decoded = strrep(decoded, '+', '-');
    %decoded = strrep(decoded, '/', '_');
    %signed_transaction('signature') = decoded;
    pyCreateTransaction = map2pydict(transactionMap);
    Transaction = transactionMod.Transaction;
    signedCreateTransaction = Transaction.sign_transaction(pyCreateTransaction, private_key);
    % Conversion of large per-user payloads can outlast the SDK's 10-second
    % JWT. Issue it only after conversion/signing, immediately before PUT.
    for attempt = 1:2
        token = generate_token(id, private_key, serviceName);
        response = api.put_transaction(signedCreateTransaction, token);
        [hasError, statusCode] = responseError(response);
        if hasError
            if statusCode == 401 && attempt == 1
                fprintf('[%s] ADI authentication rejected (HTTP 401); retrying once with a fresh token.\n', adiConsoleTimestamp());
                continue;
            end
            if statusCode == 401
                error('create_transaction:ADIAuthenticationFailed', ...
                    'ADI rejected the transaction (HTTP 401) after token refresh. Check ADI credentials and server clock.');
            end
            if statusCode > 0
                error('create_transaction:ADIRequestFailed', ...
                    'ADI rejected the transaction (HTTP %d). No transaction ID was returned.', statusCode);
            end
            error('create_transaction:ADIRequestFailed', ...
                'ADI request failed. No transaction ID was returned.');
        end
        transaction_id = validatedTransactionId(response);
        sleepNoGraphics(1);
        return;
    end
end

function [hasError, statusCode] = responseError(response)
    hasError = false;
    statusCode = 0;
    if ~isa(response, 'py.dict'), return; end
    % Python dictionary keys are not object attributes (hasattr is false).
    hasError = logical(py.operator.contains(response, 'error'));
    if logical(py.operator.contains(response, 'status_code'))
        try
            code = double(response{'status_code'});
            if isscalar(code) && isfinite(code) && code >= 400 && code <= 599 && fix(code) == code
                statusCode = code;
                hasError = true;
            end
        catch
        end
    end
    if hasError && statusCode == 0 && logical(py.operator.contains(response, 'error'))
        message = char(py.str(response{'error'}));
        code = regexp(message, '(?<!\d)([45]\d{2})(?!\d)', 'tokens', 'once');
        if ~isempty(code), statusCode = str2double(code{1}); end
    end
end

function transactionId = validatedTransactionId(response)
    if ~(isa(response, 'py.str') || ischar(response) || (isstring(response) && isscalar(response)))
        error('create_transaction:InvalidResponse', ...
            'ADI returned an unexpected response instead of a transaction ID.');
    end
    transactionId = strtrim(char(response));
    if size(transactionId, 1) ~= 1 || isempty(regexp(transactionId, '^[0-9a-fA-F]{64}$', 'once'))
        error('create_transaction:InvalidResponse', ...
            'ADI did not return a valid 64-character hexadecimal transaction ID.');
    end
    transactionId = lower(transactionId);
end

function ts = adiConsoleTimestamp()
    try
        ts = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    catch
        ts = '';
    end
end

function pyDict = map2pydict(m)
    pyDict = py.dict();
    keys = m.keys();
    for i = 1:length(keys)
        key = scalarTextToChar(keys{i}, 'transaction key');
        value = m(key);
        pyDict{key} = matlab2py(value);
    end
end

function pyValue = matlab2py(value)
    if isa(value, 'containers.Map')
        pyValue = map2pydict(value);
    elseif iscell(value)
        pyValue = py.list();
        for j = 1:numel(value)
            pyValue.append(matlab2py(value{j}));
        end
    elseif isstring(value)
        if isscalar(value)
            pyValue = char(value);
        else
            pyValue = py.list();
            for j = 1:numel(value)
                pyValue.append(char(value(j)));
            end
        end
    elseif ischar(value)
        pyValue = value;
    elseif isnumeric(value)
        if isscalar(value)
            pyValue = value;
        else
            pyValue = py.list();
            for j = 1:numel(value)
                pyValue.append(value(j));
            end
        end
    elseif islogical(value)
        if isscalar(value)
            pyValue = value;
        else
            pyValue = py.list();
            for j = 1:numel(value)
                pyValue.append(value(j));
            end
        end
    else
        pyValue = value;
    end
end

function value = scalarTextToChar(value, valueName)
    if isstring(value)
        if ~isscalar(value)
            error('create_transaction:NonScalarText', '%s must be scalar text.', valueName);
        end
        value = char(value);
    elseif ischar(value)
        % Already Python-compatible text.
    else
        try
            value = char(string(value));
        catch ME
            error('create_transaction:InvalidText', ...
                'Unable to convert %s to text: %s', valueName, ME.message);
        end
    end
end
