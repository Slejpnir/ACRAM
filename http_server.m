function http_server(action, varargin)
%HTTP_SERVER Centralized HTTP server and request handling.
%   Usage:
%     http_server('start', Risks, nUsers, ACL, objects, testInputParametersGlobal, intermediateNodesGlobal, impacts, statusDict, csvFileName, nObjects, graphArray, subjects, config)

persistent server

switch lower(action)
    case 'start'
        % Unpack arguments
        Risks = varargin{1};
        nUsers = varargin{2};
        ACL = varargin{3};
        objects = varargin{4};
        testInputParametersGlobal = varargin{5};
        intermediateNodesGlobal = varargin{6};
        impacts = varargin{7};
        statusDict = varargin{8};
        csvFileName = varargin{9};
        nObjects = varargin{10};
        graphArray = [];
        subjectsArg = [];
        configArg = [];
        if numel(varargin) >= 11
            graphArray = varargin{11};
        end
        if numel(varargin) >= 12
            subjectsArg = varargin{12};
        end
        if numel(varargin) >= 13
            configArg = varargin{13};
        end
        graphArray = ensureGraphArray(graphArray, nUsers, nObjects);
        % Start TCP server
        server = tcpserver(5600, "Timeout", 5, "ConnectionChangedFcn", @(src, event) onRequest(src, event, Risks, nUsers, ACL, objects, testInputParametersGlobal, intermediateNodesGlobal, impacts, statusDict, csvFileName, nObjects, graphArray, subjectsArg, configArg));
        fprintf("Acram server running on port %d\n", 5600);
    case 'stop'
        if ~isempty(server) && isvalid(server)
            server = [];
        end
    otherwise
        error('Unknown action for http_server: %s', action);
end
end

