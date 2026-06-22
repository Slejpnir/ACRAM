function response = send_request(method, url, data, headers)
    try
        % Create weboptions including the header fields from the cell array
        options = weboptions('Timeout', 30, 'HeaderFields', headers);

        % Handle different HTTP methods
        switch upper(method)
            case 'PUT'
                jsonStr = jsonencode(data);
                response = webwrite(url, jsonStr, options);
            case 'GET'
                response = webread(url, options);
            otherwise
                error('Unsupported HTTP method: %s', method);
        end
    catch ME
        % Return error information as a cell array
        if contains(ME.message, '400')
            response = {'error', 'Bad request', 'details', ME.message};
        elseif contains(ME.message, '404')
            response = {'error', 'Not found', 'details', ME.message};
        elseif contains(ME.message, '500')
            response = {'error', 'Internal server error', 'details', ME.message};
        else
            response = {'error', sprintf('Other error occurred: %s', ME.message)};
        end
    end