function assertsList = resultJSON(risksColumn, objectName, userColumn, saveToFile, sendToDataSpace, inputAssetsIds, varargin)
    % Parse optional arguments: [auth_id_opt, private_key_opt, graphs_for_object_opt, cfgPath_opt, indicator_labels_opt]
    auth_id_opt = [];
    private_key_opt = [];
    graphs_for_object_opt = [];
    cfgPath_opt = [];
    indicator_labels_opt = [];
    if numel(varargin) >= 1 && ~isempty(varargin{1})
        auth_id_opt = varargin{1};
    end
    if numel(varargin) >= 2 && ~isempty(varargin{2})
        private_key_opt = varargin{2};
    end
    if numel(varargin) >= 3
        graphs_for_object_opt = varargin{3};
    end
    if numel(varargin) >= 4
        cfgPath_opt = varargin{4};
    end
    if numel(varargin) >= 5
        indicator_labels_opt = varargin{5};
    end
    userColumn = resultJsonUserColumn(userColumn);
    risksColumn = risksColumn(:);
    accessMask = resultJsonAccessMask(cfgPath_opt, objectName, userColumn, numel(risksColumn));
    % Determine severity from risk values
    [severity, maxRiskIdx] = resultJsonSeverityAndFocus(risksColumn, accessMask);
    % Create the main JSON object using containers.Map.
    data = containers.Map;
    % Resolve ADI credentials, context_id, and endpoint from config.
    adiInfo = [];
    try
        adiInfo = resolve_adi_connection(cfgPath_opt);
    catch ME
        if sendToDataSpace == 1
            rethrow(ME);
        end
    end
    contextId = "";
    authPublicKey = "";
    auth_id = "";
    private_key = "";
    try
        if ~isempty(adiInfo)
            contextId = adiInfo.contextIdComponent;
            authPublicKey = adiInfo.authPublicKey;
            auth_id = adiInfo.authId;
            private_key = adiInfo.privateKey;
        end
    catch ME
        if sendToDataSpace == 1
            rethrow(ME);
        end
    end
    if sendToDataSpace == 1 && strlength(contextId) == 0
        error('resultJSON:MissingContextId', ...
            'Cannot create component transaction: context_id_component is empty. Check credentialsFileName in config.');
    end
    data('context_id') = contextId;

    % Auth parameters: prefer credentials file; allow optional overrides.
    if nargin >= 7 && ~isempty(auth_id_opt)
        auth_id = auth_id_opt;
    end
    if nargin >= 8 && ~isempty(private_key_opt)
        private_key = private_key_opt;
    end
    
    % Create the nested "data" field.
    dataData = containers.Map;
    dataData('type') = 'Component level access control risk';
    dataData('value') = severity;
    
    % Determine severity string
    if severity < 0.25
        severityString = 'GREEN';
    elseif severity < 0.5
        severityString = 'YELLOW';
    elseif severity < 0.75
        severityString = 'ORANGE';
    else
        severityString = 'RED';
    end
    dataData('severity') = severityString;
    
    % Timestamp (convert datetime to char for JSON)
    formattedDateTime = datetime('now','Format','y-M-dd HH:mm:ss');
    dataData('timestamp') = char(formattedDateTime);
    
    % Other fields in the "data" object
    dataData('subject') = formatAcramSubject(objectName);
    dataData('source') = 'ACRAM';
    
    % Build per-user risk levels as a cell array
    perUserRiskLevels = {};
    for i = 1:numel(userColumn)
        % Create a JSON object for each user as a containers.Map
        userData = containers.Map;
        userData('user-id') = userColumn(i);
        if i <= numel(accessMask) && ~accessMask(i)
            userData('level') = -1;
        else
            userData('level') = risksColumn(i);
        end
        perUserRiskLevels{end+1} = userData; %#ok<AGROW>
    end
    dataData('per-user-risk-levels') = perUserRiskLevels;
    
    % Build input indicators as a cell array
    inputIndicators = {};
    for i = 1:numel(inputAssetsIds)
        indicator = containers.Map;
        indicator('asset-id') = inputAssetsIds(i);
        inputIndicators{end+1} = indicator; %#ok<AGROW>
    end
    dataData('input-indicators') = inputIndicators;
    
    % Assign the nested "data" object to the main JSON
    data('data') = dataData;
    
    % Metadata field as a nested JSON object
    metadata = containers.Map;
    indicatorSuffix = '';
    try
        labels = strings(0,1);
        % Prefer human-readable indicator labels when provided.
        if ~isempty(indicator_labels_opt)
            if iscell(indicator_labels_opt)
                for ii = 1:numel(indicator_labels_opt)
                    lbl = string(indicator_labels_opt{ii});
                    if strlength(lbl) > 0
                        labels(end+1,1) = lbl; %#ok<AGROW>
                    end
                end
            else
                for ii = 1:numel(indicator_labels_opt)
                    lbl = string(indicator_labels_opt(ii));
                    if strlength(lbl) > 0
                        labels(end+1,1) = lbl; %#ok<AGROW>
                    end
                end
            end
        end
        % Fallback to IDs if labels are not available.
        if isempty(labels)
            if iscell(inputAssetsIds)
                for ii = 1:numel(inputAssetsIds)
                    sid = string(inputAssetsIds{ii});
                    if strlength(sid) > 0
                        labels(end+1,1) = sid; %#ok<AGROW>
                    end
                end
            else
                for ii = 1:numel(inputAssetsIds)
                    sid = string(inputAssetsIds(ii));
                    if strlength(sid) > 0
                        labels(end+1,1) = sid; %#ok<AGROW>
                    end
                end
            end
        end
        if ~isempty(labels)
            labels = unique(labels, 'stable');
            maxShown = min(numel(labels), 10);
            shown = labels(1:maxShown);
            if numel(labels) > maxShown
                indicatorSuffix = sprintf(' TELEMETRY indicators affecting this risk: %s (+%d more).', char(strjoin(shown, ', ')), numel(labels) - maxShown);
            else
                indicatorSuffix = sprintf(' TELEMETRY indicators affecting this risk: %s.', char(strjoin(shown, ', ')));
            end
        end
    catch
    end
    % If we have required globals, compute main problems for the highest-risk user
    try
        % graphs_for_object_opt is an optional cell array {user} of digraphs
        % corresponding to the current object
        hasGraphs = (nargin >= 9) && ~isempty(graphs_for_object_opt);
        threshold = 0.7;
        try
            threshold = evalin('base','FOLLOW_UP_THRESHOLD');
        catch
        end
        focusUser = "unknown";
        try
            if maxRiskIdx >= 1 && maxRiskIdx <= numel(userColumn)
                focusUser = string(userColumn(maxRiskIdx));
            end
        catch
        end
        if hasGraphs && maxRiskIdx >= 1
            try
                gUser = graphs_for_object_opt{maxRiskIdx};
                probs = getProblemsList(gUser, threshold);
                if ~isempty(probs)
                    probsStr = strjoin(string(probs), ', ');
                    metadata('follow-up-actions') = sprintf('For user %s, consider improving the following factors: %s%s', char(focusUser), probsStr, indicatorSuffix);
                else
                    metadata('follow-up-actions') = sprintf('For user %s, consider improving the following factors: (no factors exceeded threshold)%s', char(focusUser), indicatorSuffix);
                end
            catch
                metadata('follow-up-actions') = sprintf('For user %s, consider improving the following factors: (unavailable)%s', char(focusUser), indicatorSuffix);
            end
        else
            metadata('follow-up-actions') = sprintf('For user %s, consider improving the following factors: (unavailable)%s', char(focusUser), indicatorSuffix);
        end
    catch
        metadata('follow-up-actions') = sprintf('Consider improving the following factors: (error computing factors)%s', indicatorSuffix);
    end
    data('metadata') = metadata;
    
    % Other top-level fields
    data('auth_public_key') = authPublicKey;
    data('auth_id') = auth_id;
    
    % Encode the containers.Map as a JSON string (always build for debug printing)
    jsonStrPrint = jsonencode(data, "PrettyPrint", true);

    % Debug mode: print transaction before sending to ADI
    debugOn = false;
    try
        debugOn = evalin('base','exist(''DEBUG_ADI'',''var'') && ~isempty(DEBUG_ADI) && logical(DEBUG_ADI)');
    catch
    end
    if debugOn
        fprintf("[%s] ADI DEBUG resultJSON payload (%s):\n%s\n", resultJsonConsoleTimestamp(), objectName, jsonStrPrint);
    end
    
    % Save JSON to file if requested
    if saveToFile == 1
        fileName = strcat('acram_', objectName, '_output.json');
        fileID = fopen(fileName, 'w');
        if fileID == -1
            error('Failed to create the JSON file.');
        end
        fwrite(fileID, jsonStrPrint, 'char');
        fclose(fileID);
    end
    
    % Send JSON to data space if requested
    if sendToDataSpace == 1
        if isempty(adiInfo)
            adiInfo = resolve_adi_connection(cfgPath_opt);
        end
        serverBaseHttp = adiInfo.serverBaseHttp;
        serviceName = adiInfo.serviceName;

        if strlength(string(private_key)) == 0
            error('resultJSON:MissingPrivateKey', ...
                'Cannot create component transaction: private_key is empty. Check credentialsFileName in config.');
        end
        transaction_id = create_transaction(data, private_key, auth_id, serverBaseHttp, serviceName);
        if strlength(string(transaction_id)) > 0
            fprintf('[%s] Sent ADI component transaction: object=%s, severity=%s, value=%.3f, transactionId=%s\n', ...
                resultJsonConsoleTimestamp(), char(string(objectName)), severityString, severity, char(string(transaction_id)));
        end
        assertsList=transaction_id;
    else
        assertsList=[];
    end
