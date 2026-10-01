function [baconIds, atcIds, contextsOnly] = adi_input_contexts(config)
%ADI_INPUT_CONTEXTS Read existing telemetry context IDs without ADI writes.
% adiInputContexts.bacon/.atc accept a string or an array of strings.
% adiInputContextsOnly restricts subscriptions and callbacks to those IDs.
baconIds = strings(0,1);
atcIds = strings(0,1);
contextsOnly = false;
if ~isstruct(config) || ~isscalar(config), return; end
if isfield(config, 'adiInputContextsOnly')
    raw = config.adiInputContextsOnly;
    if islogical(raw) || isnumeric(raw)
        assert(isscalar(raw), 'ACRAM:InvalidInputContexts', ...
            'adiInputContextsOnly must be one boolean.');
        contextsOnly = logical(raw);
    else
        value = lower(strtrim(string(raw)));
        assert(isscalar(value) && any(value == ["true","false","on","off","1","0"]), ...
            'ACRAM:InvalidInputContexts', 'adiInputContextsOnly must be one boolean.');
        contextsOnly = any(value == ["true","on","1"]);
    end
end
if isfield(config, 'adiInputContexts')
    routes = config.adiInputContexts;
    assert(isstruct(routes) && isscalar(routes), 'ACRAM:InvalidInputContexts', ...
        'adiInputContexts must contain bacon and/or atc context IDs.');
    baconIds = readIds(routes, 'bacon');
    atcIds = readIds(routes, 'atc');
end
assert(isempty(intersect(baconIds, atcIds)), 'ACRAM:InvalidInputContexts', ...
    'A telemetry context cannot be assigned to both BACON and ATC.');
assert(~contextsOnly || ~isempty([baconIds; atcIds]), 'ACRAM:InvalidInputContexts', ...
    'adiInputContextsOnly requires at least one configured context ID.');
end

function ids = readIds(routes, name)
ids = strings(0,1);
if ~isfield(routes, name) || isempty(routes.(name)), return; end
ids = lower(strtrim(string(routes.(name))));
ids = unique(ids(:), 'stable');
valid = arrayfun(@(id) ~isempty(regexp(char(id), '^[0-9a-f]{64}$', 'once')), ids);
assert(all(valid), 'ACRAM:InvalidInputContexts', ...
    'adiInputContexts.%s must contain 64-character hexadecimal context IDs.', name);
end
