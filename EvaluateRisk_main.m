clear objects subjects OVLP NT ACL
configFileName = 'config_Nokia.json';
config = config_manager(configFileName);

gui = config.gui;
realTime = config.realTime;
realTimeMode = config.realTimeMode;
env_new = config.env;
LOIMethod = config.LOIMethod;
LOIinput = config.LOIinput;
OVLPMethod = config.OVLPMethod;
mockOAB = config.mockOAB;
minimalImpactLevel = config.minimalImpactLevel;
sbom = config.sbom;

sendToDataSpace = 0;
sendToDashboard = 1;

% --- Job management (modularized) ---
job_manager('init');


% --- HTTP server (modularized) ---
% HTTP server functionality is now handled by http_server.m module


% Data loading and preparation
subjects = config.subjects;
OVLPTemplate = struct("CVE", "", "VALUE", 0, "EM", "", "AV", "", "AC", "", "PR", "", "UI", "", "VC", "", "VA", "", "VI", "", "AR", "");
objects = config.objects;
if sbom == "manual"
    CVEList = config.CVEList;
    nCVEs = length(CVEList);
    OVLP = repmat(OVLPTemplate, nCVEs, 1);
    for CVE = 1:nCVEs
        CVEStruct = getCVEStruct(CVEList(CVE));
        OVLP(CVE) = parseCVE(CVEStruct, OVLPTemplate);
        end
    else
    filename = config.sbomFileName;
    [objects, OVLP] = parseSBOM(filename, OVLPTemplate, objects, 3);
end
NT = config.NT;
nUsers = length(subjects);
nObjects = length(objects);
ACL = cell(nUsers, nObjects);
ACL(:,:) = {"None"};
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
networkFileName = config.networkFileName;
OAFFilename = config.OAFFilename;
SABFileName = config.SABFileName;
objectsNames = strings(1, nObjects);
for i = 1:length(objects)
    objectsNames(i) = objects(i).Name;
end
objectsOAF = getOAF(OAFFilename, objectsNames);
for i = 1:length(objects)
    objects(i).OAF = objectsOAF(i);
end
subjectsSAB = getSAB(SABFileName, nUsers);
for i = 1:nUsers
    subjects(i).SAB = subjectsSAB(i);
end
impacts = zeros(nObjects, 1);
if LOIinput == "zabbix"
    if contains(networkFileName, 'nokia')
        [networkArchitecture, pageRanks, objectsNamesZabbix, adjMatrix] = parseXML_Coord(networkFileName, gui);
    else
        [networkArchitecture, pageRanks, objectsNamesZabbix, adjMatrix] = parseXML_ID(networkFileName, gui);
    end
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

% Calculate risks using the modular function
[Risks, intermediateNodesGlobal, testInputParametersGlobal, graphArray] = calculate_risks(subjects, objects, OVLP, NT, ACL, config, @map_linguistic);

% Export results using the modular function
[csvFileName, assertsList, aggregatedRiskAssertID] = export_results(Risks, subjects, objects, impacts, env_new, realTimeMode, sendToDataSpace, sendToDashboard, graphArray);

userColumn = (1:nUsers)';
usersNames = "User " + string(userColumn);

% GUI logic (preserved)
if gui == "on"
    mainFig = uifigure('Name', 'Risk levels', 'Position', [100 100 1200 800]);
    plotGUI(Risks, usersNames, objectsNames, mainFig);
    aggRisk = aggregatedRisk(Risks, impacts, objects, 0.7);
    t = uitable(mainFig, 'Data', Risks, 'ColumnName', objectsNames, 'RowName', usersNames, ...
        'Position', [20 650 1100 120], 'Tag', 'RiskTable');
    t.CellSelectionCallback = @(src, event) riskTableCellSelected(src, event, graphArray, usersNames, objectsNames);
    setappdata(mainFig, 'RiskTable', t);
    labelText = append('Aggregated risk: ', string(aggRisk));
    uilabel(mainFig, 'Text', labelText, 'Position', [20, 770, 1100, 30], ...
        'HorizontalAlignment', 'center');
    riskGuiLayout(mainFig);
end

% Real-time monitoring (modularized)
if realTime == "on"
    % Start real-time monitoring with all necessary parameters
    real_time_monitor('start', realTimeMode, env_new, Risks, nUsers, nObjects, ACL, objects, testInputParametersGlobal, intermediateNodesGlobal, impacts, objectsNames, graphArray, subjects, OVLP, NT, config);
end