end

function ts = resultJsonConsoleTimestamp()
    try
        ts = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    catch
        ts = '';
    end
end

function [severity, maxRiskIdx] = resultJsonSeverityAndFocus(risksColumn, accessMask)
    severity = 0;
    maxRiskIdx = 1;
    try
        risksColumn = risksColumn(:);
        nRisks = numel(risksColumn);
        if isempty(risksColumn)
            return;
        end
        mask = true(nRisks, 1);
        if numel(accessMask) >= nRisks
            mask = logical(accessMask(1:nRisks));
        end
        candidateIdx = find(mask);
        if isempty(candidateIdx)
            return;
        end
        [severity, localIdx] = max(risksColumn(candidateIdx));
        maxRiskIdx = candidateIdx(localIdx);
    catch
        try
            [severity, maxRiskIdx] = max(risksColumn);
        catch
            severity = 0;
            maxRiskIdx = 1;
        end
    end
end

function userColumn = resultJsonUserColumn(rawUserColumn)
    try
        if ischar(rawUserColumn)
            userColumn = string(cellstr(rawUserColumn));
        elseif iscell(rawUserColumn)
            userColumn = string(rawUserColumn(:));
        else
            userColumn = string(rawUserColumn(:));
        end
    catch
        userColumn = string(rawUserColumn);
        userColumn = userColumn(:);
    end
