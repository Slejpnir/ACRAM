function assertsID = aggregatedIndicator(aggregatedRisk,tablerisks, sendToDataSpace, inputAssetsIds,saveToFile, varargin)
    % Optional cfgPath_opt (config file path)
    cfgPath_opt = [];
    if ~isempty(varargin)
        cfgPath_opt = varargin{1};
    end
    % Determine severity from risk values
    threshold=0.5;
    severity = aggregatedRisk;
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
    authId = "";
    privateKey = "";
    try
        if ~isempty(adiInfo)
            contextId = adiInfo.contextIdAggregated;
            authPublicKey = adiInfo.authPublicKey;
            authId = adiInfo.authId;
            privateKey = adiInfo.privateKey;
        end
    catch ME
        if sendToDataSpace == 1
            rethrow(ME);
        end
    end
    if sendToDataSpace == 1 && strlength(contextId) == 0
        error('aggregatedIndicator:MissingContextId', ...
            'Cannot create aggregated transaction: context_id_aggregated is empty. Check credentialsFileName in config.');
    end
    data('context_id') = contextId;
    
    % Create the nested "data" field.
    dataData = containers.Map;
    dataData('type') = 'Aggregated access control risk';
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
    %dataData('subject') = 'Entire system';
    dataData('source') = 'ACRAM';
    
    % Build per-user risk levels as a cell array
    perUserRiskLevels = {};
    for i = 1:height(tablerisks)
        % Assuming the first column contains the row name
        rowName = tablerisks{i, 1};
        % Loop over each numeric column (from the 2nd column onward)
        for j = 2:width(tablerisks)
            value = tablerisks{i, j};
            if value > threshold
        % Create a JSON object for each user as a containers.Map
                userData = containers.Map;
                userData('user-id') = string(rowName);
                userData('device-name') = tablerisks.Properties.VariableNames{j};
                userData('level')=value;
                perUserRiskLevels{end+1} = userData; %#ok<AGROW>
            end
        end
    end
    dataData('most_risky_user_device_pairs') = perUserRiskLevels;
    
    % Build input indicators as a cell array
    inputIndicators = {};
    for i = 1:numel(inputAssetsIds)
        indicator = containers.Map;
        indicator('context-id') = inputAssetsIds(i);
        inputIndicators{end+1} = indicator; %#ok<AGROW>
    end
    %dataData('input-indicators') = inputIndicators;
    
    % Assign the nested "data" object to the main JSON
    data('data') = dataData;
    
    % Metadata field as a nested JSON object
    metadata = containers.Map;
    followUp = 'TBD';
    try
        ids = strings(0,1);
        if iscell(inputAssetsIds)
            for ii = 1:numel(inputAssetsIds)
                sid = string(inputAssetsIds{ii});
                if strlength(sid) > 0
                    ids(end+1,1) = sid; %#ok<AGROW>
                end
            end
        else
            for ii = 1:numel(inputAssetsIds)
                sid = string(inputAssetsIds(ii));
                if strlength(sid) > 0
                    ids(end+1,1) = sid; %#ok<AGROW>
                end
            end
        end
        if ~isempty(ids)
            ids = unique(ids, 'stable');
            % Keep follow-up compact to avoid oversized metadata payloads
            maxShown = min(numel(ids), 10);
            shown = ids(1:maxShown);
            if numel(ids) > maxShown
                followUp = sprintf('TELEMETRY indicators affecting this aggregated risk: %s (+%d more)', char(strjoin(shown, ', ')), numel(ids) - maxShown);
            else
                followUp = sprintf('TELEMETRY indicators affecting this aggregated risk: %s', char(strjoin(shown, ', ')));
            end
        end
    catch
    end
    metadata('follow_up_actions') = followUp;
    data('metadata') = metadata;
    
    % Other top-level fields
    data('auth_public_key') = authPublicKey;
    data('auth_id') = authId;
    
    % Encode the containers.Map as a JSON string (always build for debug printing)
    jsonStrPrint = jsonencode(data, "PrettyPrint", true);

    % Debug mode: print transaction before sending to ADI
    debugOn = false;
    try
        debugOn = evalin('base','exist(''DEBUG_ADI'',''var'') && ~isempty(DEBUG_ADI) && logical(DEBUG_ADI)');
    catch
    end
    if debugOn
        fprintf("[%s] ADI DEBUG aggregatedIndicator payload:\n%s\n", aggregatedIndicatorConsoleTimestamp(), jsonStrPrint);
    end
    
    % Replace key names with hyphenated versions as required.
    %jsonStr = strrep(jsonStr, 'per_user_risk_levels', 'per-user-risk-levels');
    %jsonStr = strrep(jsonStr, 'user_id', 'user-id');
    %jsonStr = strrep(jsonStr, 'follow_up_actions', 'follow-up-actions');
    %jsonStr = strrep(jsonStr, 'input_indicators', 'input-indicators');
    
    % Save JSON to file if requested
    if saveToFile == 1
         fileName = strcat('acram_aggregated_output.json');
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

        if strlength(string(privateKey)) == 0
            error('aggregatedIndicator:MissingPrivateKey', ...
                'Cannot create aggregated transaction: private_key is empty. Check credentialsFileName in config.');
        end
        transaction_id = create_transaction(data, privateKey, data('auth_id'), serverBaseHttp, serviceName);
        if strlength(string(transaction_id)) > 0
            fprintf('[%s] Sent ADI aggregated transaction: severity=%s, value=%.3f, transactionId=%s\n', ...
                aggregatedIndicatorConsoleTimestamp(), severityString, severity, char(string(transaction_id)));
        end
        assertsID=transaction_id;
    else
        assertsID=[];
    end
end

function ts = aggregatedIndicatorConsoleTimestamp()
    try
        ts = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    catch
        ts = '';
    end
end
