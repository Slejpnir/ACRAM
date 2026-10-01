function filters = adi_subscription_filters(config, sources)
%ADI_SUBSCRIPTION_FILTERS Include source-less telemetry from existing contexts.
[baconIds, atcIds, contextsOnly] = adi_input_contexts(config);
contextIds = unique([baconIds; atcIds], 'stable');
sourceFilter = containers.Map({'data.source'}, ...
    {containers.Map({'$in'}, {sources})});
if isempty(contextIds)
    filters = {sourceFilter};
    return;
end
contextFilter = containers.Map({'context_id'}, ...
    {containers.Map({'$in'}, {cellstr(contextIds)})});
if contextsOnly
    filters = {contextFilter};
else
    filters = {containers.Map({'$or'}, {{sourceFilter, contextFilter}})};
end
end