end

function accessMask = resultJsonAccessMask(cfgPathOpt, objectName, userColumn, nRisks)
    accessMask = true(max(numel(userColumn), nRisks), 1);
    try
        cfg = resultJsonConfig(cfgPathOpt);
        if isempty(cfg) || ~isstruct(cfg) || ~isfield(cfg, 'ACL') || ~isfield(cfg, 'objects')
            return;
        end

        objIdx = resultJsonObjectIndex(cfg.objects, objectName);
        if objIdx <= 0
            return;
        end

        accessMask(:) = false;
        aclStruct = cfg.ACL;
        aclKeys = fieldnames(aclStruct);
        for k = 1:numel(aclKeys)
            [userIdx, aclObjectIdx] = resultJsonAclKeyToIndices(aclKeys{k});
            if userIdx <= 0 || aclObjectIdx ~= objIdx || userIdx > numel(accessMask)
                continue;
            end
            if resultJsonAclEntryAllowsAccess(aclStruct.(aclKeys{k}))
                accessMask(userIdx) = true;
            end
        end
    catch
        accessMask = true(max(numel(userColumn), nRisks), 1);
    end
end

function cfg = resultJsonConfig(cfgPathOpt)
    cfg = [];
    try
        if isempty(cfgPathOpt)
            return;
        end
        if isstruct(cfgPathOpt)
            cfg = cfgPathOpt;
        else
            cfg = config_manager(string(cfgPathOpt));
        end
    catch
        cfg = [];
    end
end

function objIdx = resultJsonObjectIndex(objects, objectName)
    objIdx = 0;
    try
        if iscell(objects), objects = [objects{:}]; end
        if istable(objects), objects = table2struct(objects); end
        target = lower(strtrim(string(objectName)));
        for j = 1:numel(objects)
            names = strings(0,1);
            try
                if isfield(objects(j), 'Name')
                    names(end+1,1) = string(objects(j).Name); %#ok<AGROW>
                end
            catch
            end
            try
                if isfield(objects(j), 'SymbolicName')
                    names(end+1,1) = string(objects(j).SymbolicName); %#ok<AGROW>
                end
            catch
            end
            names = lower(strtrim(names(strlength(names) > 0)));
            if any(names == target)
                objIdx = j;
                return;
            end
        end
    catch
        objIdx = 0;
    end
end

function [userIdx, objectIdx] = resultJsonAclKeyToIndices(key)
    try
        [src, dst] = strtok(char(key), '_');
        src = strrep(src, 'x', '');
        dst = strrep(dst, '_', '');
        userIdx = str2double(src);
        objectIdx = str2double(dst);
        if isnan(userIdx), userIdx = 0; end
        if isnan(objectIdx), objectIdx = 0; end
    catch
        userIdx = 0;
        objectIdx = 0;
    end
end

function tf = resultJsonAclEntryAllowsAccess(entry)
    tf = true;
    try
        if isstruct(entry) && isfield(entry, 'Permission')
            permission = lower(strtrim(string(entry.Permission)));
            tf = strlength(permission) > 0 && permission ~= "none";
        end
    catch
        tf = true;
    end
end
