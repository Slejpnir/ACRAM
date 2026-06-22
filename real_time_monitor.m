function real_time_monitor(action, varargin)
%REAL_TIME_MONITOR Centralized real-time monitoring logic.
%   Usage:
%     real_time_monitor('start', realTimeMode, env_new, Risks, nUsers, nObjects, ACL, objects, testInputParametersGlobal, intermediateNodesGlobal, impacts, objectsNames, graphArray, subjects, OVLP, NT, config)
%     real_time_monitor('stop')
%     real_time_monitor('request_stop')  % create console stop-file request
%     real_time_monitor('reset')
%     real_time_monitor('request_reset') % create console reset-file request

persistent monitorFig stopFlag wsClient stopTimer
persistent initialRisks initialImpacts initialObjects initialNUsers initialNObjects
persistent initialObjectsNames initialGraphArray initialConfig
persistent adiCallbackContext

switch lower(action)
    case 'start'
        if numel(varargin) < 11
            error('real_time_monitor:InvalidArguments', ...
                'Start requires at least 11 arguments after the action.');
        end
        realTimeMode = varargin{1};
        env_new = varargin{2};
        Risks = varargin{3};
        nUsers = varargin{4};
        nObjects = varargin{5};
        ACL = varargin{6};
        objects = varargin{7};
        testInputParametersGlobal = varargin{8};
        intermediateNodesGlobal = varargin{9};
        impacts = varargin{10};
        objectsNames = varargin{11};

        % Optional args:
        %   12: graphArray (current callers)
        %   13-16: subjects, OVLP, NT, config
        %   17: runInForeground (legacy/unused)
        % A scalar logical/numeric 12th argument is also accepted as the
        % legacy runInForeground value.
        graphArrayArg = [];
        subjectsArg = [];
        ovlpArg = [];
        ntArg = [];
        configArg = [];
        runInForeground = false;
        nextArg = 12;
        if numel(varargin) >= nextArg
            candidate = varargin{nextArg};
            if islogical(candidate) || (isnumeric(candidate) && isscalar(candidate))
                runInForeground = logical(candidate);
                nextArg = nextArg + 1;
            else
                graphArrayArg = candidate;
                nextArg = nextArg + 1;
            end
        end
        if numel(varargin) >= nextArg + 3
            subjectsArg = varargin{nextArg};
            ovlpArg = varargin{nextArg + 1};
            ntArg = varargin{nextArg + 2};
            configArg = varargin{nextArg + 3};
            nextArg = nextArg + 4;
        end
        if numel(varargin) >= nextArg
            runInForeground = logical(varargin{nextArg});
        end

        initialRisks = Risks;
        initialImpacts = impacts;
        initialObjects = objects;
        initialNUsers = nUsers;
        initialNObjects = nObjects;
        initialObjectsNames = objectsNames;
        initialGraphArray = graphArrayArg;
        initialConfig = configArg;
        
        % If a previous WebSocket client exists, ensure it is stopped
        try
            if ~isempty(wsClient) && isvalid(wsClient)
                wsClient.disconnect();
            end
        catch ME
            fprintf('Previous WebSocket disconnect failed: %s\n', ME.message);
        end
        wsClient = [];
        stopConsoleStopWatcher(stopTimer);
        stopTimer = [];
        clearConsoleStopRequest();
        clearConsoleResetRequest();
        stopTimer = startConsoleStopWatcher();

        % Initialize status dictionary
        statusHierarchy = ["OFF", "YELLOW", "ORANGE", "RED"];
        statusDict = containers.Map();
        statusDict("OFF") = 0;
        statusDict("YELLOW") = 0.33;
        statusDict("ORANGE") = 0.66;
        statusDict("RED") = 1;
        % Handle different monitoring modes
        if realTimeMode == "local"
            % Local monitoring mode
            filePath = 'snapshot_NAD.txt';
            lastReadPosition = 1;
            currentWorstStatus = "OFF";
            RisksRT = Risks;
            csvFileName = 'risksRT.csv';
            if isfile(csvFileName)
                delete(csvFileName);
            end
            file = fopen(csvFileName, 'a');
            if file == -1
                error('real_time_monitor:FileOpenFailed', 'Unable to open %s for writing.', csvFileName);
            end
            fileCleanup = onCleanup(@() closeFileIfOpen(file));
            fprintf(file, "%s,", "User");
            for i = 1:nObjects
                fprintf(file, "%s,", objectsNames(i));
            end
            fprintf(file, "\n");
            disp('Starting continuous monitoring...');
            monitorFig = figure;
            figCleanup = onCleanup(@() closeFigureIfValid(monitorFig));
            stopFlag = false;
            set(monitorFig, 'KeyPressFcn', @(src, event) setappdata(monitorFig, 'stopFlag', true));
            setappdata(monitorFig, 'stopFlag', false);
            while true
                [newWorstStatus, worstTimestamp, worstConfidence] = monitorFile(filePath, lastReadPosition, currentWorstStatus);
                if find(statusHierarchy == newWorstStatus) ~= find(statusHierarchy == currentWorstStatus)
                    currentWorstStatus = newWorstStatus;
                    disp(worstTimestamp + " " + currentWorstStatus + " confidence: " + worstConfidence);
                    OABadj = statusDict(currentWorstStatus) * worstConfidence;
                    graphArrayLocal = ensureGraphArray(graphArrayArg, nUsers, nObjects);
                    anyRiskChanged = false;
                    for user = 1:nUsers
                        for object = 1:nObjects
                            if isstruct(ACL{user, object})
                                oldRisk = RisksRT(user, object);
                                [newRisk, testInputNew, intermediateNew, ~, ~] = recomputeRiskGraphWithOAB(OABadj, ...
                                    testInputParametersGlobal, intermediateNodesGlobal, user, object, [], configArg);
                                try
                                    testInputParametersGlobal{user, object} = testInputNew;
                                    intermediateNodesGlobal{user, object} = intermediateNew;
                                catch
                                end
                                RisksRT(user, object) = newRisk;
                                if abs(oldRisk - newRisk) > 1e-6
                                    anyRiskChanged = true;
                                    if ~isempty(subjectsArg)
                                        [riskGraph, graphGenerated] = generateRiskGraphForChange(subjectsArg, user, ...
                                            testInputNew, intermediateNew, newRisk, getLOIMethod(configArg));
                                        if graphGenerated
                                            graphArrayLocal{user, object} = riskGraph;
                                            exportChangedGraphPicture(graphArrayLocal, nUsers, objects, objectsNames, configArg, user, object);
                                        end
                                    end
                                end
                                disp("User " + user + "->object " + object + " risk level: " + RisksRT(user, object));
                            end
                        end
                    end
                    if anyRiskChanged
                        graphArrayArg = graphArrayLocal;
                    end
                    aggRisk = aggregatedRisk(RisksRT, impacts, objects, 0.7);
                    disp("Aggregated risk: " + aggRisk);
                    if anyRiskChanged
                        try
                            riskGuiUpdate(RisksRT, impacts, objects);
                        catch MEgui
                            fprintf('Risk GUI live update skipped: %s\n', MEgui.message);
                        end
                    end
                    fprintf(file, "%s\n", char(worstTimestamp));
                    for i = 1:nUsers
                        fprintf(file, "%d,", i);
                        for j = 1:nObjects
                            fprintf(file, "%.2f,", RisksRT(i, j));
                        end
                        fprintf(file, "\n");
                    end
                end
                lastReadPosition = max(1, fileSizeBytes(filePath));
                if consoleStopRequested()
                    fprintf('Console stop requested via %s\n', consoleStopFilePath());
                    clearConsoleStopRequest();
                    stopFlag = true;
                end
                if consoleResetRequested()
                    fprintf('Console reset requested via %s\n', consoleResetFilePath());
                    clearConsoleResetRequest();
                    handleADITransactionIndicators("__reset__");
                    RisksRT = Risks;
                    currentWorstStatus = "OFF";
                    try
                        riskGuiUpdate(RisksRT, impacts, objects);
                    catch MEgui
                        fprintf('Risk GUI reset skipped: %s\n', MEgui.message);
                    end
                    sendResetRiskTransactions(Risks, impacts, objects, nUsers, nObjects, objectsNames, graphArrayArg, configArg);
                    fprintf('Risk monitor reset to initial stage.\n');
                end
                if isempty(monitorFig) || ~isvalid(monitorFig)
                    stopFlag = true;
                else
                    stopFlag = getappdata(monitorFig, 'stopFlag');
                    if isempty(stopFlag), stopFlag = false; end
                end
                if stopFlag
                    disp('Finish');
                    break;
                end
                processGuiEvents();
                sleepNoGraphics(1);
            end
            closeFigureIfValid(monitorFig);
            monitorFig = [];
            closeFileIfOpen(file);
            file = -1;
            stopConsoleStopWatcher(stopTimer);
            stopTimer = [];
            clear figCleanup fileCleanup
            
        elseif realTimeMode == "aggregator" && (contains(env_new, "nokia") || contains(env_new, "telco")|| contains(env_new, "antonov"))
            % Aggregator mode for Nokia environment
            object = 4; % Specific object for aggregator mode
            csvFileName = 'risksRT.csv';
            if ~isfile(csvFileName)
                file = fopen(csvFileName, 'a');
                if file == -1
                    error('real_time_monitor:FileOpenFailed', 'Unable to open %s for writing.', csvFileName);
                end
                fileCleanup = onCleanup(@() closeFileIfOpen(file));
                fprintf(file, "%s,", "User");
                for i = 1:nObjects
                    fprintf(file, "%s,", objectsNames(i));
                end
                fprintf(file, "\n");
                closeFileIfOpen(file);
                file = -1;
                clear fileCleanup
            end
            % Start HTTP server for aggregator mode
            http_server('start', Risks, nUsers, ACL, objects, testInputParametersGlobal, intermediateNodesGlobal, impacts, statusDict, csvFileName, nObjects, graphArrayArg, subjectsArg, configArg);
            fprintf("Acram server running on port %d\n", 5600);
            
        elseif realTimeMode == "ADI" && (contains(env_new, "nokia") || contains(env_new, "telco")|| contains(env_new, "antonov"))
            % ADI mode for Nokia environment
            lockFile = 'auth_lock.txt';
            if exist(lockFile, 'file')
                fprintf('[ERROR] Authentication permanently locked for this session (file lock).\n');
                return;
            end
            % Load WebSocket credentials from config. Missing/invalid
            % credentials should stop ADI startup.
            try
                adiInfo = resolve_adi_connection(configArg);
                serverAddress = string(adiInfo.credentials.websocket_address);
                id = string(adiInfo.authId);
                private_key = string(adiInfo.privateKey);
            catch ME
                fprintf('[ERROR] WebSocket credentials unavailable: %s\n', ME.message);
                rethrow(ME);
            end

            % Source-based filter using $in on data.source
            % Note: "BACON" is used by newer BACON network anomaly transactions
            % that replace/augment the earlier "ENG Network Event" naming.
            sources = { ...
                "NAD Longterm Raw Observation Event", ... % Nokia_RAD
                "RAD Observation Event", ...              % ATC_RAD
                "I4RI Observation Event", ...             % I4RI_RAD
                "ATC Network Event", ...                  % ATC_NAD
                "ENG Network Event", ...                  % BECON_NAD (legacy)
                "BACON", ...                              % BACON network anomaly
                "NAD", ...                                % Generic NAD network anomaly
                "UAM" ...                                 % UAM anomaly indicators (per-user OAB etc.)
            };
            % Optional: include SBOM/CVE list transactions (UC2 Nokia)
            try
                enableCveWs = false;
                if ~isempty(configArg) && isstruct(configArg) && isfield(configArg,'parseCVEListFromWebsocket')
                    enableCveWs = logical(configArg.parseCVEListFromWebsocket);
                end
                if enableCveWs
                    extra = "SBOM Tool";
                    try
                        if isfield(configArg,'cveWebsocketSources') && ~isempty(configArg.cveWebsocketSources)
                            extra = string(configArg.cveWebsocketSources);
                        end
                    catch
                    end
                    for s = 1:numel(extra)
                        try
                            if ~any(string(sources) == string(extra(s)))
                                sources{end+1} = char(string(extra(s))); %#ok<AGROW>
                            end
                        catch
                        end
                    end
                end
            catch
            end
            inMap = containers.Map({'$in'},{sources});
            filter = containers.Map({'data.source'},{inMap});
            filters = {filter};

            % Separate variable to keep robot IP(s) gathered from config (optional per object)
            robotIps = strings(0,1);
            try
                if isfield(objects, 'IP')
                    for k = 1:numel(objects)
                        try
                            ipk = string(objects(k).IP);
                            if strlength(ipk) > 0
                                robotIps(end+1,1) = ipk; %#ok<AGROW>
                            end
                        catch
                        end
                    end
                end
            catch
            end

            handleADITransactionIndicators("__reset__");
            adiCallbackContext = struct( ...
                'nUsers', nUsers, ...
                'nObjects', nObjects, ...
                'ACL', {ACL}, ...
                'objects', objects, ...
                'testInputParametersGlobal', {testInputParametersGlobal}, ...
                'intermediateNodesGlobal', {intermediateNodesGlobal}, ...
                'impacts', impacts, ...
                'statusDict', statusDict, ...
                'Risks', Risks, ...
                'robotIps', robotIps, ...
                'subjectsArg', subjectsArg, ...
                'ovlpArg', ovlpArg, ...
                'ntArg', ntArg, ...
                'configArg', configArg, ...
                'graphArrayArg', {graphArrayArg});
            try
                clear SmartQCWebSocketClient
                rehash
            catch MEclear
                fprintf('WebSocket class reload skipped: %s\n', MEclear.message);
            end
            wsClient = SmartQCWebSocketClient(serverAddress, id, private_key, filters, @real_time_monitor_adi_callback);
            wsClient.connectBackground();

        else
            error('Unsupported real-time mode: %s for environment: %s', realTimeMode, env_new);
        end
    case 'stop'
        stopConsoleStopWatcher(stopTimer);
        stopTimer = [];
        clearConsoleStopRequest();
        clearConsoleResetRequest();
        % Stop local monitoring UI, if any
        try
            if ~isempty(monitorFig) && isvalid(monitorFig)
                close(monitorFig);
            end
        catch ME
            fprintf('Monitor figure close failed: %s\n', ME.message);
        end
        stopFlag = true;

        % Stop and clean up WebSocket client (ADI mode)
        try
            if ~isempty(wsClient) && isvalid(wsClient)
                wsClient.disconnect();
            end
        catch
        end
        wsClient = [];
        adiCallbackContext = [];
        handleADITransactionIndicators("__reset__");
    case {'request_stop', 'stop_request'}
        requestConsoleStop();
        fprintf('Console stop requested via %s\n', consoleStopFilePath());
    case 'reset'
        clearConsoleResetRequest();
        handleADITransactionIndicators("__reset__");
        adiCallbackContext = [];
        resetLiveRiskGui(initialRisks, initialImpacts, initialObjects);
        sendResetRiskTransactions(initialRisks, initialImpacts, initialObjects, ...
            initialNUsers, initialNObjects, initialObjectsNames, initialGraphArray, initialConfig);
        fprintf('Risk monitor reset to initial stage.\n');
    case {'request_reset', 'reset_request'}
        requestConsoleReset();
        fprintf('Console reset requested via %s\n', consoleResetFilePath());
    case 'test_adi_transaction'
        if numel(varargin) < 8
            error('real_time_monitor:InvalidTestArguments', ...
                'test_adi_transaction requires transaction, Risks, ACL, objects, testInput, intermediate, impacts, and config.');
        end
        transaction = varargin{1};
        Risks = varargin{2};
        ACL = varargin{3};
        objects = varargin{4};
        testInputParametersGlobal = varargin{5};
        intermediateNodesGlobal = varargin{6};
        impacts = varargin{7};
        configArg = varargin{8};
        try
            configArg.disableAdiSend = true;
        catch
        end
        subjectsArg = [];
        ovlpArg = [];
        ntArg = [];
        graphArrayArg = [];
        resetBefore = true;
        if numel(varargin) >= 9, subjectsArg = varargin{9}; end
        if numel(varargin) >= 10, ovlpArg = varargin{10}; end
        if numel(varargin) >= 11, ntArg = varargin{11}; end
        if numel(varargin) >= 12, graphArrayArg = varargin{12}; end
        if numel(varargin) >= 13, resetBefore = logical(varargin{13}); end
        if resetBefore
            handleADITransactionIndicators("__reset__");
        end
        nUsers = size(Risks, 1);
        nObjects = numel(objects);
        statusDict = containers.Map({'OFF', 'YELLOW', 'ORANGE', 'RED'}, {0, 0.33, 0.66, 1});
        robotIps = objectIpsForRealtime(objects);
        handleADITransactionIndicators(transaction, nUsers, nObjects, ACL, objects, ...
            testInputParametersGlobal, intermediateNodesGlobal, impacts, statusDict, ...
            Risks, robotIps, subjectsArg, ovlpArg, ntArg, configArg, graphArrayArg);
    case {'adi_callback_transaction', 'websocket_transaction'}
        if isempty(adiCallbackContext)
            fprintf('WebSocket transaction parse skipped: real_time_monitor ADI callback context is not initialized.\n');
            return;
        end
        if isempty(varargin)
            fprintf('WebSocket transaction parse skipped: missing transaction payload.\n');
            return;
        end
        c = adiCallbackContext;
        handleADITransactionIndicators(varargin{1}, c.nUsers, c.nObjects, c.ACL, c.objects, ...
            c.testInputParametersGlobal, c.intermediateNodesGlobal, c.impacts, c.statusDict, ...
            c.Risks, c.robotIps, c.subjectsArg, c.ovlpArg, c.ntArg, c.configArg, c.graphArrayArg);
    otherwise
        error('Unknown action for real_time_monitor: %s', action);