function req = readHTTPRequest(src)
    if src.NumBytesAvailable>0
        rawData = read(src, src.NumBytesAvailable, "char");
        if isempty(rawData) || ~ischar(rawData)
            disp("Invalid data received. Closing connection.");
            error("Received empty or invalid request data.");
        end
        tokens = regexp(rawData, '(.*?)\r\n\r\n(.*)', 'tokens', 'once');
        if isempty(tokens)
            error('Malformed HTTP request.');
        end
        headerPart = tokens{1};
        bodyPart   = tokens{2};
        reqLines = splitlines(headerPart);
        parts = split(reqLines{1});
        req.Method = parts{1};
        req.Path   = parts{2};
        req.Body = bodyPart;
    else
        req="Error. Zero bytes.";
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
        error('http_server:RiskInputMissing', ...
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
        error('http_server:GraphInputsMissing', 'subjects are not available.');
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

function exportChangedGraphPicture(graphArray, nUsers, objects, configArg, userIdx, objectIdx)
    try
        usersNames = "User " + string((1:nUsers)');
        objectsNames = objectNamesForGraphs(objects, size(graphArray, 2));
        exportRiskGraphImages(graphArray, usersNames, objectsNames, configArg, userIdx, objectIdx);
    catch ME
        fprintf('Risk graph image update failed for user %d, object %d: %s\n', userIdx, objectIdx, ME.message);
    end
end

function objectsNames = objectNamesForGraphs(objects, nObjects)
    objectsNames = strings(1, nObjects);
    for j = 1:nObjects
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

function onRequest(src, ~, Risks, nUsers, ACL, objects, testInputParametersGlobal, intermediateNodesGlobal, impacts, statusDict, csvFileName, nObjects, graphArray, subjectsArg, configArg)
    sleepNoGraphics(0.1)
    if src.Connected
        disp("Client connected");
        sleepNoGraphics(0.5)
        req = readHTTPRequest(src);
        userColumn = (1:nUsers)';
        usersNames = "User " + string(userColumn);
        graphArray = ensureGraphArray(graphArray, nUsers, nObjects);
        if isstruct(req)
            if startsWith(req.Path, '/evaluate')
                disp("Receiving data");
                inputData = jsondecode(req.Body);
                responseMessage.jobid = job_manager('add', 0); % 0 = IN PROGRESS
                jsonResponse = jsonencode(responseMessage);
                httpResponse = sprintf(['HTTP/1.1 200 OK\r\n', ...
                                    'Content-Type: application/json\r\n', ...
                                    'Content-Length: %d\r\n', ...
                                    'Connection: close\r\n\r\n', ...
                                    '%s'], ...
                                    length(jsonResponse), jsonResponse);
                writeline(src, httpResponse);
                job_manager('update', responseMessage.jobid, 1); % 1 = FINISHED
                if inputData.source=="NAD Event"
                    disp("NAD event");
                    file=fopen(csvFileName,'a');
                    if file == -1
                        error('http_server:FileOpenFailed', 'Unable to open %s for appending.', csvFileName);
                    end
                    fileCleanup = onCleanup(@() fclose(file));
                    riskString=inputData.severity;
                    RisksRT=Risks;
                    riskChange=0;
                    for user=1:nUsers
                        if isstruct(ACL{user,1})
                            OABadj=statusDict(riskString);
                            oldRisk = RisksRT(user,1);
                            [newRisk, testInputNew, intermediateNew, ~, ~] = recomputeRiskGraphWithOAB(OABadj, ...
                                testInputParametersGlobal, intermediateNodesGlobal, user, 1, [], configArg);
                            RisksRT(user,1)=newRisk;
                            try
                                testInputParametersGlobal{user,1} = testInputNew;
                                intermediateNodesGlobal{user,1} = intermediateNew;
                            catch
                            end
                            if abs(oldRisk - newRisk) > 1e-6
                                if ~isempty(subjectsArg)
                                    [riskGraph, graphGenerated] = generateRiskGraphForChange(subjectsArg, user, ...
                                        testInputNew, intermediateNew, newRisk, getLOIMethod(configArg));
                                    if graphGenerated
                                        graphArray{user,1} = riskGraph;
                                        exportChangedGraphPicture(graphArray, nUsers, objects, configArg, user, 1);
                                    end
                                end
                                riskChange=1;
                            end
                            disp("User " + user + "->robot risk level: " + RisksRT(user,1))
                        end
                    end
                    aggRisk=aggregatedRisk(RisksRT,impacts,objects,0.7);
                    disp("Aggregated risk: "+aggRisk);
                    dt = datetime('now');
                    dt.Format = 'dd-MMM-yyyy HH:mm:ss';
                    timeString = string(dt);
                    fprintf(file,timeString);
                    fprintf(file,"\n");
                    for i=1:nUsers
                        fprintf(file,"%d,",i);
                        for j=1:nObjects
                            fprintf(file,"%.2f,",RisksRT(i,j));
                        end
                        fprintf(file,"\n");
                    end
                    if riskChange==1
                        inputAssetsIds=[];
                        graphsForObject = {};
                        try
                            graphsForObject = graphArray(:,1);
                        catch
                        end
                        resultJSON(RisksRT(:,1),objects(1).Name,usersNames,0,1,inputAssetsIds, [], [], graphsForObject, configArg);
                    end
                    fclose(file);
                    clear fileCleanup
                else
                    disp(inputData);
                end
                job_manager('update', responseMessage.jobid, 1); % 1 = FINISHED
            elseif startsWith(req.Path, '/jobs')
                disp("Job status request")
                jobPattern = '/jobs/(\d+)';
                jobMatch = regexp(req.Path, jobPattern, 'tokens', 'once');
                if ~isempty(jobMatch)
                    jobId = str2double(jobMatch{1});
                    disp(jobId);
                    status = job_manager('status', jobId);
                    if status == 0
                        statusText='IN PROGRESS';
                    elseif status == 1
                        statusText='FINISHED';
                    else
                        statusText='WRONG ID';
                    end
                else
                    statusText='WRONG FORMAT';
                end
                responseMessage.status=statusText;
                jsonResponse = jsonencode(responseMessage);
                httpResponse = sprintf(['HTTP/1.1 200 OK\r\n', ...
                                        'Content-Type: application/json\r\n', ...
                                        'Content-Length: %d\r\n', ...
                                        'Connection: close\r\n\r\n', ...
                                        '%s'], ...
                                        length(jsonResponse), jsonResponse);
                writeline(src, httpResponse);
                sleepNoGraphics(0.2);
            elseif startsWith(req.Path, '/reset')
                job_manager('reset');
                responseMessage = struct();
                jsonResponse = jsonencode(responseMessage);
                httpResponse = sprintf(['HTTP/1.1 200 OK\r\n', ...
                                        'Content-Type: application/json\r\n', ...
                                        'Content-Length: %d\r\n', ...
                                        'Connection: close\r\n\r\n', ...
                                        '%s'], ...
                                        length(jsonResponse), jsonResponse);
                writeline(src, httpResponse);
            else
                disp("Unknown endpoint");
                responseMessage = struct();
                jsonResponse = jsonencode(responseMessage);
                httpResponse = sprintf(['HTTP/1.1 404 OK\r\n', ...
                                        'Content-Type: application/json\r\n', ...
                                        'Content-Length: %d\r\n', ...
                                        'Connection: close\r\n\r\n', ...
                                        '%s'], ...
                                        length(jsonResponse), jsonResponse);
                writeline(src, httpResponse);
            end
        else
            disp(req);
            responseMessage = struct();
            jsonResponse = jsonencode(responseMessage);
            httpResponse = sprintf(['HTTP/1.1 404 OK\r\n', ...
                                    'Content-Type: application/json\r\n', ...
                                    'Content-Length: %d\r\n', ...
                                    'Connection: close\r\n\r\n', ...
                                    '%s'], ...
                                    length(jsonResponse), jsonResponse);
            writeline(src, httpResponse);
        end
    end
end 
