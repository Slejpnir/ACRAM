% Enhanced Risk Evaluation System with improved error handling, performance monitoring, and validation
function EvaluateRisk_main_enhanced(configFileNameParam)
clear objects subjects OVLP NT ACL

try
    % Initialize performance monitoring
    performance_monitor('start', 'total_execution');
    
    % Load and validate configuration
    performance_monitor('start', 'config_loading');
    % Determine config file from input argument or default
    if nargin >= 1 && ~isempty(configFileNameParam)
        configFileName = string(configFileNameParam);
    else
        configFileName = 'config_Telco3PC.json';
    end
    % Expose selected config path to base workspace for downstream helpers
    try
        assignin('base','configFileName', char(configFileName));
    catch
    end
    config = config_manager(configFileName);
    
    % Validate configuration
    config_validator(config);
    performance_monitor('end', 'config_loading');
    
    % Check dependencies
    required_functions = {'map_linguistic', 'calculate_risks', 'export_results', 'job_manager', 'http_server', 'real_time_monitor'};
    error_handler('check_dependencies', required_functions);
    
    % Extract configuration parameters
    gui = config.gui;
    % Force GUI off on Linux regardless of config
    try
        if isunix && ~ismac
            gui = "off";
        end
    catch
    end
    realTime = config.realTime;
    realTimeMode = config.realTimeMode;
    env_new = config.env;
    %LOIMethod = config.LOIMethod;
    LOIinput = config.LOIinput;
    OVLPMethod = config.OVLPMethod;
    %mockOAB = config.mockOAB;
    minimalImpactLevel = config.minimalImpactLevel;
    sbom = config.sbom;
    
    sendToDataSpace = configFlag(config, 'sendToDataSpace', 1);
    sendToDashboard = configFlag(config, 'sendToDashboard', 1);
