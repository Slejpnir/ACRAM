function info = resolve_adi_connection(cfgOpt)
%RESOLVE_ADI_CONNECTION Resolve credentials, context IDs, and REST endpoint.
%   cfgOpt can be a config struct, a config JSON filename, or empty. The
%   returned struct contains credentials and derived REST routing fields.

info = struct( ...
    'credentialsFile', "ws_credentials.json", ...
    'credentials', [], ...
    'envName', "", ...
    'authId', "", ...
    'authPublicKey', "", ...
    'privateKey', "", ...
    'contextIdComponent', "", ...
    'contextIdAggregated', "", ...
    'serverBaseHttp', "", ...
    'serviceName', "smartqc");

cfg = [];
if nargin >= 1 && ~isempty(cfgOpt)
    if isstruct(cfgOpt)
        cfg = cfgOpt;
    else
        cfgText = fileread(string(cfgOpt));
        cfg = jsondecode(cfgText);
    end
elseif exist('config_Nokia_robot_CVE_2025.json', 'file') == 2
    cfg = jsondecode(fileread('config_Nokia_robot_CVE_2025.json'));
end

if isstruct(cfg)
    if isfield(cfg, 'env') && ~isempty(cfg.env)
        info.envName = lower(string(cfg.env));
    end
    if isfield(cfg, 'credentialsFileName') && strlength(string(cfg.credentialsFileName)) > 0
        info.credentialsFile = string(cfg.credentialsFileName);
    end
end

if exist(info.credentialsFile, 'file') ~= 2
    error('resolve_adi_connection:CredentialsMissing', ...
        'Credentials file not found: %s', char(info.credentialsFile));
end

try
    info.credentials = jsondecode(fileread(info.credentialsFile));
catch ME
    error('resolve_adi_connection:CredentialsInvalid', ...
        'Credentials JSON invalid in file %s: %s', char(info.credentialsFile), ME.message);
end

requiredFields = {'websocket_address', 'user_id', 'private_key'};
for idx = 1:numel(requiredFields)
    fieldName = requiredFields{idx};
    if ~isfield(info.credentials, fieldName) || strlength(string(info.credentials.(fieldName))) == 0
        error('resolve_adi_connection:CredentialsInvalid', ...
            'Credentials file %s is missing required field "%s".', char(info.credentialsFile), fieldName);
    end
end

info.authId = string(info.credentials.user_id);
info.privateKey = string(info.credentials.private_key);
if isfield(info.credentials, 'public_key') && strlength(string(info.credentials.public_key)) > 0
    info.authPublicKey = string(info.credentials.public_key);
else
    info.authPublicKey = info.authId;
end
if isfield(info.credentials, 'context_id_component')
    info.contextIdComponent = string(info.credentials.context_id_component);
end
if isfield(info.credentials, 'context_id_aggregated')
    info.contextIdAggregated = string(info.credentials.context_id_aggregated);
end

addr = string(info.credentials.websocket_address);
base = regexprep(regexprep(addr, '^ws://', 'http://'), '^wss://', 'https://');
toks = regexp(base, '^(https?)://([^/:]+)(?::(\d+))?', 'tokens', 'once');
if isempty(toks)
    error('resolve_adi_connection:InvalidWebsocketAddress', ...
        'Invalid websocket_address in %s: %s', char(info.credentialsFile), char(addr));
end

scheme = string(toks{1});
host = string(toks{2});
info.serverBaseHttp = scheme + "://" + host;
if numel(toks) >= 3 && ~isempty(toks{3})
    info.serverBaseHttp = info.serverBaseHttp + ":" + string(toks{3});
end

if contains(addr, "/contextchain/") || contains(info.envName, "telco") || contains(info.envName, "antonov")
    info.serviceName = "contextchain";
else
    info.serviceName = "smartqc";
end

if info.serviceName == "smartqc"
    info.serverBaseHttp = scheme + "://" + host + ":8080";
elseif contains(info.envName, "antonov")
    info.serverBaseHttp = scheme + "://" + host + ":83";
end
end