end
end

function closeFileIfOpen(fileId)
    try
        if isnumeric(fileId) && isscalar(fileId) && fileId > 0
            fclose(fileId);
        end
    catch
    end
end

function closeFigureIfValid(fig)
    try
        if ~isempty(fig) && isvalid(fig)
            close(fig);
        end
    catch
    end
end

function timerObj = startConsoleStopWatcher()
    try
        stopPath = consoleStopFilePath();
        resetPath = consoleResetFilePath();
        timerObj = timer('ExecutionMode', 'fixedSpacing', ...
            'Period', 1.0, ...
            'BusyMode', 'drop', ...
            'Name', 'RiskConsoleStopWatcher', ...
            'TimerFcn', @(~, ~) consoleStopTimerTick());
        start(timerObj);
        fprintf('Console stop enabled. Create this file to stop monitoring: %s\n', stopPath);
        fprintf('Console reset enabled. Create this file to reset monitoring: %s\n', resetPath);
    catch ME
        fprintf('Console stop watcher unavailable: %s\n', ME.message);
        timerObj = [];
    end
end

function stopConsoleStopWatcher(timerObj)
    try
        if ~isempty(timerObj) && isvalid(timerObj)
            stop(timerObj);
            delete(timerObj);
        end
    catch
    end
end

function consoleStopTimerTick()
    try
        if consoleStopRequested()
            fprintf('Console stop requested via %s\n', consoleStopFilePath());
            real_time_monitor('stop');
        elseif consoleResetRequested()
            fprintf('Console reset requested via %s\n', consoleResetFilePath());
            real_time_monitor('reset');
        end
    catch ME
        fprintf('Console stop watcher error: %s\n', ME.message);
    end
end