%    if contains(env_new, "antonov") 
%        sendToDataSpace = 0;
%        sendToDashboard = 0;
%    end
    
    % Initialize job management
    if realTimeMode == "aggregator"
        performance_monitor('start', 'job_initialization');
        job_manager('init');
        performance_monitor('end', 'job_initialization');
    end
    
    % Data loading and preparation
    performance_monitor('start', 'data_preparation');
    subjects = config.subjects;
    OVLPTemplate = struct("CVE", "", "VALUE", 0, "EM", "", "AV", "", "AC", "", "PR", "", "UI", "", "VC", "", "VA", "", "VI", "", "AR", "");
    objects = config.objects;
    % Normalize objects (avoid dot-index errors)
    if iscell(objects), objects = [objects{:}]; end
    if istable(objects), objects = table2struct(objects); end
    
    % Check cache for SBOM data. Include file size/time in the key so a
    % changed SBOM at the same path is not reused from the in-memory cache.
    cache_key = sprintf('sbom_%s_%s', char(sbom), char(string(config.sbomFileName)));
    if sbom == "file"
        try
            sbomInfo = dir(char(string(config.sbomFileName)));
            if ~isempty(sbomInfo)
                cache_key = sprintf('sbom_file_%s_%d_%.12g', ...
                    char(string(config.sbomFileName)), sbomInfo(1).bytes, sbomInfo(1).datenum);
            else
                cache_key = sprintf('sbom_file_%s_missing', char(string(config.sbomFileName)));
            end
        catch
        end
    end
    cached_data = data_cache('get', cache_key);
    
    if ~isempty(cached_data) && sbom == "file"
        objects = cached_data.objects;
        % Normalize after cache
        if iscell(objects), objects = [objects{:}]; end
        if istable(objects), objects = table2struct(objects); end
        OVLP = cached_data.OVLP;
        fprintf('Using cached SBOM data\n');
    else
        if sbom == "manual"
            CVEList = config.CVEList;
            nCVEs = length(CVEList);
            OVLP = repmat(OVLPTemplate, nCVEs, 1);
            for CVE = 1:nCVEs
                try
                    CVEStruct = getCVEStruct(CVEList(CVE));
                catch ME
                    if strcmp(ME.identifier, 'CVEUnavailable:NoCache')
                        cveIdStr = char(string(CVEList(CVE)));
                        fprintf('Stopping: CVE %s unavailable and not cached.\n', cveIdStr);
                        return;
                    else
                        rethrow(ME);
                    end
                end
                OVLP(CVE) = parseCVE(CVEStruct, OVLPTemplate);
            end
        else
            filename = config.sbomFileName;
            if contains(filename, 'Antonov_sbom')
                [objects, OVLP] = parseSBOMJson(filename, OVLPTemplate, objects, 3);
            else
                [objects, OVLP] = parseSBOM(filename, OVLPTemplate, objects, 3);
            end
            % Normalize after parse
            if iscell(objects), objects = [objects{:}]; end
            if istable(objects), objects = table2struct(objects); end
            
            % Cache the results
            data_cache('store', cache_key, struct('objects', objects, 'OVLP', OVLP));
        end
    end
    
    NT = config.NT;
    nUsers = length(subjects);
    nObjects = length(objects);
    ACL = cell(nUsers, nObjects);
    ACL(:,:) = {"None"};
    
    % Process ACL configuration
    aclStruct = config.ACL;
    aclKeys = fieldnames(aclStruct);
    numEntries = length(aclKeys);
    for i = 1:numEntries
        key = aclKeys{i};
        [src, dst] = strtok(key, '_');
        dst = strrep(dst, '_', '');
        src = strrep(src, 'x', '');
        aclEntry = aclStruct.(key);
        permission = aclEntry.Permission;
        sca = aclEntry.SCA;
        ACL(uint16(str2double(src)), uint16(str2double(dst))) = {struct("Permission", permission, "SCA", sca)};
    end
    
    % Load network and assessment data
    networkFileName = config.networkFileName;
    OAFFilename = config.OAFFilename;
    SABFileName = config.SABFileName;
    
    objectsNames = strings(1, nObjects);
    for i = 1:length(objects)
        objectsNames(i) = objects(i).Name;
    end

    startupUsersNames = "User " + string((1:nUsers)');
    exportPermissionMatrix(ACL, startupUsersNames, objectsNames, config);
    
    objectsOAF = getOAF(OAFFilename, objectsNames);
    for i = 1:length(objects)
        objects(i).OAF = objectsOAF(i);
    end
    
    subjectsSAB = getSAB(SABFileName, nUsers);
    for i = 1:nUsers
        subjects(i).SAB = subjectsSAB(i);
    end
    
    % Calculate impacts and LOI
    impacts = zeros(nObjects, 1);
    if LOIinput == "zabbix"
        %if contains(networkFileName, 'nokia')
        %    [networkArchitecture, pageRanks, objectsNamesZabbix, adjMatrix] = parseXML_Coord(networkFileName, gui);
        %else
        [~, pageRanks, objectsNamesZabbix, adjMatrix] = parseXML_ID(networkFileName, gui);
        %end
        LOIMatrix = adjMatrix;
    end
    
    for object = 1:nObjects
        if LOIinput == "zabbix"
            objects(object).LOI = pageRanks(objectsNamesZabbix == objects(object).Name);
            impacts(object) = objects(object).LOI;
        else
            LOIMatrix = getLOIMatrix('influence_nokia.csv');
            impacts = sum(LOIMatrix, 2);
            objects(object).LOI = impacts(object) / sum(impacts);
        end
    end
    
    % Handle OVLP inheritance
    if OVLPMethod == "inherit"
        OVLPInitial = {objects.OVLP};
        for object1 = 1:nObjects
            for object2 = 1:nObjects
                if LOIMatrix(object1, object2) > minimalImpactLevel
                    if ~isempty(OVLPInitial{object1})
                        objects(object2).OVLP = [objects(object2).OVLP OVLPInitial{object1}];
                    end
                end
            end
        end
        for object = 1:nObjects
            objects(object).OVLP = unique(objects(object).OVLP);
        end
    end
    performance_monitor('end', 'data_preparation');
    
    % Calculate risks using the modular function
    performance_monitor('start', 'risk_calculation');
    [Risks, intermediateNodesGlobal, testInputParametersGlobal, graphArray] = calculate_risks(subjects, objects, OVLP, NT, ACL, config, @map_linguistic);
    performance_monitor('end', 'risk_calculation');

    userColumn = (1:nUsers)';
    usersNames = "User " + string(userColumn);

    % Initial submit of risks to ADI regardless of realTime flag
    %if realTimeMode == "ADI" && (contains(env_new, "nokia") || contains(env_new, "telco"))
    %    inputAssetsIds = [];
    %    for obj = 1:nObjects
            % Pass per-user graphs for this object to resultJSON
    %        graphsForObject = {};
    %        try
    %            graphsForObject = graphArray(:, obj);
    %        catch
    %        end
    %        resultJSON(Risks(:,obj), objects(obj).Name, usersNames, 0, 1, inputAssetsIds, [], [], graphsForObject);
    %    end
        % Aggregated risk submit using aggregatedIndicator (include Users column)
    %    userColumn = (1:nUsers)';
    %    tablerisks = array2table([userColumn, Risks], "VariableNames", ["Users", objectsNames]);
    %    aggregatedIndicator(aggregatedRisk(Risks, impacts, objects, 0.7), tablerisks, 1, [], 0);
    %end
    
    mainFig = [];

    % Run blocking I/O (PNG export + HTTP result submission) BEFORE the risk
    % GUI is opened. While `webwrite`/`create_transaction` calls in
    % export_results are in flight, MATLAB's main thread cannot service GUI
    % callbacks - the listbox row would highlight at the OS level but
    % updatePlot would never fire. Doing this work first keeps the GUI fully
    % responsive once it appears.
    performance_monitor('start', 'graph_image_export');
    try
        exportRiskGraphImages(graphArray, usersNames, objectsNames, config);
    catch MEgraphExport
        fprintf('Risk graph image export failed: %s\n', MEgraphExport.message);
    end
    performance_monitor('end', 'graph_image_export');

    performance_monitor('start', 'result_export');
    try
        [~, ~, ~] = export_results(Risks, subjects, objects, impacts, env_new, realTimeMode, sendToDataSpace, sendToDashboard, graphArray, configFileName);
    catch MEexport
        fprintf('Result export skipped: %s\n', MEexport.message);
    end
    performance_monitor('end', 'result_export');

    % Real-time monitoring (modularized). Started before the GUI so the
    % WebSocket / HTTP-server setup does not block GUI input. ADI and
    % aggregator modes return immediately after kicking off background work;
    % local mode runs an internal loop with periodic processGuiEvents().
    if realTime == "on" && realTimeMode ~= "local"
        performance_monitor('start', 'real_time_setup');
        try
            real_time_monitor('start', realTimeMode, env_new, Risks, nUsers, nObjects, ACL, objects, testInputParametersGlobal, intermediateNodesGlobal, impacts, objectsNames, graphArray, subjects, OVLP, NT, config);
        catch MErealTime
            fprintf('Real-time monitoring skipped: %s\n', MErealTime.message);
        end
        performance_monitor('end', 'real_time_setup');
    end

    % GUI logic. Opened LAST so blocking I/O above cannot starve GUI
    % callbacks. By this point MATLAB's main thread is idle (background WS /
    % HTTP server work, when running, does not hold the main thread between
    % transactions), so the listbox callback fires immediately on selection
    % change.
    if gui == "on"
        performance_monitor('start', 'gui_setup');
        try
            clear plotGUI updatePlot riskPlotSelectionChanged cellSelectedCallback
            mainFig = figure('Name', 'Risk levels', 'Position', [100 100 1200 800], ...
                'NumberTitle', 'off', 'InvertHardcopy', 'off');
            plotGUI(Risks, usersNames, objectsNames, mainFig);
            aggRisk = aggregatedRisk(Risks, impacts, objects, 0.7);
            t = uitable(mainFig, 'Data', Risks, 'ColumnName', cellstr(objectsNames), 'RowName', cellstr(usersNames), ...
                'Position', [20 650 1100 120], 'Tag', 'RiskTable');
            t.CellSelectionCallback = @(src, event) riskTableCellSelected(src, event, graphArray, usersNames, objectsNames);
            labelText = append('Aggregated risk: ', string(aggRisk));
            riskLabel = uicontrol(mainFig, 'Style', 'text', 'String', char(labelText), ...
                'Position', [20, 770, 1100, 30], 'HorizontalAlignment', 'center', ...
                'FontWeight', 'bold', 'Tag', 'RiskAggregateLabel');
            setappdata(mainFig, 'RiskTable', t);
            setappdata(mainFig, 'RiskAggregateLabel', riskLabel);
            % Cache impacts and register mainFig globally so live updates
            % from real_time_monitor / WS transactions can find the GUI
            % via riskGuiUpdate(...).
            setappdata(mainFig, 'RiskImpacts', impacts);
            setappdata(0, 'RiskGuiFigure', mainFig);
            riskGuiLayout(mainFig);
            restoreRiskGuiAfterBlockingWork(mainFig);
        catch MEgui
            fprintf('GUI setup skipped: %s\n', MEgui.message);
        end
        performance_monitor('end', 'gui_setup');
    end

    % Local real-time mode runs an internal blocking loop, so it must be
    % started AFTER the GUI is shown (its loop calls processGuiEvents()
    % every iteration to keep the listbox alive while it polls the snapshot).
    if realTime == "on" && realTimeMode == "local"
        performance_monitor('start', 'real_time_setup');
        try
            real_time_monitor('start', realTimeMode, env_new, Risks, nUsers, nObjects, ACL, objects, testInputParametersGlobal, intermediateNodesGlobal, impacts, objectsNames, graphArray, subjects, OVLP, NT, config);
        catch MErealTime
            fprintf('Real-time monitoring (local) skipped: %s\n', MErealTime.message);
        end
        restoreRiskGuiAfterBlockingWork(mainFig);
        performance_monitor('end', 'real_time_setup');
    end
    
    performance_monitor('end', 'total_execution');
    performance_monitor('report');
    
    fprintf('Risk evaluation completed successfully\n');
    
