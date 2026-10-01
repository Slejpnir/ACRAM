function [source, accepted] = adi_transaction_source(transaction, config)
%ADI_TRANSACTION_SOURCE Route configured contexts before source inference.
source = "";
accepted = false;
if ~isstruct(transaction) || ~isscalar(transaction) || ...
        ~isfield(transaction, 'data') || ~isstruct(transaction.data) || ...
        ~isscalar(transaction.data)
    return;
end
data = transaction.data;
% A context schema is a definition, never an anomaly observation.
if isfield(data, 'context_data') || isfield(data, 'context_metadata'), return; end
[baconIds, atcIds, contextsOnly] = adi_input_contexts(config);
contextId = "";
if isfield(transaction, 'context_id')
    contextId = lower(strtrim(string(transaction.context_id)));
elseif isfield(transaction, 'contextId')
    contextId = lower(strtrim(string(transaction.contextId)));
end
if ~isscalar(contextId), return; end
if any(contextId == baconIds)
    source = "BACON";
elseif any(contextId == atcIds)
    source = "ATC Network Event";
elseif contextsOnly
    return;
elseif isfield(data, 'source')
    source = string(data.source);
end
if ~isscalar(source), return; end
if strlength(source) == 0 && isfield(data, 'traffic_participants') && isfield(data, 'root_cause')
    source = "NAD";
end
accepted = true;
end
