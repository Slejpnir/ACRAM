function [currentWorstStatus, worstTimestamp, worstConfidence] = monitorFile(filePath, lastReadPosition, previousWorstStatus)
    % Define the status hierarchy
    statusHierarchy = ["OFF", "YELLOW", "ORANGE", "RED"];
    currentWorstStatus = "OFF";
    worstTimestamp="00:00:00";
    worstConfidence=0;
    % Memory-map the file
    m = memmapfile(filePath, 'Writable', false, 'Format', 'uint8');
    
    % Check the file size and read new data if any
    fileSize = numel(m.Data);
    if lastReadPosition >= fileSize
        currentWorstStatus = previousWorstStatus;

        return;  % No new data to process
    end

    % Read new data as a character array
    newData = char(m.Data(lastReadPosition:fileSize))';
    %debugLogFile = fopen('debug_log.txt', 'a');
    %if debugLogFile == -1
    %    error('Unable to open debug log file.');
    %end

    % Split new data into lines and analyze each line
    lines = strsplit(newData, '\n');
    for i = 1:numel(lines)
        line = lines{i};
        %disp(line);
        % Check for a status change using regular expression
        %status = regexp(line, '"\s*(OFF|YELLOW|ORANGE|RED)\s*"', 'tokens', 'once');
        tokens = regexp(line, 'nadEvent --> b''{"([\d-]+ [\d:]+)":\s*"(\s*[A-Z]+\s*)",\s*"     confidence":\s*"([\d.]+)"', 'tokens', 'once');
        
        % Pattern to match the timestamp
        %timestamp_pattern = '\"(\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})\"';
        
        % Pattern to match the color (OFF, RED, or YELLOW)
        %color_pattern = '\"(\s*(?:OFF|RED|ORANGE|YELLOW)\s*)\"';
        
        % Pattern to match the confidence value
        %confidence_pattern = '"     confidence":\s*"([0-9.]+)"';
        % Example usage:
        %timestamp = regexp(line, timestamp_pattern, 'tokens', 'once');
        %status = regexp(line, color_pattern, 'tokens', 'once');
        %confidence = regexp(line, confidence_pattern, 'tokens', 'once');
        if isempty(tokens) 
%            fprintf(debugLogFile, 'Line skipped (no match): %s\n', line);
            continue;  % Skip lines that don't match the expected format
        end
        %timestamp = timestamp{1};
        %status = status{1};
        %confidence = confidence{1};
        timestamp = tokens{1};
        status = strtrim(tokens{2});
        confidence = str2double(tokens{3});
        %fprintf(debugLogFile, 'Processed Line - Timestamp: %s, Status: %s, Confidence: %.2f\n', timestamp, status, confidence);
        if ~isempty(status)
            % Find the hierarchy index for the current worst and detected status
            if i==numel(lines)
               worstConfidence = confidence;
               worstTimestamp=timestamp;
            end
            currentIndex = find(statusHierarchy == currentWorstStatus);
            detectedIndex = find(statusHierarchy == status);

            % Update the worst status if the new status is worse
            if detectedIndex >= currentIndex
                currentWorstStatus = status;
                worstTimestamp = timestamp;
                worstConfidence = confidence;
                disp(['New worst status detected: ', currentWorstStatus]);
            end
        end
    end
    %fclose(debugLogFile);
end