catch ME
    % Error handling
    error_handler('log_error', 'Risk evaluation failed', ME);
    fprintf('Error: %s\n', ME.message);
    fprintf('See error_log.txt for details\n');
    
    % Cleanup on error
    performance_monitor('clear');
    data_cache('clear');
    error_handler('cleanup');
    
    rethrow(ME);
end 

end

function permissionTable = exportPermissionMatrix(ACL, usersNames, objectsNames, config)
    permissionMatrix = strings(size(ACL));
    for userIdx = 1:size(ACL, 1)
        for objectIdx = 1:size(ACL, 2)
            permissionMatrix(userIdx, objectIdx) = permissionCellText(ACL{userIdx, objectIdx});
        end
    end

    objectColumnNames = matlab.lang.makeValidName(cellstr(objectsNames));
    objectColumnNames = matlab.lang.makeUniqueStrings(objectColumnNames);
    permissionTable = array2table(permissionMatrix, 'VariableNames', objectColumnNames);
    permissionTable = [table(usersNames(:), 'VariableNames', {'Users'}) permissionTable];

    outputFile = "permissions_matrix.csv";
    try
        if nargin >= 4 && isstruct(config) && isfield(config, 'permissionMatrixFileName') && ~isempty(config.permissionMatrixFileName)
            outputFile = string(config.permissionMatrixFileName);
        end
    catch
        outputFile = "permissions_matrix.csv";
    end

    try
        writetable(permissionTable, outputFile);
        fprintf('Permission matrix saved to %s\n', char(outputFile));
    catch ME
        fprintf('Permission matrix export skipped: %s\n', ME.message);
    end
