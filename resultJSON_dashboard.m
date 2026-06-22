function response = resultJSON_dashboard(risksColumn, objectName, userColumn, saveToFile, sendToDashboard)
    response = [];
    persistent dashboardExportWarningShown

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
    formattedDateTime = datetime('now', 'Format', 'y-M-dd HH:mm:ss');
    data('timestamp') = char(formattedDateTime);

    % Other fields in the data object
    supplData = containers.Map;
    supplData('subject') = formatAcramSubject(objectName);

    % Build per-user risk levels
    for i = 1:numel(userColumn)
        supplData('user ' + string(i) + ' risk level') = risksColumn(i);
    end

    % Assign the nested data object to the main JSON
    data('supplementary-details') = supplData;
    jsonStrPrint = jsonencode(data, "PrettyPrint", true);

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

    % Send JSON to the dashboard if requested. A dashboard outage must not
    % stop local result generation or ADI export.
    if sendToDashboard == 1
        url = getenv('ACRAM_DASHBOARD_URL');
        if isempty(url)
            url = 'http://163.162.228.250:5050/message_stream/ACRAM-00001';
        end

        opts = weboptions( ...
            'MediaType', 'application/json', ...
            'Timeout', 10);

        try
            response = webwrite(url, jsonStrPrint, opts);
        catch ME
            if isempty(dashboardExportWarningShown)
                fprintf('Dashboard export skipped: Error connecting to %s: %s\n', url, ME.message);
                dashboardExportWarningShown = true;
            end
            response = [];
        end
    end
end
