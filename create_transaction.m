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
    % Generate JWT token using selected Python service (smartqc / contextchain)
    token = generate_token(id, private_key, serviceName);
    pyCreateTransaction = map2pydict(transactionMap);
    Transaction = transactionMod.Transaction;
    signedCreateTransaction = Transaction.sign_transaction(pyCreateTransaction, private_key);
    response = api.put_transaction(signedCreateTransaction,token);
    sleepNoGraphics(1);
    % Process response
    if py.hasattr(response, 'error')
        fprintf('[%s] ADI transaction error: %s, Details: %s\n', adiConsoleTimestamp(), char(response.error), char(py.getattr(response, 'details', 'No details')));
    else
        transaction_id=char(response);
    end
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