end

function textValue = permissionCellText(entry)
    textValue = "None";
    try
        if isstruct(entry)
            permission = "";
            sca = "";
            if isfield(entry, 'Permission') && ~isempty(entry.Permission)
                permission = string(entry.Permission);
            end
            if isfield(entry, 'SCA') && ~isempty(entry.SCA)
                sca = string(entry.SCA);
            end
            if strlength(permission) > 0 && strlength(sca) > 0
                textValue = permission + " (" + sca + ")";
            elseif strlength(permission) > 0
                textValue = permission;
            end
        elseif ~isempty(entry)
            rawText = string(entry);
            if strlength(rawText) > 0
                textValue = rawText;
            end
        end
    catch
        textValue = "None";
    end
end

function value = configFlag(config, fieldName, defaultValue)
    value = defaultValue;
    try
        if ~isstruct(config) || ~isfield(config, fieldName)
            return;
        end

        rawValue = config.(fieldName);
        if islogical(rawValue)
            value = double(rawValue);
        elseif isnumeric(rawValue)
            value = double(rawValue ~= 0);
        else
            textValue = lower(strtrim(string(rawValue)));
            value = double(textValue == "1" || textValue == "true" || textValue == "on" || textValue == "yes");
        end
    catch
        value = defaultValue;
    end
end

function restoreRiskGuiAfterBlockingWork(mainFig)
    try
        if isempty(mainFig) || ~isvalid(mainFig)
            return;
        end

        lb = [];
        try
            lb = getappdata(mainFig, 'RiskPlotListbox');
        catch
        end
        if isempty(lb) || ~isvalid(lb)
            lb = findobj(mainFig, 'Style', 'listbox');
        end
        if ~isempty(lb)
            lb = lb(1);
            set(lb, 'Enable', 'on', 'BusyAction', 'queue');
            try
                uistack(lb, 'top');
            catch
            end
        end

        set(groot, 'CurrentFigure', mainFig);
        figure(mainFig);
        refresh(mainFig);
        drawnow;
    catch ME
        fprintf('Risk GUI refresh skipped: %s\n', ME.message);
    end
end
