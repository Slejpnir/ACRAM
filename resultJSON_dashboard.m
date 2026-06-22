function response = resultJSON_dashboard(risksColumn, objectName, userColumn, saveToFile, sendToDashboard)
    % Determine severity from risk values
    severity = max(risksColumn);
    % Create the main JSON object using containers.Map.
    data = containers.Map;
        
    data('value') = severity;
    
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
    data('severity') = severityString;
    
    % Timestamp (convert datetime to char for JSON)
    formattedDateTime = datetime('now','Format','y-M-dd HH:mm:ss');
    data('timestamp') = char(formattedDateTime);
    
    % Other fields in the "data" object
    supplData = containers.Map;
    supplData('subject') = formatAcramSubject(objectName);
    
    % Build per-user risk levels
    for i = 1:numel(userColumn)
        % Create a JSON object for each user as a containers.Map
        supplData('user '+string(i)+' risk level') = risksColumn(i);
    end
    
 
    % Assign the nested "data" object to the main JSON
    data('supplementary-details') = supplData;
    
    %jsonStr = jsonencode(data);
    jsonStrPrint=jsonencode(data,"PrettyPrint",true);
    
    % Replace key names with hyphenated versions as required.
    %jsonStr = strrep(jsonStr, 'per_user_risk_levels', 'per-user-risk-levels');
    %jsonStr = strrep(jsonStr, 'user_id', 'user-id');
    %jsonStr = strrep(jsonStr, 'follow_up_actions', 'follow-up-actions');
    %jsonStr = strrep(jsonStr, 'input_indicators', 'input-indicators');
    
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
    if sendToDashboard == 1
        url = 'http://163.162.228.250:5050/message_stream/ACRAM-00001';
    
        % Configure web options
        opts = weboptions( ...
            'MediaType', 'application/json', ...
            'Timeout',   10 );
    
        try
            response = webwrite(url, jsonStrPrint, opts);
        catch ME
            % If it's a timeout, handle gracefully
            if contains(ME.message, 'Timeout') || contains(ME.message, 'timed out')
                warning('HTTP POST timed out after %g seconds. Returning empty response.', opts.Timeout);
                response = [];   % or [] / struct() / whatever default you prefer
            else
                % some other error—rethrow so you see it
                rethrow(ME);
            end
        end
    end
end