function requestConsoleStop()
    stopPath = consoleStopFilePath();
    fileId = fopen(stopPath, 'w');
    if fileId == -1
        error('real_time_monitor:StopRequestFailed', ...
            'Unable to create stop request file: %s', stopPath);
    end
    cleanup = onCleanup(@() fclose(fileId));
    fprintf(fileId, 'stop requested at %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    clear cleanup
end

function requestConsoleReset()
    resetPath = consoleResetFilePath();
    fileId = fopen(resetPath, 'w');
    if fileId == -1
        error('real_time_monitor:ResetRequestFailed', ...
            'Unable to create reset request file: %s', resetPath);
    end
    cleanup = onCleanup(@() fclose(fileId));
    fprintf(fileId, 'reset requested at %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    clear cleanup
end

function tf = consoleStopRequested()
    tf = isfile(consoleStopFilePath());
end

function tf = consoleResetRequested()
    tf = isfile(consoleResetFilePath());
end

function clearConsoleStopRequest()
    try
        stopPath = consoleStopFilePath();
        if isfile(stopPath)
            delete(stopPath);
        end
    catch
    end
end

function clearConsoleResetRequest()
    try
        resetPath = consoleResetFilePath();
        if isfile(resetPath)
            delete(resetPath);
        end
    catch
    end
end

function stopPath = consoleStopFilePath()
    try
        envPath = string(getenv('ACRAM_STOP_FILE'));
    catch
        envPath = "";
    end
    if strlength(strtrim(envPath)) > 0
        stopPath = char(envPath);
    else
        stopPath = fullfile(pwd, 'stop_acram_monitor.flag');
    end
end

function resetPath = consoleResetFilePath()
    try
        envPath = string(getenv('ACRAM_RESET_FILE'));
    catch
        envPath = "";
    end
    if strlength(strtrim(envPath)) > 0
        resetPath = char(envPath);
    else
        resetPath = fullfile(pwd, 'reset_acram_monitor.flag');
    end
end

function resetLiveRiskGui(initialRisks, initialImpacts, initialObjects)
    try
        if isempty(initialRisks)
            return;
        end
        if isempty(initialImpacts) || isempty(initialObjects)
            riskGuiUpdate(initialRisks);
        else
            riskGuiUpdate(initialRisks, initialImpacts, initialObjects);
        end
    catch ME
        fprintf('Risk GUI reset skipped: %s\n', ME.message);
    end
end

function sendResetRiskTransactions(risks, impacts, objects, nUsers, nObjects, objectsNames, graphArray, configArg)
    try
        if isempty(risks) || isempty(objects) || isempty(configArg) || ~realtimeSendEnabled(configArg)
            return;
        end
        if isempty(nUsers) || nUsers <= 0
            nUsers = size(risks, 1);
        end
        if isempty(nObjects) || nObjects <= 0
            nObjects = numel(objects);
        end
        nUsers = min(nUsers, size(risks, 1));
        nObjects = min(nObjects, min(size(risks, 2), numel(objects)));
        if nUsers <= 0 || nObjects <= 0
            return;
        end

        usersNames = "User " + string((1:nUsers)');
        resetLabels = "ACRAM reset to initial stage";
        sentObjects = 0;
        for objIdx = 1:nObjects
            graphsForObject = {};
            try
                if ~isempty(graphArray)
                    graphsForObject = graphArray(:, objIdx);
                end
            catch
                graphsForObject = {};
            end
            resultJSON(risks(1:nUsers, objIdx), objects(objIdx).Name, usersNames, ...
                0, 1, strings(0,1), [], [], graphsForObject, configArg, resetLabels);
            sentObjects = sentObjects + 1;
        end

        try
            aggRisk = aggregatedRisk(risks(1:nUsers, 1:nObjects), impacts(1:nObjects), objects(1:nObjects), 0.7);
            tablerisks = resetRiskTable(risks(1:nUsers, 1:nObjects), usersNames, objects(1:nObjects), objectsNames);
            aggregatedIndicator(aggRisk, tablerisks, 1, resetLabels, 0, configArg);
        catch MEagg
            fprintf('Reset aggregated ADI transaction skipped: %s\n', MEagg.message);
        end
        fprintf('Reset risk transactions sent to ADI: %d object transaction(s).\n', sentObjects);
    catch ME
        fprintf('Reset ADI transaction send failed: %s\n', ME.message);
    end
end

function tablerisks = resetRiskTable(risks, usersNames, objects, objectsNames)
    nObjects = size(risks, 2);
    varNames = strings(1, nObjects);
    for j = 1:nObjects
        nm = "Object_" + string(j);
        try
            if nargin >= 4 && ~isempty(objectsNames) && numel(objectsNames) >= j && strlength(string(objectsNames(j))) > 0
                nm = string(objectsNames(j));
            elseif isfield(objects(j), 'Name') && ~isempty(objects(j).Name)
                nm = string(objects(j).Name);
            end
        catch
        end
        varNames(j) = string(matlab.lang.makeValidName(nm));
    end
    T = array2table(risks, 'VariableNames', cellstr(varNames));
    tablerisks = [table(usersNames(:), 'VariableNames', {'Users'}) T];
end

function robotIps = objectIpsForRealtime(objects)
    robotIps = strings(0,1);
    try
        if isfield(objects, 'IP')
            for k = 1:numel(objects)
                try
                    ipk = string(objects(k).IP);
                    if strlength(ipk) > 0
                        robotIps(end+1,1) = ipk; %#ok<AGROW>
                    end
                catch
                end
            end
        end
    catch
    end
end

function nBytes = fileSizeBytes(filePath)
    info = dir(filePath);
    if isempty(info)
        nBytes = 0;
    else
        nBytes = info.bytes;
    end
end

function [testInput, intermediateNode] = getRiskPathInputs(testInputs, intermediateNodes, userIdx, objectIdx, vulnerabilityIdx)
    try
        testInput = testInputs{userIdx, objectIdx};
        intermediateNode = intermediateNodes{userIdx, objectIdx};
        if ~isempty(testInput) && ~isempty(intermediateNode)
            return;
        end
    catch
    end

    try
        testInput = testInputs{userIdx, objectIdx, vulnerabilityIdx};
        intermediateNode = intermediateNodes{userIdx, objectIdx, vulnerabilityIdx};
    catch ME
        error('real_time_monitor:RiskInputMissing', ...
            'Missing risk inputs for user %d, object %d: %s', userIdx, objectIdx, ME.message);
    end
end

function [riskValue, testInput, intermediateNode, riskGraph, graphGenerated] = recomputeRiskGraphWithOAB(OABadj, testInputs, intermediateNodes, userIdx, objectIdx, subjectsArg, configArg)
    [testInput, intermediateNode] = getRiskPathInputs(testInputs, intermediateNodes, userIdx, objectIdx, 1);
    testInput("OAB") = OABadj;
    loim = getLOIMethod(configArg);
    try
        [riskValue, intermediateNode] = EvaluateRisk(testInput, loim);
    catch
        riskValue = updateOAB(OABadj, testInput("AR"), testInput("AC"), ...
            intermediateNode("AS"), intermediateNode("ALbeforeOAB"));
    end
    riskGraph = [];
    graphGenerated = false;
    if ~isempty(subjectsArg)
        [riskGraph, graphGenerated] = generateRiskGraphForChange(subjectsArg, userIdx, testInput, intermediateNode, riskValue, loim);
    end
end

function [RisksOut, testInputOut, intermediateOut, graphOut] = applyRuntimeOABState(RisksIn, testInputIn, intermediateIn, graphIn, subjectsArg, nUsers, nObjects, ACL, configArg, ind_nokiaRAD, ind_ATCRAD, ind_I4RIRAD, ind_ATCNAD, ind_BACONNAD, oabPrev, oabFis)
    RisksOut = RisksIn;
    testInputOut = testInputIn;
    intermediateOut = intermediateIn;
    graphOut = graphIn;
    if isempty(testInputOut) || isempty(intermediateOut)
        return;
    end
    try
        graphOut = ensureGraphArray(graphOut, nUsers, nObjects);
    catch
    end
    for objIdx = 1:nObjects
        indicators = [ind_nokiaRAD(objIdx), ind_ATCRAD(objIdx), ind_I4RIRAD(objIdx), ind_ATCNAD(objIdx), ind_BACONNAD(objIdx)];
        hasRuntimeOAB = any(indicators > 0);
        try
            hasRuntimeOAB = hasRuntimeOAB || (~isempty(oabPrev) && numel(oabPrev) >= objIdx && ~isnan(oabPrev(objIdx)));
        catch
        end
        if ~hasRuntimeOAB
            continue;
        end
        OABadj = computeOABFromIndicators(indicators, oabFis);
        for userIdx = 1:nUsers
            if ~isstruct(ACL{userIdx, objIdx})
                continue;
            end
            try
                [newVal, testInputNew, intermediateNew, riskGraph, graphGenerated] = recomputeRiskGraphWithOAB(OABadj, ...
                    testInputOut, intermediateOut, userIdx, objIdx, subjectsArg, configArg);
                RisksOut(userIdx, objIdx) = newVal;
                testInputOut{userIdx, objIdx} = testInputNew;
                intermediateOut{userIdx, objIdx} = intermediateNew;
                if graphGenerated
                    graphOut{userIdx, objIdx} = riskGraph;
                end
            catch ME
                fprintf('Runtime OAB cache restore failed for user %d, object %d: %s\n', userIdx, objIdx, ME.message);
            end
        end
    end
end

function [riskGraph, graphGenerated] = generateRiskGraphForChange(subjectsArg, userIdx, testInput, intermediateNode, riskValue, loim)
    riskGraph = [];
    graphGenerated = false;
    try
        [SPMP, SPMPNames] = spmpForGraph(subjectsArg, userIdx);
        riskGraph = createGraph(SPMP, SPMPNames, testInput, intermediateNode, riskValue, loim);
        graphGenerated = true;
    catch ME
        fprintf('Graph generation skipped for user %d: %s\n', userIdx, ME.message);
    end
end

function [SPMP, SPMPNames] = spmpForGraph(subjectsArg, userIdx)
    if isempty(subjectsArg) || numel(subjectsArg) < userIdx
        error('real_time_monitor:GraphInputsMissing', 'subjects are not available.');
    end
    SPMP = dictionary();
    fields = ["RAL", "mPA", "ALD", "MPA", "EPH", "ALT", "MPL", "PCR", "SPE"];
    SPMPNames = ["Reset account lockout counter after", ...
        "Minimum password age", ...
        "Account Lockout Duration", ...
        "Maximum password age", ...
        "Enforce password history", ...
        "Account Lockout Threshold", ...
        "Minimum password length", ...
        "Password must meet complexity requirements", ...
        "Store passwords using reversible encryption"];
    subj = subjectsArg(userIdx);
    for i = 1:numel(fields)
        fieldName = fields(i);
        fieldNameChar = char(fieldName);
        if isfield(subj, fieldNameChar)
            SPMP(fieldName) = subj.(fieldNameChar);
        else
            SPMP(fieldName) = 0;
        end
    end
end

function loim = getLOIMethod(configArg)
    loim = "indirect";
    try
        if ~isempty(configArg) && isfield(configArg, 'LOIMethod')
            loim = string(configArg.LOIMethod);
        end
    catch
    end
end

function graphArray = ensureGraphArray(graphArray, nUsers, nObjects)
    if isempty(graphArray) || ~iscell(graphArray)
        graphArray = cell(nUsers, nObjects);
    elseif size(graphArray, 1) < nUsers || size(graphArray, 2) < nObjects
        graphArray{nUsers, nObjects} = [];
    end
end

function exportChangedGraphPicture(graphArray, nUsers, objects, objectsNamesFallback, configArg, userIdx, objectIdx)
    try
        usersNames = "User " + string((1:nUsers)');
        objectsNames = objectNamesForGraphs(objects, size(graphArray, 2), objectsNamesFallback);
        exportRiskGraphImages(graphArray, usersNames, objectsNames, configArg, userIdx, objectIdx);
    catch ME
        fprintf('Risk graph image update failed for user %d, object %d: %s\n', userIdx, objectIdx, ME.message);
    end
end

function objectsNames = objectNamesForGraphs(objects, nObjects, fallback)
    if nargin >= 3 && ~isempty(fallback)
        objectsNames = string(fallback);
        objectsNames = objectsNames(:)';
        if numel(objectsNames) >= nObjects
            return;
        end
    else
        objectsNames = strings(1, nObjects);
    end

    for j = 1:nObjects
        if j <= numel(objectsNames) && strlength(objectsNames(j)) > 0
            continue;
        end
        nm = "Object " + string(j);
        try
            if isfield(objects(j), 'Name') && ~isempty(objects(j).Name)
                nm = string(objects(j).Name);
            end
        catch
        end
        objectsNames(j) = nm;
    end
end

function handleADITransactionIndicators(transaction, nUsers, nObjects, ACL, objects, testInputParametersGlobal, intermediateNodesGlobal, impacts, statusDict, Risks, robotIps, subjectsArg, ovlpArg, ntArg, configArg, graphArrayInitial) %#ok<INUSD>
    % Persistent runtime state
	persistent RisksRT ind_nokiaRAD ind_ATCRAD ind_I4RIRAD ind_ATCNAD ind_BACONNAD t_ATCNAD t_BACONNAD oabFis aggRiskPrev oabPrev
    persistent perUserSABPrev
    persistent perUserRiskPrev
    persistent testInputRT intermediateRT
    persistent id_nokiaRAD id_ATCRAD id_I4RIRAD id_ATCNAD id_BACONNAD
    persistent objectsRT ovlpRT subjectsRT
    persistent graphArrayRT
    persistent seenTxIds seenTxOrder
    if nargin == 1 && (ischar(transaction) || isstring(transaction)) && any(strcmpi(string(transaction), "__reset__"))
        [RisksRT, ind_nokiaRAD, ind_ATCRAD, ind_I4RIRAD, ind_ATCNAD, ind_BACONNAD, ...
            t_ATCNAD, t_BACONNAD, oabFis, aggRiskPrev, oabPrev, perUserSABPrev, ...
            perUserRiskPrev, testInputRT, intermediateRT, id_nokiaRAD, id_ATCRAD, ...
            id_I4RIRAD, id_ATCNAD, id_BACONNAD, objectsRT, ovlpRT, subjectsRT, graphArrayRT, ...
            seenTxIds, seenTxOrder] = deal([]);
        return;
    end
    if isempty(RisksRT), RisksRT = Risks; end
    if isempty(testInputRT), testInputRT = testInputParametersGlobal; end
    if isempty(intermediateRT), intermediateRT = intermediateNodesGlobal; end
    % Ensure per-object arrays for component and network indicators.
    if isempty(ind_nokiaRAD) || numel(ind_nokiaRAD) ~= nObjects, ind_nokiaRAD = zeros(1, nObjects); end
    if isempty(ind_ATCRAD) || numel(ind_ATCRAD) ~= nObjects, ind_ATCRAD = zeros(1, nObjects); end
    if isempty(ind_I4RIRAD) || numel(ind_I4RIRAD) ~= nObjects, ind_I4RIRAD = zeros(1, nObjects); end
    if isempty(ind_ATCNAD) || numel(ind_ATCNAD) ~= nObjects, ind_ATCNAD = zeros(1, nObjects); end
    if isempty(ind_BACONNAD) || numel(ind_BACONNAD) ~= nObjects, ind_BACONNAD = zeros(1, nObjects); end
	if isempty(t_ATCNAD) || numel(t_ATCNAD) ~= nObjects || ~isa(t_ATCNAD,'uint64'), t_ATCNAD = zeros(1, nObjects, 'uint64'); end
	if isempty(t_BACONNAD) || numel(t_BACONNAD) ~= nObjects || ~isa(t_BACONNAD,'uint64'), t_BACONNAD = zeros(1, nObjects, 'uint64'); end
	if isempty(id_nokiaRAD) || numel(id_nokiaRAD) ~= nObjects, id_nokiaRAD = strings(1, nObjects); end
    if isempty(id_ATCRAD) || numel(id_ATCRAD) ~= nObjects, id_ATCRAD = strings(1, nObjects); end
    if isempty(id_I4RIRAD) || numel(id_I4RIRAD) ~= nObjects, id_I4RIRAD = strings(1, nObjects); end
    if isempty(id_ATCNAD) || numel(id_ATCNAD) ~= nObjects, id_ATCNAD = strings(1, nObjects); end
	if isempty(id_BACONNAD) || numel(id_BACONNAD) ~= nObjects, id_BACONNAD = strings(1, nObjects); end
	% Track previous OAB per object to report changes/no-changes
	if isempty(oabPrev) || numel(oabPrev) ~= nObjects, oabPrev = nan(1, nObjects); end
    % Track previous SAB per user for UAM per-user anomaly transactions
	if isempty(perUserSABPrev) || numel(perUserSABPrev) ~= nUsers, perUserSABPrev = nan(1, nUsers); end
    % Track previous per-user risk levels when receiving ACRAM daily summary without a subject/object
	if isempty(perUserRiskPrev) || numel(perUserRiskPrev) ~= nUsers, perUserRiskPrev = nan(1, nUsers); end
    if isempty(seenTxIds)
        seenTxIds = containers.Map('KeyType','char','ValueType','double');
        seenTxOrder = strings(0,1);
    end
    if isempty(graphArrayRT)
        try
            graphArrayRT = graphArrayInitial;
        catch
            graphArrayRT = [];
        end
    end
    graphArrayRT = ensureGraphArray(graphArrayRT, nUsers, nObjects);
    % Keep a mutable copy of objects/OVLP for realtime updates (e.g., SBOM CVE list)
    if isempty(objectsRT)
        try
            objectsRT = objects;
        catch
            objectsRT = [];
        end
    end
    if isempty(ovlpRT)
        try
            ovlpRT = ovlpArg;
        catch
            ovlpRT = [];
        end
    end
    if isempty(subjectsRT)
        try
            subjectsRT = subjectsArg;
        catch
            subjectsRT = [];
        end
    end
    % Use the realtime-updated versions for all downstream computations
    try
        if ~isempty(objectsRT), objects = objectsRT; end
        if ~isempty(ovlpRT), ovlpArg = ovlpRT; end
        if ~isempty(subjectsRT), subjectsArg = subjectsRT; end
    catch
    end
    if isempty(oabFis)
        try
            oabFis = readfis('fiz_OAB.fis'); % OAB FIS
        catch
            oabFis = []; % fallback later
        end
    end

    try
        % The callback receives the payload directly with nested 'data'
        if ~isfield(transaction,'data'), return; end

        % De-duplicate by transaction id
        txId = getTxIdFromTx(transaction);
        if txId ~= ""
            k = char(txId);
            if isKey(seenTxIds, k)
                return;
            else
                seenTxIds(k) = 1;
                seenTxOrder(end+1,1) = txId;
                % bound memory
                maxSeen = 1000;
                if numel(seenTxOrder) > maxSeen
                    oldK = char(seenTxOrder(1));
                    if isKey(seenTxIds, oldK), remove(seenTxIds, oldK); end
                    seenTxOrder(1) = [];
                end
            end
        end
        d = transaction.data; % struct with severity, source, value, supplementary_details, etc.

        % Log full incoming transaction to central log (system.log) for traceability
        try
            logger('info', 'ADI transaction received: %s', jsonencode(transaction));
        catch
        end

        % Read source/severity directly
        src = "";  if isfield(d,'source'),   src = string(d.source);   end
        if strlength(src) == 0 && isfield(d,'traffic_participants') && isfield(d,'root_cause')
            src = "NAD";
        end
        sev = "";  if isfield(d,'severity'), sev = upper(strtrim(string(d.severity))); end
        sendToDataSpaceRT = realtimeSendEnabled(configArg);

        % Context id (used for routing)
        ctxId = "";
        try
            if isfield(transaction,'context_id')
                ctxId = string(transaction.context_id);
            elseif isfield(transaction,'contextId')
                ctxId = string(transaction.contextId);
            end
        catch
            ctxId = "";
        end

        % -----------------------------------------------------------------
        % UC2 Nokia SBOM/CVE list transaction: update OVLP for one object and
        % recompute risks.
        % Controlled by configArg.parseCVEListFromWebsocket (default off).
        % -----------------------------------------------------------------
        try
            enableCveWs = false;
            if ~isempty(configArg) && isstruct(configArg) && isfield(configArg,'parseCVEListFromWebsocket')
                enableCveWs = logical(configArg.parseCVEListFromWebsocket);
            end
            hasCveList = isfield(d,'CVE_list') || isfield(d,'CVEList');
            isCveType = false;
            try
                if isfield(d,'type') && contains(lower(string(d.type)),"cve")
                    isCveType = true;
                end
            catch
            end
            emptyCveListReport = isCveType && ~hasCveList && cveListValueIsZero(d);
            if enableCveWs && (hasCveList || emptyCveListReport)
                % Extract list
                cves = [];
                if isfield(d,'CVE_list')
                    cves = d.CVE_list;
                elseif isfield(d,'CVEList')
                    cves = d.CVEList;
                end
                % Determine object by subject (ip_src/name_src) when present
                subj = "";
                if isfield(d,'subject')
                    subj = string(d.subject);
                end
                [objIdx, objName, objIp] = resolveUc2ObjectFromSubject(subj, objects, robotIps, configArg);
                if objIdx <= 0
                    fprintf('UC2 CVE list received but object could not be resolved (subject="%s")\n', char(subj));
                else
                    if emptyCveListReport
                        fprintf('UC2 empty CVE list for object %d: %s (IP=%s)\n', objIdx, char(objName), char(objIp));
                    else
                        fprintf('UC2 CVE list for object %d: %s (IP=%s)\n', objIdx, char(objName), char(objIp));
                    end
                    % Update OVLP list and object OVLP indices
                    OVLPTemplate = struct("CVE", "", "VALUE", 0, "EM", "Not-Defined", "AV", "Network", "AC", "Low", "PR", "None", "UI", "None", "VC", "None", "VA", "None", "VI", "None", "AR", "None");
                    try
                        if isempty(ovlpRT) && ~isempty(ovlpArg)
                            ovlpRT = ovlpArg;
                        end
                    catch
                    end
                    if isempty(ovlpRT)
                        ovlpRT = repmat(OVLPTemplate, 0, 1);
                    end

                    newIdx = zeros(0,1);
                    try
                        if isstruct(cves)
                            cvesArr = cves;
                        elseif iscell(cves)
                            cvesArr = [cves{:}];
                        else
                            cvesArr = [];
                        end
                    catch
                        cvesArr = [];
                    end

                    for ii = 1:numel(cvesArr)
                        try
                            ov = ovlpFromUc2Cve(cvesArr(ii), OVLPTemplate);
                            cveId = string(ov.CVE);
                            if strlength(cveId) == 0
                                continue;
                            end
                            % Deduplicate by CVE id
                            idxExist = 0;
                            for jj = 1:numel(ovlpRT)
                                try
                                    if string(ovlpRT(jj).CVE) == cveId
                                        idxExist = jj;
                                        break;
                                    end
                                catch
                                end
                            end
                            if idxExist > 0
                                ovlpRT(idxExist) = ov;
                                newIdx(end+1,1) = idxExist; %#ok<AGROW>
                            else
                                ovlpRT(end+1,1) = ov; %#ok<AGROW>
                                newIdx(end+1,1) = numel(ovlpRT); %#ok<AGROW>
                            end
                        catch
                        end
                    end
                    newIdx = unique(newIdx);
                    objectsRT = objects;
                    objectsRT(objIdx).OVLP = newIdx(:)';
                    % Swap effective objects/ovlp used by rest of handler
                    objects = objectsRT;
                    ovlpArg = ovlpRT;

                    % Recompute risks
                    if ~isempty(subjectsArg) && ~isempty(ntArg)
                        try
                            [RisksNew, intermediateNew, testInputNew, graphNew] = calculate_risks(subjectsArg, objectsRT, ovlpRT, ntArg, ACL, configArg, @map_linguistic);
                            [RisksNew, testInputNew, intermediateNew, graphNew] = applyRuntimeOABState( ...
                                RisksNew, testInputNew, intermediateNew, graphNew, subjectsArg, nUsers, nObjects, ACL, ...
                                configArg, ind_nokiaRAD, ind_ATCRAD, ind_I4RIRAD, ind_ATCNAD, ind_BACONNAD, oabPrev, oabFis);
                            % Report changes for this object
                            changedAny = false;
                            for u = 1:nUsers
                                oldVal = RisksRT(u, objIdx);
                                newVal = RisksNew(u, objIdx);
                                if abs(oldVal - newVal) > 1e-6
                                    changedAny = true;
                                    fprintf('Risk changed (CVE): User %d -> %s : %.3f -> %.3f\n', u, char(objectsRT(objIdx).Name), oldVal, newVal);
                                    exportChangedGraphPicture(graphNew, nUsers, objectsRT, [], configArg, u, objIdx);
                                end
                            end
                            RisksRT = RisksNew;
                            testInputRT = testInputNew;
                            intermediateRT = intermediateNew;
                            try
                                graphArrayRT = graphNew;
                            catch MEresult
                                fprintf('UC2 CVE result send failed: %s\n', MEresult.message);
                            end
                            if ~changedAny
                                fprintf('No risk changes after UC2 CVE update for %s.\n', char(objectsRT(objIdx).Name));
                            end
                            % Send updated object risks and aggregated risk
                            try
                                inputAssetsIds = strings(0,1);
                                try
                                    cveTxId = getAssetIdFromTx(transaction);
                                    if strlength(cveTxId) > 0, inputAssetsIds(end+1,1) = cveTxId; end
                                catch
                                end
                                followUpIndicators = strings(0,1);
                                try
                                    objNm = "Object_" + string(objIdx);
                                    if isfield(objectsRT(objIdx), 'Name') && ~isempty(objectsRT(objIdx).Name)
                                        objNm = string(objectsRT(objIdx).Name);
                                    end
                                    followUpIndicators(end+1,1) = "CVE_list -> " + objNm;
                                catch
                                    followUpIndicators(end+1,1) = "CVE_list";
                                end
                                userColumn = (1:nUsers)';
                                usersNames = "User " + string(userColumn);
                                graphsForObject = {};
                                try
                                    graphsForObject = graphNew(:, objIdx);
                                catch
                                end
                                resultJSON(RisksRT(:,objIdx), objectsRT(objIdx).Name, usersNames, 0, sendToDataSpaceRT, inputAssetsIds, [], [], graphsForObject, configArg, followUpIndicators);
                            catch MEresult
                                fprintf('UC2 CVE result send failed: %s\n', MEresult.message);
                            end
                            try
                                aggRiskNew = aggregatedRisk(RisksRT, impacts, objectsRT, 0.7);
                                if isempty(aggRiskPrev), aggRiskPrev = aggRiskNew; end
                                if abs(aggRiskNew - aggRiskPrev) > 1e-6
                                    userNamesCol = "User " + string((1:nUsers)');
                                    varNames = strings(1, nObjects);
                                    for j = 1:nObjects
                                        nm = "Object_" + string(j);
                                        try
                                            if isfield(objectsRT(j), 'Name') && ~isempty(objectsRT(j).Name)
                                                nm = string(objectsRT(j).Name);
                                            end
                                        catch
                                        end
                                        varNames(j) = string(matlab.lang.makeValidName(nm));
                                    end
                                    T = array2table(RisksRT, 'VariableNames', cellstr(varNames));
                                    tablerisks = [table(userNamesCol, 'VariableNames', {'Users'}) T];
                                    followUpIndicators = strings(0,1);
                                    try
                                        objNm = "Object_" + string(objIdx);
                                        if isfield(objectsRT(objIdx), 'Name') && ~isempty(objectsRT(objIdx).Name)
                                            objNm = string(objectsRT(objIdx).Name);
                                        end
                                        followUpIndicators(end+1,1) = "CVE_list -> " + objNm;
                                    catch
                                        followUpIndicators(end+1,1) = "CVE_list";
                                    end
                                    aggregatedIndicator(aggRiskNew, tablerisks, sendToDataSpaceRT, followUpIndicators, 0, configArg);
                                    aggRiskPrev = aggRiskNew;
                                end
                            catch MEaggCve
                                fprintf('UC2 CVE aggregated send failed: %s\n', MEaggCve.message);
                            end
                        catch MEc
                            fprintf('UC2 CVE risk recompute failed: %s\n', MEc.message);
                        end
                    else
                        fprintf('UC2 CVE update skipped: subjects/NT not available.\n');
                    end
                end
                return; % do not process CVE tx as network indicator
            end
        catch MEcve
            fprintf('UC2 CVE transaction handling failed: %s\n', MEcve.message);
        end

        % -----------------------------------------------------------------
        % ACRAM per-user risk summary (context_id = 58cd...): update risks
        % -----------------------------------------------------------------
        try
            if src == "ACRAM" && ctxId == "58cd8f8bb6aedcca60784483e621e92b7b02ac42c6104745d229f3292f5e4906"
                if isfield(d,'per-user-risk-levels')
                    pur = d.('per-user-risk-levels');
                elseif isfield(d,'per_user_risk_levels')
                    pur = d.per_user_risk_levels;
                else
                    pur = [];
                end

                % Try to locate the affected object by d.subject (if present)
                subj = "";
                if isfield(d,'subject')
                    subj = string(d.subject);
                end
                objIdx = 0;
                if strlength(subj) > 0
                    try
                        for jj = 1:nObjects
                            if string(objects(jj).Name) == subj
                                objIdx = jj;
                                break;
                            end
                        end
                    catch
                        objIdx = 0;
                    end
                end

                % Normalize pur into MATLAB array of structs
                if ~isempty(pur)
                    changedAny = false;
                    if isstruct(pur)
                        purList = pur;
                    else
                        purList = [];
                    end

                    % In some cases jsondecode returns a cell array for arrays
                    if iscell(pur)
                        try
                            purList = [pur{:}];
                        catch
                            purList = [];
                        end
                    end

                    if ~isempty(purList)
                        for ii = 1:numel(purList)
                            try
                                uid = "";
                                lvl = nan;
                                if isfield(purList(ii),'user-id')
                                    uid = string(purList(ii).('user-id'));
                                elseif isfield(purList(ii),'user_id')
                                    uid = string(purList(ii).user_id);
                                end
                                if isfield(purList(ii),'level')
                                    lvl = str2double(string(purList(ii).level));
                                end
                                tok = regexp(char(uid), '^user-(\d+)$', 'tokens', 'once');
                                if isempty(tok), continue; end
                                uIdx = str2double(tok{1});
                                if isnan(uIdx) || uIdx < 1 || uIdx > nUsers, continue; end
                                if isnan(lvl), continue; end
                                lvl = max(0, min(1, lvl));

                                if objIdx > 0
                                    oldVal = RisksRT(uIdx, objIdx);
                                    if abs(oldVal - lvl) > 1e-6
                                        changedAny = true;
                                        RisksRT(uIdx, objIdx) = lvl;
                                        if ~isempty(subjectsArg)
                                            try
                                                [testInputAcram, intermediateAcram] = getRiskPathInputs(testInputRT, intermediateRT, uIdx, objIdx, 1);
                                                [riskGraph, graphGenerated] = generateRiskGraphForChange(subjectsArg, uIdx, ...
                                                    testInputAcram, intermediateAcram, lvl, getLOIMethod(configArg));
                                                if graphGenerated
                                                    graphArrayRT{uIdx, objIdx} = riskGraph;
                                                    exportChangedGraphPicture(graphArrayRT, nUsers, objects, [], configArg, uIdx, objIdx);
                                                end
                                            catch MEgraph
                                                fprintf('ACRAM graph generation failed for user %d, object %d: %s\n', ...
                                                    uIdx, objIdx, MEgraph.message);
                                            end
                                        end
                                        fprintf('Risk updated from ACRAM: %s -> %s : %.3f -> %.3f\n', char(uid), char(objects(objIdx).Name), oldVal, lvl);
                                    end
                                else
                                    oldVal = perUserRiskPrev(uIdx);
                                    if isnan(oldVal) || abs(oldVal - lvl) > 1e-6
                                        changedAny = true;
                                        perUserRiskPrev(uIdx) = lvl;
                                        fprintf('Per-user risk updated from ACRAM: %s : %.3f -> %.3f\n', char(uid), oldVal, lvl);
                                    end
                                end
                            catch
                            end
                        end
                    end

                    if ~changedAny
                        fprintf('No risk changes from ACRAM daily summary.\n');
                    end

                    % Whole-system aggregated risk recompute (from RisksRT matrix)
                    try
                        aggRiskNew = aggregatedRisk(RisksRT, impacts, objects, 0.7);
                        if isempty(aggRiskPrev)
                            aggRiskPrev = aggRiskNew;
                        end
                        if abs(aggRiskNew - aggRiskPrev) > 1e-6
                            fprintf('Aggregated risk changed: %.3f -> %.3f\n', aggRiskPrev, aggRiskNew);
                            aggRiskPrev = aggRiskNew;
                        else
                            fprintf('No aggregated risk change. Total risk: %.3f\n', aggRiskNew);
                        end
                    catch MEagg2
                        fprintf('Aggregated risk recompute failed: %s\n', MEagg2.message);
                    end
                end
                return; % do not process as network indicator event
            end
        catch MEacram
            fprintf('ACRAM summary processing failed: %s\n', MEacram.message);
        end

        % -----------------------------------------------------------------
        % UAM per-user anomaly indicator: treat data.value as SAB for user-id
        % Accept both source="UAM" and mislabelled source="ACRAM" as long as
        % it matches the UAM user-anomaly context_id.
        % -----------------------------------------------------------------
        isUamContext = (ctxId == "2718e8975fa329947434f1ac88d9f07a1438195b9c50e22e6401d7c054237ec8");
        if src == "UAM" || isUamContext
            try
                uIdStr = "";
                if isfield(d,'user-id')
                    uIdStr = string(d.('user-id'));
                elseif isfield(d,'user_id')
                    uIdStr = string(d.user_id);
                end
                if strlength(uIdStr) > 0 && isfield(d,'value')
                    tok = regexp(char(uIdStr), '^user-(\d+)$', 'tokens', 'once');
                    if ~isempty(tok)
                        uIdx = str2double(tok{1});
                        if ~isnan(uIdx) && uIdx >= 1 && uIdx <= nUsers
                            sabVal = str2double(string(d.value));
                            if isnan(sabVal), sabVal = 0; end
                            sabVal = max(0, min(1, sabVal)); % clamp to [0,1]

                            % Map numeric SAB into discrete SAB levels used by model
                            if sabVal < 0.33
                                sabCode = map_linguistic("SABLOW");
                                sabStr = "LOW";
                            elseif sabVal < 0.66
                                sabCode = map_linguistic("SABMEDIUM");
                                sabStr = "MEDIUM";
                            else
                                sabCode = map_linguistic("SABHIGH");
                                sabStr = "HIGH";
                            end

                            % Keep realtime subjects in sync so later full recalculations
                            % (for example an SBOM refresh) preserve the latest UAM SAB.
                            try
                                if isempty(subjectsRT) && ~isempty(subjectsArg)
                                    subjectsRT = subjectsArg;
                                end
                                if ~isempty(subjectsRT) && numel(subjectsRT) >= uIdx
                                    subjectsRT(uIdx).SAB = char(sabStr);
                                    subjectsArg = subjectsRT;
                                end
                            catch
                            end

                            prevSabU = perUserSABPrev(uIdx);
                            perUserSABPrev(uIdx) = sabCode;

                            if ~isnan(prevSabU) && abs(sabCode - prevSabU) <= 1e-6
                                fprintf('No change in UAM SAB for %s (user %d)\n', char(uIdStr), uIdx);
                                return;
                            end
                            fprintf('New UAM SAB for %s (user %d): %s (%.3f)\n', char(uIdStr), uIdx, char(sabStr), sabVal);

                            % Recompute risks for this user across all objects and report changes.
                            % SAB impacts ALbeforeOAB, so we recompute intermediate nodes per vulnerability
                            % and then apply current per-object OAB adjustment (if present).
                            changedAny = false;
                            for objIdx = 1:nObjects
                                if isstruct(ACL{uIdx, objIdx})
                                    % Use current object OAB adjustment if known; otherwise baseline object OAB
                                    oabCur = oabPrev(objIdx);
                                    if isnan(oabCur)
                                        try
                                            oabCur = map_linguistic(objects(objIdx).OAB);
                                        catch
                                            oabCur = 0;
                                        end
                                    end

                                    % NOTE: calculate_risks stores one (max-risk) vulnerability path per (user,object),
                                    % so testInputRT/intermediateRT are 2D cell arrays. Keep realtime updates consistent.
                                    try
                                        testInputRT{uIdx, objIdx}("SAB") = sabCode;
                                        testInputRT{uIdx, objIdx}("OAB") = oabCur;
                                        [newVal, intermediateRT{uIdx, objIdx}] = EvaluateRisk(testInputRT{uIdx, objIdx}, getLOIMethod(configArg));
                                    catch
                                        try
                                            newVal = updateOAB(oabCur, ...
                                                testInputRT{uIdx, objIdx}("AR"), ...
                                                testInputRT{uIdx, objIdx}("AC"), ...
                                                intermediateRT{uIdx, objIdx}("AS"), ...
                                                intermediateRT{uIdx, objIdx}("ALbeforeOAB"));
                                        catch
                                            newVal = RisksRT(uIdx, objIdx);
                                        end
                                    end
                                    oldVal = RisksRT(uIdx, objIdx);
                                    if abs(oldVal - newVal) > 1e-6
                                        changedAny = true;
                                        RisksRT(uIdx, objIdx) = newVal;
                                        if ~isempty(subjectsArg)
                                            try
                                                [riskGraph, graphGenerated] = generateRiskGraphForChange(subjectsArg, uIdx, ...
                                                    testInputRT{uIdx, objIdx}, intermediateRT{uIdx, objIdx}, newVal, getLOIMethod(configArg));
                                                if graphGenerated
                                                    graphArrayRT{uIdx, objIdx} = riskGraph;
                                                    exportChangedGraphPicture(graphArrayRT, nUsers, objects, [], configArg, uIdx, objIdx);
                                                end
                                            catch MEgraph
                                                fprintf('UAM graph generation failed for user %d, object %d: %s\n', ...
                                                    uIdx, objIdx, MEgraph.message);
                                            end
                                        end
                                        try
                                            fprintf('Risk changed: %s -> %s : %.3f -> %.3f\n', ...
                                                char(uIdStr), char(objects(objIdx).Name), oldVal, newVal);
                                        catch
                                            fprintf('Risk changed: user %d -> object %d : %.3f -> %.3f\n', ...
                                                uIdx, objIdx, oldVal, newVal);
                                        end
                                    end
                                end
                            end

                            if ~changedAny
                                fprintf('No risk changes for %s after UAM SAB update.\n', char(uIdStr));
                            end

                            % Recompute and report aggregated risk changes (whole system)
                            try
                                aggRiskNew = aggregatedRisk(RisksRT, impacts, objects, 0.7);
                                if isempty(aggRiskPrev)
                                    aggRiskPrev = aggRiskNew;
                                end
                                if abs(aggRiskNew - aggRiskPrev) > 1e-6
                                    fprintf('Aggregated risk changed: %.3f -> %.3f\n', aggRiskPrev, aggRiskNew);
                                    aggRiskPrev = aggRiskNew;
                                else
                                    fprintf('No aggregated risk change. Total risk: %.3f\n', aggRiskNew);
                                end
                            catch MEagg
                                fprintf('Aggregated risk recompute failed: %s\n', MEagg.message);
                            end
                            return; % do not process as network indicator event
                        end
                    end
                end
            catch MEu
                fprintf('UAM per-user processing error: %s\n', MEu.message);
                return;
            end
        end

        % Ignore any remaining ACRAM transactions after the supported ACRAM
        % summary/UAM contexts have had a chance to run.
        if src == "ACRAM"
            return;
        end

        % Log transaction reception with timestamp
        try
            ts = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
            idStr = '';
            if txId ~= "", idStr = char(txId); end
            fprintf('[%s] Transaction received: source=%s, severity=%s, id=%s\n', ts, char(src), char(sev), idStr);
        catch
        end

        % Parse indicator values by source.
        indicatorAffectedIdx = [];
        if src == "NAD Longterm Raw Observation Event"
            % Nokia RAD: severity ON means active (1), OFF means inactive (0).
            indicatorAffectedIdx = componentObjectIdx(transaction, objects, configArg);
            if ~isempty(indicatorAffectedIdx)
                if severityIsOn(sev)
                    ind_nokiaRAD(indicatorAffectedIdx) = 1;
                    id_nokiaRAD(indicatorAffectedIdx) = getAssetIdFromTx(transaction);
                elseif severityIsOff(sev)
                    ind_nokiaRAD(indicatorAffectedIdx) = 0;
                    id_nokiaRAD(indicatorAffectedIdx) = "";
                end
            end
        elseif src == "RAD Observation Event"
            indicatorAffectedIdx = componentObjectIdx(transaction, objects, configArg);
            if severityIsOn(sev) || severityIsOff(sev)
                val = valueFromSeverityAndData(d, sev);
                if ~isnan(val) && ~isempty(indicatorAffectedIdx)
                    ind_ATCRAD(indicatorAffectedIdx) = val;
                    if val > 0
                        id_ATCRAD(indicatorAffectedIdx) = getAssetIdFromTx(transaction);
                    else
                        id_ATCRAD(indicatorAffectedIdx) = "";
                    end
                end
            end
        elseif src == "I4RI Observation Event"
            indicatorAffectedIdx = componentObjectIdx(transaction, objects, configArg);
            if ~isempty(indicatorAffectedIdx)
                if severityIsOn(sev)
                    ind_I4RIRAD(indicatorAffectedIdx) = 1;
                    id_I4RIRAD(indicatorAffectedIdx) = getAssetIdFromTx(transaction);
                elseif severityIsOff(sev)
                    ind_I4RIRAD(indicatorAffectedIdx) = 0;
                    id_I4RIRAD(indicatorAffectedIdx) = "";
                end
            end
        elseif src == "ATC Network Event"
            if severityIsOff(sev)
                ind_ATCNAD(:) = 0;
                t_ATCNAD(:) = uint64(0);
                id_ATCNAD(:) = "";
            elseif severityIsOn(sev)
                idxList = matchObjectIdxByIP(transaction, objects);
                if isempty(idxList)
                    idxList = defaultNetworkObjectIdx(objects, configArg);
                end
                if ~isempty(idxList)
                    val = valueFromSeverityAndData(d, sev, 1);
                    if ~isnan(val)
                        for ii = 1:numel(idxList)
                            ix = idxList(ii);
                            ind_ATCNAD(ix) = val;
                            if val > 0
                                t_ATCNAD(ix) = tic;
                                id_ATCNAD(ix) = getAssetIdFromTx(transaction);
                            else
                                t_ATCNAD(ix) = uint64(0);
                                id_ATCNAD(ix) = "";
                            end
                        end
                    end
                end
            end
        elseif src == "ENG Network Event" || src == "BACON" || src == "NAD"
            if severityIsOn(sev) || severityIsOff(sev)
                idxList = matchObjectIdxByIP(transaction, objects);
                if isempty(idxList)
                    idxList = defaultNetworkObjectIdx(objects, configArg);
                end
                if ~isempty(idxList)
                    val = valueFromSeverityAndData(d, sev);
                    if ~isnan(val)
                        for ii = 1:numel(idxList)
                            ix = idxList(ii);
                            ind_BACONNAD(ix) = val;
                            if val > 0
                                t_BACONNAD(ix) = tic;
                                id_BACONNAD(ix) = getAssetIdFromTx(transaction);
                            else
                                t_BACONNAD(ix) = uint64(0);
                                id_BACONNAD(ix) = "";
                            end
                        end
                    end
                end
            end
        end

        % Auto-reset network indicators after 60s (per object)
	for ix = 1:nObjects
		if t_ATCNAD(ix) ~= uint64(0) && toc(t_ATCNAD(ix)) > 60
			ind_ATCNAD(ix) = 0; t_ATCNAD(ix) = uint64(0); id_ATCNAD(ix) = "";
		end
		if t_BACONNAD(ix) ~= uint64(0) && toc(t_BACONNAD(ix)) > 60
			ind_BACONNAD(ix) = 0; t_BACONNAD(ix) = uint64(0); id_BACONNAD(ix) = "";
		end
	end

        % Determine affected objects for this transaction
        affectedIdx = [];
        if src == "ATC Network Event" && severityIsOff(sev)
            affectedIdx = 1:nObjects;
        elseif src == "ATC Network Event" || src == "ENG Network Event" || src == "BACON" || src == "NAD"
            affectedIdx = matchObjectIdxByIP(transaction, objects);
            if isempty(affectedIdx)
                affectedIdx = defaultNetworkObjectIdx(objects, configArg);
            end
        elseif ~isempty(indicatorAffectedIdx)
            affectedIdx = indicatorAffectedIdx;
        end
        if isempty(affectedIdx)
            % default to the 'Robot' object position in objects array
            robotIdx = [];
            try
                names = strings(1, numel(objects));
                for j = 1:numel(objects)
                    try
                        names(j) = string(objects(j).Name);
                    catch
                        names(j) = "";
                    end
                end
                idx = find(names == "Robot", 1);
                if ~isempty(idx), robotIdx = idx; end
            catch
            end
            if ~isempty(robotIdx) && robotIdx <= nObjects
                affectedIdx = robotIdx;
            else
                affectedIdx = [];
            end
        end

        % Recompute risks per affected object using object-specific network indicators
        riskChangedObjects = false(1, numel(affectedIdx));
        for k = 1:numel(affectedIdx)
            objIdx = affectedIdx(k);
            indicators_k = [ind_nokiaRAD(objIdx), ind_ATCRAD(objIdx), ind_I4RIRAD(objIdx), ind_ATCNAD(objIdx), ind_BACONNAD(objIdx)];
			OABadj_k = computeOABFromIndicators(indicators_k, oabFis);
			% Log OAB change or no-change per object
			prevOab = oabPrev(objIdx);
			if ~isnan(prevOab) && abs(OABadj_k - prevOab) <= 1e-6
				try
					fprintf('No change in integrated anomaly level for %s\n', char(objects(objIdx).Name));
				catch
				end
			else
				try
					fprintf('New integrated anomaly level for %s: %.3f\n', char(objects(objIdx).Name), OABadj_k);
				catch
				end
			end
			oabPrev(objIdx) = OABadj_k;
            objRiskChanged = false;
            for user = 1:nUsers
                if isstruct(ACL{user, objIdx})
                    oldVal = RisksRT(user, objIdx);
                    try
                        [newVal, testInputNew, intermediateNew, ~, ~] = recomputeRiskGraphWithOAB(OABadj_k, ...
                            testInputRT, intermediateRT, user, objIdx, [], configArg);
                        testInputRT{user, objIdx} = testInputNew;
                        intermediateRT{user, objIdx} = intermediateNew;
                    catch MErisk
                        fprintf('Risk recompute failed for user %d, object %d: %s\n', user, objIdx, MErisk.message);
                        newVal = oldVal;
                    end
                    if abs(oldVal - newVal) > 1e-6
                        objRiskChanged = true;
                        RisksRT(user, objIdx) = newVal;
                        if ~isempty(subjectsArg)
                            [riskGraph, graphGenerated] = generateRiskGraphForChange(subjectsArg, user, ...
                                testInputNew, intermediateNew, newVal, getLOIMethod(configArg));
                            if graphGenerated
                                graphArrayRT{user, objIdx} = riskGraph;
                                exportChangedGraphPicture(graphArrayRT, nUsers, objects, [], configArg, user, objIdx);
                            end
                        end
                    end
                end
            end
            riskChangedObjects(k) = objRiskChanged;
            if ~objRiskChanged
                fprintf('No risk change for %s (object %d)\n', objects(objIdx).Name, objIdx);
            else
                % Display new risk levels per user for this object
                try
                    ts = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
                catch
                    ts = '';
                end
                try
                    vals = RisksRT(:, objIdx);
                    fprintf('[%s] New risk levels for %s: ', ts, objects(objIdx).Name);
                    for uu = 1:numel(vals)
                        fprintf('%.3f', vals(uu));
                        if uu < numel(vals), fprintf(' '); end
                    end
                    fprintf('\n');
                catch
                end
            end
        end
        aggRiskNew = aggregatedRisk(RisksRT, impacts, objects, 0.7);
        if isempty(aggRiskPrev)
            aggRiskPrev = aggRiskNew;
        end

        % For each affected object that changed, build list of input asset IDs and send JSON
        % and a separate human-readable indicator list for aggregated follow-up.
        aggIndicatorLabels = strings(0,1);
        for k = 1:numel(affectedIdx)
            objIdx = affectedIdx(k);
            if ~riskChangedObjects(k), continue; end
            inputAssetsIds = strings(0,1);
            if ind_nokiaRAD(objIdx) > 0 && strlength(id_nokiaRAD(objIdx)) > 0, inputAssetsIds(end+1,1) = id_nokiaRAD(objIdx); end %#ok<AGROW>
            if ind_ATCRAD(objIdx)   > 0 && strlength(id_ATCRAD(objIdx))   > 0, inputAssetsIds(end+1,1) = id_ATCRAD(objIdx);   end %#ok<AGROW>
            if ind_I4RIRAD(objIdx)  > 0 && strlength(id_I4RIRAD(objIdx))  > 0, inputAssetsIds(end+1,1) = id_I4RIRAD(objIdx);  end %#ok<AGROW>
            if ind_ATCNAD(objIdx)   > 0 && strlength(id_ATCNAD(objIdx))   > 0, inputAssetsIds(end+1,1) = id_ATCNAD(objIdx);   end %#ok<AGROW>
            if ind_BACONNAD(objIdx) > 0 && strlength(id_BACONNAD(objIdx)) > 0, inputAssetsIds(end+1,1) = id_BACONNAD(objIdx); end %#ok<AGROW>
            indicatorLabels = strings(0,1);
            objNameLabel = "Object_" + string(objIdx);
            try
                if isfield(objects(objIdx), 'Name') && ~isempty(objects(objIdx).Name)
                    objNameLabel = string(objects(objIdx).Name);
                end
            catch
            end
            if ind_nokiaRAD(objIdx) > 0 && strlength(id_nokiaRAD(objIdx)) > 0, indicatorLabels(end+1,1) = "nokiaRAD -> " + objNameLabel; end %#ok<AGROW>
            if ind_ATCRAD(objIdx)   > 0 && strlength(id_ATCRAD(objIdx))   > 0, indicatorLabels(end+1,1) = "ATCRAD -> " + objNameLabel;   end %#ok<AGROW>
            if ind_I4RIRAD(objIdx)  > 0 && strlength(id_I4RIRAD(objIdx))  > 0, indicatorLabels(end+1,1) = "I4RIRAD -> " + objNameLabel;  end %#ok<AGROW>
            if ind_ATCNAD(objIdx)   > 0 && strlength(id_ATCNAD(objIdx))   > 0, indicatorLabels(end+1,1) = "ATCNAD -> " + objNameLabel;   end %#ok<AGROW>
            if ind_BACONNAD(objIdx) > 0 && strlength(id_BACONNAD(objIdx)) > 0, indicatorLabels(end+1,1) = "BACONNAD -> " + objNameLabel; end %#ok<AGROW>
            userColumn = (1:nUsers)';
            usersNames = "User " + string(userColumn);
            % Graphs for changed risks are refreshed during the same recompute
            % that updates RisksRT, so follow-up actions use current OAB/SAB inputs.
            graphsForObject = {};
            try
                if ~isempty(graphArrayRT)
                    graphsForObject = graphArrayRT(:, objIdx);
                end
            catch
            end
            if ~isempty(indicatorLabels)
                aggIndicatorLabels = [aggIndicatorLabels; indicatorLabels(:)]; %#ok<AGROW>
            end
            resultJSON(RisksRT(:,objIdx), objects(objIdx).Name, usersNames, 0, sendToDataSpaceRT, inputAssetsIds, [], [], graphsForObject, configArg, indicatorLabels);
        end

        % If aggregated risk changed, send aggregated indicator to ADI
        if abs(aggRiskNew - aggRiskPrev) > 1e-6
            % Build tablerisks: first column 'Users', subsequent columns per object
            userNamesCol = "User " + string((1:nUsers)');
            varNames = strings(1, nObjects);
            for j = 1:nObjects
                nm = "Object_" + string(j);
                try
                    if isfield(objects(j), 'Name') && ~isempty(objects(j).Name)
                        nm = string(objects(j).Name);
                    end
                catch
                end
                varNames(j) = string(matlab.lang.makeValidName(nm));
            end
            T = array2table(RisksRT, 'VariableNames', cellstr(varNames));
            tablerisks = [table(userNamesCol, 'VariableNames', {'Users'}) T];
            if ~isempty(aggIndicatorLabels)
                aggIndicatorLabels = unique(aggIndicatorLabels, 'stable');
            end
            aggregatedIndicator(aggRiskNew, tablerisks, sendToDataSpaceRT, aggIndicatorLabels, 0, configArg);
            aggRiskPrev = aggRiskNew;
        else
            fprintf('No aggregated risk change. Total risk: %.3f\n', aggRiskNew);
        end

        % Flush the latest RisksRT into the live "Risk levels" GUI (if it
        % is open). riskGuiUpdate is throttled internally and is a no-op
        % when no GUI is registered, so it is safe to call after every
        % transaction regardless of whether anything actually changed.
        try
            riskGuiUpdate(RisksRT, impacts, objects);
        catch MEgui
            fprintf('Risk GUI live update skipped: %s\n', MEgui.message);
        end
    catch ME
        fprintf('ADI processing error: %s\n', ME.message);
    end
end

function [objIdx, objName, objIp] = resolveUc2ObjectFromSubject(subj, objects, robotIps, configArg)
    objIdx = 0;
    objName = "";
    objIp = "";
    if nargin < 4
        configArg = [];
    end
    try
        s = string(subj);
        if strlength(s) > 0
            tokIp = regexp(char(s), 'ip_src=([^;]+)', 'tokens', 'once');
            if ~isempty(tokIp)
                objIp = string(tokIp{1});
            end
            tokName = regexp(char(s), 'name_src=([^;]+)', 'tokens', 'once');
            if ~isempty(tokName)
                objName = string(tokName{1});
                objName = strrep(objName, "_", " ");
            end
        end
        % IP match first
        if strlength(objIp) > 0
            for j = 1:numel(objects)
                try
                    if string(objects(j).IP) == objIp
                        objIdx = j;
                        return;
                    end
                catch
                end
            end
        end
        % Name match
        if strlength(objName) > 0
            for j = 1:numel(objects)
                try
                    if lower(string(objects(j).Name)) == lower(objName)
                        objIdx = j;
                        objIp = string(objects(j).IP);
                        return;
                    end
                catch
                end
            end
        end
        targetName = getConfigString(configArg, ["sbomTargetObjectName", "sbomTargetObject", "cveTargetObjectName"]);
        if strlength(targetName) == 0
            try
                if isfield(configArg,'env') && contains(lower(string(configArg.env)), "telco")
                    targetName = "Gateway";
                end
            catch
            end
        end
        if strlength(targetName) > 0
            objIdx = findObjectIdxByName(objects, targetName);
            if objIdx > 0
                objName = targetName;
                try
                    objIp = string(objects(objIdx).IP);
                catch
                    objIp = "";
                end
                return;
            end
        end
        % As a last fallback, if name missing but robotIps contains ip, match by that
        if strlength(objIp) > 0 && any(robotIps == objIp)
            for j = 1:numel(objects)
                try
                    if string(objects(j).IP) == objIp
                        objIdx = j;
                        return;
                    end
                catch
                end
            end
        end
    catch
        objIdx = 0;
    end
end

function ov = ovlpFromUc2Cve(entry, tpl)
    ov = tpl;
    try
        if isfield(entry,'cve_number')
            ov.CVE = string(entry.cve_number);
        elseif isfield(entry,'CVE')
            ov.CVE = string(entry.CVE);
        elseif isfield(entry,'id')
            ov.CVE = string(entry.id);
        end
    catch
    end
    try
        if isfield(entry,'score')
            ov.VALUE = str2double(string(entry.score));
            if isnan(ov.VALUE), ov.VALUE = 0; end
        end
    catch
    end
    try
        if isfield(entry,'remarks')
            % UC2 SBOM tool uses remarks like "NewFound". Treat it as EM=Unreported.
            rem = upper(strtrim(string(entry.remarks)));
            if rem == "NEWFOUND"
                ov.EM = 'Unreported';
            end
        end
    catch
    end
    try
        if isfield(entry,'cvss_vector')
            vec = string(entry.cvss_vector);
            ov = applyCvssVectorToOvlp(vec, ov);
        end
    catch
    end
end

function ov = applyCvssVectorToOvlp(vec, ov)
    s = char(string(vec));
    % AV
    tok = regexp(s, 'AV:([NALP])', 'tokens', 'once');
    if ~isempty(tok)
        switch tok{1}
            case 'N', ov.AV = 'Network';
            case 'A', ov.AV = 'Adjacent';
            case 'L', ov.AV = 'Local';
            case 'P', ov.AV = 'Physical';
        end
    end
    % AC
    tok = regexp(s, 'AC:([LH])', 'tokens', 'once');
    if ~isempty(tok)
        if tok{1} == 'L', ov.AC = 'Low'; else, ov.AC = 'High'; end
    end
    % PR
    tok = regexp(s, 'PR:([NLH])', 'tokens', 'once');
    if ~isempty(tok)
        switch tok{1}
            case 'N', ov.PR = 'None';
            case 'L', ov.PR = 'Low';
            case 'H', ov.PR = 'High';
        end
    end
    % UI
    tok = regexp(s, 'UI:([NR])', 'tokens', 'once');
    if ~isempty(tok)
        if tok{1} == 'N', ov.UI = 'None'; else, ov.UI = 'Active'; end
    end
    % C/I/A impacts -> VC/VI/VA
    tok = regexp(s, 'C:([HLN])', 'tokens', 'once');
    if ~isempty(tok), ov.VC = ciaToLevel(tok{1}); end
    tok = regexp(s, 'I:([HLN])', 'tokens', 'once');
    if ~isempty(tok), ov.VI = ciaToLevel(tok{1}); end
    tok = regexp(s, 'A:([HLN])', 'tokens', 'once');
    if ~isempty(tok), ov.VA = ciaToLevel(tok{1}); end
    ov.AR = 'None';
end

function lvl = ciaToLevel(ch)
    switch ch
        case 'H', lvl = 'High';
        case 'L', lvl = 'Low';
        otherwise, lvl = 'None';
    end
end

function tf = cveListValueIsZero(d)
    tf = false;
    try
        if ~isfield(d,'value')
            return;
        end
        rawValue = string(d.value);
        numericValue = str2double(rawValue);
        if ~isnan(numericValue)
            tf = numericValue == 0;
            return;
        end
        tf = lower(strtrim(rawValue)) == "0";
    catch
        tf = false;
    end
end

function tf = severityIsOn(sev)
    tf = upper(strtrim(string(sev))) == "ON";
end

function tf = severityIsOff(sev)
    tf = upper(strtrim(string(sev))) == "OFF";
end

function val = valueFromSeverityAndData(d, sev, onDefault)
    if nargin < 3
        onDefault = nan;
    end
    if severityIsOff(sev)
        val = 0;
        return;
    end
    val = onDefault;
    try
        if isfield(d,'value')
            parsedValue = str2double(string(d.value));
            if ~isnan(parsedValue) && parsedValue > 0
                val = parsedValue;
            end
        end
    catch
        val = onDefault;
    end
end

function idxList = matchObjectIdxByIP(payload, objects)
    idxList = [];
    if ~isfield(payload,'data'), return; end
    d = payload.data;
    parts = strings(0,1);
    names = strings(0,1);
    if isfield(d,'supplementary_details')
        details = d.supplementary_details;
    elseif isfield(d,'supplementary-details')
        details = d.('supplementary-details');
    else
        details = [];
    end
    try
        parts = [parts; extractIpsFromDetails(details)];
    catch
    end
    try
        if isfield(d,'traffic_participants')
            parts = [parts; extractIpStrings(d.traffic_participants)];
        end
    catch
    end
    try
        if isfield(d,'subject')
            parts = [parts; extractIpStrings(d.subject)];
            names = [names; extractParticipantNames(d.subject)];
        end
    catch
    end
    parts = unique(parts(strlength(parts) > 0));
    names = unique(lower(strtrim(names(strlength(names) > 0))));
    if isempty(parts) && isempty(names)
        return;
    end
    for j = 1:numel(objects)
        try
            ipj = string(objects(j).IP);
        catch
            ipj = "";
        end
        objectNames = strings(0,1);
        try
            if isfield(objects(j), 'Name')
                objectNames(end+1,1) = string(objects(j).Name); %#ok<AGROW>
            end
        catch
        end
        try
            if isfield(objects(j), 'SymbolicName')
                objectNames(end+1,1) = string(objects(j).SymbolicName); %#ok<AGROW>
            end
        catch
        end
        objectNames = lower(strtrim(objectNames(strlength(objectNames) > 0)));
        if (strlength(ipj) > 0 && any(parts == ipj)) || ...
                (~isempty(names) && ~isempty(objectNames) && any(ismember(objectNames, names)))
            idxList(end+1) = j; %#ok<AGROW>
        end
    end
end

function names = extractParticipantNames(value)
    names = strings(0,1);
    try
        raw = string(value);
        rawText = join(raw(:), ";");
        fields = ["name_src", "name_dst"];
        for ii = 1:numel(fields)
            pattern = char(fields(ii) + "\s*=\s*([^;]*)");
            hits = regexp(char(rawText), pattern, 'tokens');
            for jj = 1:numel(hits)
                candidate = strtrim(string(hits{jj}{1}));
                if strlength(candidate) > 0
                    names(end+1,1) = candidate; %#ok<AGROW>
                end
            end
        end
    catch
        names = strings(0,1);
    end
end

function parts = extractIpsFromDetails(details)
    parts = strings(0,1);
    try
        if isempty(details)
            return;
        end
        if isstruct(details)
            if isfield(details,'traffic_participants')
                parts = [parts; extractIpStrings(details.traffic_participants)];
            end
            if isfield(details,'source_ip')
                parts = [parts; extractIpStrings(details.source_ip)];
            end
            if isfield(details,'destination_ip')
                parts = [parts; extractIpStrings(details.destination_ip)];
            end
            return;
        end
        textValue = string(details);
        if strlength(textValue) == 0
            return;
        end
        parsedDetails = jsondecode(textValue);
        parts = extractIpsFromDetails(parsedDetails);
    catch
        parts = strings(0,1);
    end
end

function idxList = defaultNetworkObjectIdx(objects, configArg)
    idxList = [];
    targetName = getConfigString(configArg, ["networkAnomalyTargetObjectName", "networkAnomalyTargetObject"]);
    if strlength(targetName) > 0
        idx = findObjectIdxByName(objects, targetName);
        if idx > 0
            idxList = idx;
            return;
        end
    end
    idx = findObjectIdxByName(objects, "Robot");
    if idx > 0
        idxList = idx;
        return;
    end
    try
        if isfield(configArg,'env') && contains(lower(string(configArg.env)), "telco")
            idx = findObjectIdxByName(objects, "Gateway");
            if idx > 0
                idxList = idx;
            end
        end
    catch
    end
end

function idxList = componentObjectIdx(payload, objects, configArg)
    idxList = matchObjectIdxByIP(payload, objects);
    if ~isempty(idxList)
        return;
    end
    targetName = getConfigString(configArg, ["componentAnomalyTargetObjectName", "componentAnomalyTargetObject", "radTargetObjectName", "radTargetObject"]);
    if strlength(targetName) > 0
        idx = findObjectIdxByName(objects, targetName);
        if idx > 0
            idxList = idx;
            return;
        end
    end
    idx = findObjectIdxByName(objects, "Robot");
    if idx > 0
        idxList = idx;
    end
end

function idx = findObjectIdxByName(objects, name)
    idx = 0;
    target = lower(strtrim(string(name)));
    if strlength(target) == 0
        return;
    end
    for j = 1:numel(objects)
        try
            if lower(strtrim(string(objects(j).Name))) == target
                idx = j;
                return;
            end
        catch
        end
    end
end

function value = getConfigString(configArg, names)
    value = "";
    try
        if isempty(configArg) || ~isstruct(configArg)
            return;
        end
        for ii = 1:numel(names)
            nm = char(string(names(ii)));
            if isfield(configArg, nm) && ~isempty(configArg.(nm))
                value = string(configArg.(nm));
                if strlength(value) > 0
                    return;
                end
            end
        end
    catch
        value = "";
    end
end

function enabled = realtimeSendEnabled(configArg)
    enabled = true;
    try
        if isempty(configArg) || ~isstruct(configArg)
            return;
        end
        if isfield(configArg,'disableAdiSend') && logical(configArg.disableAdiSend)
            enabled = false;
            return;
        end
        if isfield(configArg,'sendRealtimeResultsToDataSpace')
            enabled = parseConfigLogical(configArg.sendRealtimeResultsToDataSpace);
        end
    catch
        enabled = true;
    end
end

function value = parseConfigLogical(rawValue)
    try
        if islogical(rawValue) || isnumeric(rawValue)
            value = logical(rawValue);
            return;
        end
        textValue = lower(strtrim(string(rawValue)));
        value = any(textValue == ["true", "on", "yes", "1"]);
    catch
        value = false;
    end
end

function parts = extractIpStrings(value)
    parts = strings(0,1);
    try
        if iscell(value)
            raw = string(value(:));
        else
            raw = string(value);
            raw = raw(:);
        end
        for ii = 1:numel(raw)
            hits = regexp(char(raw(ii)), '\d{1,3}(?:\.\d{1,3}){3}', 'match');
            if ~isempty(hits)
                parts = [parts; string(hits(:))]; %#ok<AGROW>
            elseif strlength(strtrim(raw(ii))) > 0
                pieces = split(raw(ii), ",");
                parts = [parts; strtrim(pieces(:))]; %#ok<AGROW>
            end
        end
    catch
        parts = strings(0,1);
    end
end
function id = getAssetIdFromTx(tx)
    id = "";
    try
        if isfield(tx,'id')
            id = string(tx.id);
        elseif isfield(tx,'asset_id')
            id = string(tx.asset_id);
        elseif isfield(tx,'payload') && isfield(tx.payload,'id')
            id = string(tx.payload.id);
        end
    catch
        id = "";
    end
end

function txId = getTxIdFromTx(tx)
    txId = "";
    try
        if isfield(tx,'id')
            txId = string(tx.id);
        elseif isfield(tx,'payload') && isfield(tx.payload,'id')
            txId = string(tx.payload.id);
        end
    catch
        txId = "";
    end
end

function OABadj = computeOABFromIndicators(indicators, ~)
    indicators(isnan(indicators)) = 0;
    activeTools = nnz(indicators(:) > 0);
    if activeTools <= 0
        OABadj = 0;
    elseif activeTools == 1
        OABadj = 0.5;
    elseif activeTools == 2
        OABadj = 0.75;
    else
        OABadj = 1;
    end
end
