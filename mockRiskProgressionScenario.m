function outputRoot = mockRiskProgressionScenario(configFileName, outputRoot, exportAllGraphs, scenarioKind)
%MOCKRISKPROGRESSIONSCENARIO Generate a risk progression demo.
%   Saves per-step JSON, CSV, focused graph PNGs, and GUI screenshots.

    if nargin < 1 || isempty(configFileName)
        configFileName = 'config_Nokia_robot_CVE_2025.json';
    end
    if nargin < 4 || isempty(scenarioKind)
        scenarioKind = "robot";
    else
        scenarioKind = lower(string(scenarioKind));
    end
    if nargin < 2 || isempty(outputRoot)
        stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
        outputRoot = fullfile('mock_outputs', [char(scenarioOutputStem(scenarioKind)) '_' stamp]);
    end
    if nargin < 3 || isempty(exportAllGraphs)
        exportAllGraphs = false;
    end

    rootFolder = pwd;
    configPath = fullfile(rootFolder, char(configFileName));
    if ~exist(outputRoot, 'dir')
        mkdir(outputRoot);
    end

    ctx = loadRiskContext(configFileName, scenarioKind);
    subjectsState = ctx.subjects;
    objectsState = ctx.objects;
    ovlpState = ctx.OVLP;
    previousTargetRisk = -inf;

    [stageNames, stageSlugs] = scenarioStages(scenarioKind);

    stepSummaries = [];
    for stepIdx = 1:numel(stageNames)
        [subjectsState, objectsState, ovlpState, indicatorLabels, changedObjects, inputTransactions] = applyStageChanges( ...
            stepIdx, subjectsState, objectsState, ovlpState, ctx.OVLPTemplate, ctx, scenarioKind);

        [Risks, graphArray] = calculateRiskState(ctx, subjectsState, objectsState, ovlpState);
        [aggregateValue, aggregateDetails] = aggregatedRisk(Risks, ctx.impacts, objectsState, 0.7);
        targetRisk = targetObjectRisk(Risks, ctx);

        [subjectsState, objectsState, ovlpState, indicatorLabels, changedObjects, Risks, graphArray, aggregateValue, targetRisk] = ...
            ensureStepIncrease(stepIdx, previousTargetRisk, targetRisk, aggregateValue, ctx, objectsState, ...
            subjectsState, ovlpState, indicatorLabels, changedObjects, Risks, graphArray);
        previousTargetRisk = targetRisk;

        stepDir = fullfile(outputRoot, sprintf('step_%02d_%s', stepIdx, char(stageSlugs(stepIdx))));
        if ~exist(stepDir, 'dir')
            mkdir(stepDir);
        end

        stepSummary = writeStepArtifacts(stepDir, stepIdx, stageNames(stepIdx), ...
            indicatorLabels, changedObjects, inputTransactions, Risks, aggregateValue, aggregateDetails, ...
            targetRisk, graphArray, ctx, objectsState, configPath, exportAllGraphs);
        if isempty(stepSummaries)
            stepSummaries = stepSummary;
        else
            stepSummaries(end+1, 1) = stepSummary; %#ok<AGROW>
        end
    end

    scenarioSummary = struct();
    scenarioSummary.configFileName = char(configFileName);
    scenarioSummary.scenarioKind = char(scenarioKind);
    scenarioSummary.outputRoot = char(outputRoot);
    scenarioSummary.targetObject = char(ctx.targetObjectName);
    if isfield(ctx, 'targetUserIdx') && ~isempty(ctx.targetUserIdx)
        scenarioSummary.targetUser = char(ctx.targetUserName);
        scenarioSummary.targetUserId = char(ctx.targetUserId);
    end
    scenarioSummary.exportAllGraphs = logical(exportAllGraphs);
    scenarioSummary.generatedAt = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    scenarioSummary.steps = stepSummaries;
    writeJsonFile(fullfile(outputRoot, 'scenario_summary.json'), scenarioSummary);

    fprintf('Mock risk progression scenario saved to %s\n', outputRoot);
end

function outputStem = scenarioOutputStem(scenarioKind)
    switch lower(string(scenarioKind))
        case "antonov_uc1"
            outputStem = "risk_progression_antonov_uc1";
        case "antonov_uc3"
            outputStem = "risk_progression_antonov_uc3";
        case "telco_uc3"
            outputStem = "risk_progression_telco_uc3";
        otherwise
            outputStem = "risk_progression";
    end
end

function [stageNames, stageSlugs] = scenarioStages(scenarioKind)
    switch lower(string(scenarioKind))
        case "antonov_uc1"
            stageNames = [
                "Initial risk calculation"
                "SBOM received"
                "UAM indicator received"
            ];
            stageSlugs = [
                "initial_risk"
                "sbom_received"
                "uam_indicator_received"
            ];
        case "antonov_uc3"
            stageNames = [
                "Initial risk calculation"
                "SBOM received"
                "BECON received"
                "NAD received"
            ];
            stageSlugs = [
                "initial_risk"
                "sbom_received"
                "becon_received"
                "nad_received"
            ];
        case "telco_uc3"
            stageNames = [
                "Initial risk calculation"
                "SBOM received"
                "BECON received"
                "NAD received"
            ];
            stageSlugs = [
                "initial_risk"
                "sbom_received"
                "becon_received"
                "nad_received"
            ];
        otherwise
            stageNames = [
                "Initial risk calculation"
                "SBOM received"
                "Robot anomaly indicator received: ATCNAD"
                "Robot anomaly indicator received: BACON"
                "Robot anomaly indicator received: nokiaRAD"
            ];
            stageSlugs = [
                "initial_risk"
                "sbom_received"
                "robot_atcnad_anomaly"
                "robot_bacon_anomaly"
                "robot_nokiarad_anomaly"
            ];
    end
end

function ctx = loadRiskContext(configFileName, scenarioKind)
    config = config_manager(configFileName);
    config.gui = "off";
    config.realTime = "off";
    config.realTimeMode = "mock";
    scenarioKind = lower(string(scenarioKind));

    objects = normalizeStructArray(config.objects);
    subjects = normalizeStructArray(config.subjects);
    nUsers = numel(subjects);
    nObjects = numel(objects);

    objectsNames = strings(1, nObjects);
    for i = 1:nObjects
        objectsNames(i) = string(objects(i).Name);
    end

    objectsOAF = getOAF(config.OAFFilename, objectsNames);
    for i = 1:nObjects
        objects(i).OAF = objectsOAF(i);
    end

    if scenarioKind ~= "antonov_uc1"
        for i = 1:nUsers
            subjects(i).SAB = 0;
        end
    end

    impacts = zeros(nObjects, 1);
    if string(config.LOIinput) == "zabbix"
        [~, pageRanks, objectsNamesZabbix, ~] = parseXML_ID(config.networkFileName, 'off');
        for objectIdx = 1:nObjects
            idx = find(objectsNamesZabbix == objects(objectIdx).Name, 1);
            if ~isempty(idx)
                objects(objectIdx).LOI = pageRanks(idx);
                impacts(objectIdx) = pageRanks(idx);
            end
        end
    else
        LOIMatrix = getLOIMatrix('influence_nokia.csv');
        impacts = sum(LOIMatrix, 2);
        for objectIdx = 1:nObjects
            objects(objectIdx).LOI = impacts(objectIdx) / sum(impacts);
        end
    end

    ovlpTemplate = struct("CVE", "", "VALUE", 0, "EM", "", "AV", "", ...
        "AC", "", "PR", "", "UI", "", "VC", "", "VA", "", "VI", "", "AR", "");
    [objects, OVLP] = clearInitialCves(objects, ovlpTemplate);

    ACL = buildACL(config.ACL, nUsers, nObjects);
    usersNames = "User " + string((1:nUsers)');

    ctx = struct();
    ctx.config = config;
    ctx.subjects = subjects;
    ctx.objects = objects;
    ctx.OVLP = OVLP;
    ctx.OVLPTemplate = ovlpTemplate;
    ctx.NT = config.NT;
    ctx.ACL = ACL;
    ctx.impacts = impacts;
    ctx.usersNames = usersNames;
    ctx.objectsNames = objectsNames;
    ctx.scenarioKind = scenarioKind;
    if scenarioKind == "antonov_uc1"
        ctx.targetObjectName = "Router_1";
        ctx.sbomCveLimit = 50;
        ctx.uamValue = 0.89;
        ctx.uamSeverity = "RED";
        ctx.uamTimestamp = "2026-01-30T17:13:43Z";
        ctx.guiRiskThreshold = 0.50;
    elseif scenarioKind == "antonov_uc3"
        ctx.targetObjectName = "Router_1";
        ctx.sbomCveLimit = 37;
        ctx.beconOabValue = 0.75;
        ctx.nadOabValue = 1.00;
        ctx.guiRiskThreshold = 0.50;
    elseif scenarioKind == "telco_uc3"
        ctx.targetObjectName = "Gateway";
        ctx.sbomCveLimit = 37;
        ctx.beconOabValue = 0.75;
        ctx.nadOabValue = 1.00;
        ctx.guiRiskThreshold = 0.50;
    else
        ctx.targetObjectName = "Robot";
        ctx.guiRiskThreshold = 0;
    end
    ctx.targetObjectIdx = find(objectsNames == ctx.targetObjectName, 1);
    if isempty(ctx.targetObjectIdx)
        error('mockRiskProgressionScenario:MissingTargetObject', ...
            'Target object "%s" was not found in the config.', ctx.targetObjectName);
    end
    ctx.targetUserIdx = [];
    ctx.targetUserName = "";
    ctx.targetUserId = "";
    if scenarioKind == "antonov_uc1"
        ctx.targetUserIdx = selectAntonovTargetUser(ACL, subjects, ctx.targetObjectIdx);
        ctx.targetUserName = usersNames(ctx.targetUserIdx);
        ctx.targetUserId = "user-" + string(ctx.targetUserIdx);
    end
end

function userIdx = selectAntonovTargetUser(ACL, subjects, targetObjectIdx)
    userIdx = [];
    bestScore = -inf;
    for u = 1:size(ACL, 1)
        entry = ACL{u, targetObjectIdx};
        if ~isstruct(entry)
            continue;
        end
        sabValue = subjectSabValue(subjects(u));
        if sabValue >= 0.8
            continue;
        end
        permissionScore = 0;
        scaScore = 0;
        try
            permissionScore = map_linguistic(entry.Permission);
            scaScore = map_linguistic(entry.SCA);
        catch
        end
        score = permissionScore * 10 + (1 - sabValue) - scaScore * 0.01;
        if score > bestScore
            bestScore = score;
            userIdx = u;
        end
    end
    if isempty(userIdx)
        for u = 1:size(ACL, 1)
            if isstruct(ACL{u, targetObjectIdx})
                userIdx = u;
                return;
            end
        end
    end
    if isempty(userIdx)
        error('mockRiskProgressionScenario:MissingTargetUser', ...
            'No ACL user was found for target object index %d.', targetObjectIdx);
    end
end

function value = subjectSabValue(subject)
    value = 0;
    if ~isfield(subject, 'SAB') || isempty(subject.SAB)
        return;
    end
    rawValue = subject.SAB;
    if isnumeric(rawValue)
        value = max(0, min(1, rawValue));
        return;
    end
    textValue = upper(string(rawValue));
    switch textValue
        case "LOW"
            value = map_linguistic("SABLOW");
        case "MEDIUM"
            value = map_linguistic("SABMEDIUM");
        case "HIGH"
            value = map_linguistic("SABHIGH");
        otherwise
            try
                value = map_linguistic(textValue);
            catch
                value = 0;
            end
    end
end

function arr = normalizeStructArray(arr)
    if iscell(arr)
        arr = [arr{:}];
    end
    if istable(arr)
        arr = table2struct(arr);
    end
end

function [objects, OVLP] = clearInitialCves(objects, template)
    OVLP = repmat(template, 0, 1);
    for i = 1:numel(objects)
        objects(i).OVLP = [];
    end
end

function ACL = buildACL(aclStruct, nUsers, nObjects)
    ACL = cell(nUsers, nObjects);
    ACL(:, :) = {"None"};
    aclKeys = fieldnames(aclStruct);
    for i = 1:numel(aclKeys)
        key = aclKeys{i};
        keyText = char(string(key));
        tokens = regexp(keyText, '^x?(\d+)[_,](\d+)$', 'tokens', 'once');
        if isempty(tokens)
            continue;
        end
        userIdx = str2double(tokens{1});
        objectIdx = str2double(tokens{2});
        if isnan(userIdx) || isnan(objectIdx)
            continue;
        end
        if userIdx < 1 || userIdx > nUsers || objectIdx < 1 || objectIdx > nObjects
            continue;
        end
        aclEntry = aclStruct.(key);
        ACL{uint16(userIdx), uint16(objectIdx)} = struct( ...
            "Permission", aclEntry.Permission, "SCA", aclEntry.SCA);
    end
end

function [subjects, objects, OVLP, indicatorLabels, changedObjects, inputTransactions] = applyStageChanges(stepIdx, subjects, objects, OVLP, template, ctx, scenarioKind)
    indicatorLabels = strings(0, 1);
    changedObjects = strings(0, 1);
    inputTransactions = emptyInputTransactions();

    if lower(string(scenarioKind)) == "antonov_uc1"
        [subjects, objects, OVLP, indicatorLabels, changedObjects, inputTransactions] = ...
        applyAntonovUc1Stage(stepIdx, subjects, objects, OVLP, template, ctx);
        return;
    end
    if any(lower(string(scenarioKind)) == ["antonov_uc3", "telco_uc3"])
        [subjects, objects, OVLP, indicatorLabels, changedObjects, inputTransactions] = ...
            applyUc3Stage(stepIdx, subjects, objects, OVLP, template, ctx);
        return;
    end

    switch stepIdx
        case 2
            [objects, OVLP, label] = addMockCve(objects, OVLP, template, ...
                "Robot", "CVE-2099-1001", "SBOM CVE reported -> Robot", "reported");
            indicatorLabels(end+1, 1) = label;
            changedObjects(end+1, 1) = "Robot";
            inputTransactions(end+1, 1) = sbomInputTransaction(objects, "Robot", "CVE-2099-1001");

        case 3
            [objects, label] = setObjectAnomaly(objects, "Robot", 0.25, ...
                "ATCNAD anomaly -> Robot (OAB 0.25)");
            indicatorLabels(end+1, 1) = label;
            changedObjects(end+1, 1) = "Robot";
            inputTransactions(end+1, 1) = componentAnomalyInputTransaction(objects, ...
                "Robot", "ATC Network Event", 0.25, ...
                "atcNetAnomalyExpressReport", "Network Anomaly Detection", ...
                "Check the network traffic at the tapping point");

        case 4
            [objects, label] = setObjectAnomaly(objects, "Robot", 0.75, ...
                "BACON anomaly -> Robot (OAB 0.75)");
            indicatorLabels(end+1, 1) = label;
            changedObjects(end+1, 1) = "Robot";
            inputTransactions(end+1, 1) = componentAnomalyInputTransaction(objects, ...
                "Robot", "BACON", 0.75, ...
                "baconNetAnomalyExpressReport", "Network Anomaly Detection", ...
                "Check the network traffic at the tapping point");

        case 5
            [objects, label] = setObjectAnomaly(objects, "Robot", 0.80, ...
                "nokiaRAD anomaly -> Robot (OAB 0.80)");
            indicatorLabels(end+1, 1) = label;
            changedObjects(end+1, 1) = "Robot";
            inputTransactions(end+1, 1) = componentAnomalyInputTransaction(objects, ...
                "Robot", "NAD Longterm Raw Observation Event", 0.80, ...
                "nadRawObservationExpressReport", "Component Anomaly Detection", ...
                "Check the operation of the DuT (i.e.: the subject)");
    end
end

function [subjects, objects, OVLP, indicatorLabels, changedObjects, inputTransactions] = applyAntonovUc1Stage(stepIdx, subjects, objects, OVLP, template, ctx)
    indicatorLabels = strings(0, 1);
    changedObjects = strings(0, 1);
    inputTransactions = emptyInputTransactions();

    switch stepIdx
        case 2
            sbomPath = fullfile(pwd, char(ctx.config.sbomFileName));
            [objects, sbomOVLP] = parseSBOMJson(sbomPath, template, objects, ctx.targetObjectIdx);
            totalCveCount = numel(sbomOVLP);
            [sbomOVLP, selectedIndexes] = selectRepresentativeCves(sbomOVLP, ctx.sbomCveLimit);

            baseCount = numel(OVLP);
            if isempty(OVLP)
                OVLP = sbomOVLP;
            elseif ~isempty(sbomOVLP)
                OVLP = [OVLP; sbomOVLP];
            end
            for objectIdx = 1:numel(objects)
                objects(objectIdx).OVLP = [];
            end
            if ~isempty(sbomOVLP)
                objects(ctx.targetObjectIdx).OVLP = baseCount + (1:numel(sbomOVLP));
            end

            appliedCount = numel(sbomOVLP);
            label = sprintf('SBOM received from %s -> %s (%d of %d CVEs applied)', ...
                char(ctx.config.sbomFileName), char(ctx.targetObjectName), appliedCount, totalCveCount);
            indicatorLabels(end+1, 1) = string(label);
            changedObjects(end+1, 1) = ctx.targetObjectName;
            inputTransactions(end+1, 1) = sbomFileInputTransaction(ctx, sbomOVLP, selectedIndexes, totalCveCount);

        case 3
            subjects(ctx.targetUserIdx).SAB = ctx.uamValue;
            label = sprintf('UAM indicator -> %s SAB %.2f', ...
                char(ctx.targetUserId), ctx.uamValue);
            indicatorLabels(end+1, 1) = string(label);
            changedObjects = accessibleObjectsForUser(ctx.ACL, ctx.objectsNames, ctx.targetUserIdx);
            if ~any(changedObjects == ctx.targetObjectName)
                changedObjects(end+1, 1) = ctx.targetObjectName;
            end
            inputTransactions(end+1, 1) = uamInputTransaction(ctx);
    end
end

function [subjects, objects, OVLP, indicatorLabels, changedObjects, inputTransactions] = applyUc3Stage(stepIdx, subjects, objects, OVLP, template, ctx)
    indicatorLabels = strings(0, 1);
    changedObjects = strings(0, 1);
    inputTransactions = emptyInputTransactions();

    switch stepIdx
        case 2
            cveList = antonovUc3CveList();
            [sbomOVLP, sourceIndexes] = antonovUc3SbomOVLP(template, cveList);
            totalCveCount = numel(cveList);
            [sbomOVLP, selectedIndexes] = selectRepresentativeCves(sbomOVLP, ctx.sbomCveLimit);
            selectedSourceIndexes = sourceIndexes(selectedIndexes);

            baseCount = numel(OVLP);
            if isempty(OVLP)
                OVLP = sbomOVLP;
            elseif ~isempty(sbomOVLP)
                OVLP = [OVLP; sbomOVLP];
            end
            for objectIdx = 1:numel(objects)
                objects(objectIdx).OVLP = [];
            end
            if ~isempty(sbomOVLP)
                objects(ctx.targetObjectIdx).OVLP = baseCount + (1:numel(sbomOVLP));
            end

            appliedCount = numel(sbomOVLP);
            label = sprintf('SBOM received -> %s (%d scored CVEs applied from %d reported)', ...
                char(ctx.targetObjectName), appliedCount, totalCveCount);
            indicatorLabels(end+1, 1) = string(label);
            changedObjects(end+1, 1) = ctx.targetObjectName;
            inputTransactions(end+1, 1) = antonovUc3SbomInputTransaction( ...
                cveList, appliedCount, selectedSourceIndexes);

        case 3
            [objects, label] = setObjectAnomaly(objects, ctx.targetObjectName, ctx.beconOabValue, ...
                sprintf('BECON/BACON anomaly -> %s (OAB %.2f)', ...
                char(ctx.targetObjectName), ctx.beconOabValue));
            indicatorLabels(end+1, 1) = string(label);
            changedObjects(end+1, 1) = ctx.targetObjectName;
            inputTransactions(end+1, 1) = antonovUc3BeconInputTransaction();

        case 4
            [objects, label] = setObjectAnomaly(objects, ctx.targetObjectName, ctx.nadOabValue, ...
                sprintf('NAD anomaly -> %s (OAB %.2f)', ...
                char(ctx.targetObjectName), ctx.nadOabValue));
            indicatorLabels(end+1, 1) = string(label);
            changedObjects(end+1, 1) = ctx.targetObjectName;
            inputTransactions(end+1, 1) = antonovUc3NadInputTransaction();
    end
end

function [OVLP, sourceIndexes] = antonovUc3SbomOVLP(template, cveList)
    OVLP = repmat(template, numel(cveList), 1);
    sourceIndexes = zeros(numel(cveList), 1);
    appliedCount = 0;

    for i = 1:numel(cveList)
        scoreValue = str2double(string(cveList(i).score));
        cvssVector = string(cveList(i).cvss_vector);
        if isnan(scoreValue) || strlength(cvssVector) == 0 || lower(cvssVector) == "unknown"
            continue;
        end

        ov = template;
        ov.CVE = char(string(cveList(i).cve_number));
        ov.VALUE = scoreValue;
        ov.EM = 'UNREPORTED';
        ov.AR = 'NOT-DEFINED';
        ov = applyCvssVectorToOvlp(ov, cvssVector);
        appliedCount = appliedCount + 1;
        OVLP(appliedCount, 1) = ov;
        sourceIndexes(appliedCount, 1) = i;
    end

    OVLP = OVLP(1:appliedCount, :);
    sourceIndexes = sourceIndexes(1:appliedCount, :);
end

function ov = applyCvssVectorToOvlp(ov, cvssVector)
    components = strsplit(char(cvssVector), '/');
    for j = 1:numel(components)
        part = components{j};
        if ~contains(part, ':')
            continue;
        end
        key = extractBefore(part, ':');
        val = extractAfter(part, ':');
        switch key
            case 'AV'
                switch val
                    case 'N', ov.AV = 'NETWORK';
                    case 'A', ov.AV = 'ADJACENT';
                    case 'L', ov.AV = 'LOCAL';
                    case 'P', ov.AV = 'PHYSICAL';
                end
            case 'AC'
                if strcmpi(val, 'L'), ov.AC = 'LOW'; else, ov.AC = 'HIGH'; end
            case 'PR'
                switch val
                    case 'N', ov.PR = 'NONE';
                    case 'L', ov.PR = 'LOW';
                    case 'H', ov.PR = 'HIGH';
                end
            case 'UI'
                switch val
                    case 'N', ov.UI = 'NONE';
                    case 'P', ov.UI = 'PASSIVE';
                    case {'A', 'R'}, ov.UI = 'ACTIVE';
                end
            case {'C', 'VC'}
                switch val
                    case 'N', ov.VC = 'NONE';
                    case 'L', ov.VC = 'LOW';
                    case 'H', ov.VC = 'HIGH';
                end
            case {'I', 'VI'}
                switch val
                    case 'N', ov.VI = 'NONE';
                    case 'L', ov.VI = 'LOW';
                    case 'H', ov.VI = 'HIGH';
                end
            case {'A', 'VA'}
                switch val
                    case 'N', ov.VA = 'NONE';
                    case 'L', ov.VA = 'LOW';
                    case 'H', ov.VA = 'HIGH';
                end
        end
    end

    if string(ov.AV) == "", ov.AV = 'NETWORK'; end
    if string(ov.AC) == "", ov.AC = 'LOW'; end
    if string(ov.PR) == "", ov.PR = 'NONE'; end
    if string(ov.UI) == "", ov.UI = 'NOT-DEFINED'; end
    if string(ov.VC) == "", ov.VC = 'NONE'; end
    if string(ov.VI) == "", ov.VI = 'NONE'; end
    if string(ov.VA) == "", ov.VA = 'NONE'; end
end

function [selectedOVLP, selectedIndexes] = selectRepresentativeCves(OVLP, maxCount)
    selectedIndexes = 1:numel(OVLP);
    if isempty(OVLP) || numel(OVLP) <= maxCount
        selectedOVLP = OVLP;
        return;
    end

    values = zeros(numel(OVLP), 1);
    for i = 1:numel(OVLP)
        try
            values(i) = double(OVLP(i).VALUE);
        catch
            values(i) = 0;
        end
        values(i) = values(i) + uamSensitivityBonus(OVLP(i));
    end
    [~, order] = sort(values, 'descend');
    selectedIndexes = sort(order(1:maxCount));
    selectedOVLP = OVLP(selectedIndexes);
end

function bonus = uamSensitivityBonus(ovlp)
    bonus = 0;
    try
        uiValue = upper(string(ovlp.UI));
        if uiValue == "ACTIVE" || uiValue == "PASSIVE" || uiValue == "REQUIRED"
            bonus = bonus + 2.0;
        end
    catch
    end
end

function objectNames = accessibleObjectsForUser(ACL, objectsNames, userIdx)
    objectNames = strings(0, 1);
    if userIdx < 1 || userIdx > size(ACL, 1)
        return;
    end
    for objectIdx = 1:numel(objectsNames)
        if isstruct(ACL{userIdx, objectIdx})
            objectNames(end+1, 1) = objectsNames(objectIdx); %#ok<AGROW>
        end
    end
end

function txs = emptyInputTransactions()
    txs = struct('asset_id', {}, 'auth_id', {}, 'auth_public_key', {}, ...
        'data', {}, 'metadata', {}, 'signature', {}, 'id', {}, ...
        'timestamp', {}, 'context_id', {});
end

function tx = sbomInputTransaction(objects, objectName, cveId)
    timestampText = "2026-05-07 09:53:45";
    cve = struct();
    cve.vendor = "mock";
    cve.product = "robot-control";
    cve.version = "1.0.0";
    cve.cve_number = char(cveId);
    cve.severity = "MEDIUM";
    cve.score = "5.9";
    cve.source = "GAD";
    cve.cvss_version = "3";
    cve.cvss_vector = "CVSS:3.1/AV:N/AC:H/PR:H/UI:R/S:U/C:N/I:H/A:N";
    cve.paths = "";
    cve.remarks = "NewFound";
    cve.comments = "Mock SBOM report; AR remains None in risk inputs";

    data = struct();
    data.CVE_list = {cve};
    data.severity = "severity=MEDIUM;score=5.9";
    data.source = "SBOM Tool";
    data.subject = deviceSubject(objects, objectName);
    data.timestamp = timestampText;
    data.type = "CVE list";
    data.value = "1";

    tx = transactionEnvelope(data, "TBD", timestampText, ...
        "30417d40660a946a35ab7fafa2b5b1635c19b0c01c4e49c90d5173638e8189d8", ...
        "GKykBCEVWN413RwEBiiQUoA9W81hcJagFZpyAoxnuqnB", ...
        "c8a5c17284c6690836ea609a3aaa006352180ef3bba767de858d3ff8f703c73c");
end

function tx = sbomFileInputTransaction(ctx, sbomOVLP, selectedIndexes, totalCveCount)
    timestampText = "2026-02-17 14:49:33";
    cveList = repmat(struct('cve_number', "", 'score', 0, 'source', "Antonov_sbom.json"), ...
        numel(sbomOVLP), 1);
    for i = 1:numel(sbomOVLP)
        cveList(i, 1) = struct( ...
            'cve_number', string(sbomOVLP(i).CVE), ...
            'score', sbomOVLP(i).VALUE, ...
            'source', string(ctx.config.sbomFileName));
    end

    data = struct();
    data.CVE_list = cveList;
    data.severity = sbomSeverityLabel(sbomOVLP);
    data.source = "SBOM Tool";
    data.subject = ctx.targetObjectName;
    data.timestamp = timestampText;
    data.type = "CVE list";
    data.value = char(string(totalCveCount));
    data.file_name = char(ctx.config.sbomFileName);
    data.applied_cve_count = numel(sbomOVLP);
    data.total_cve_count = totalCveCount;
    data.selected_cve_indexes = selectedIndexes;

    tx = transactionEnvelope(data, ...
        sprintf('Antonov UC1 SBOM imported for %s; %d representative CVEs applied from %d total entries', ...
        char(ctx.targetObjectName), numel(sbomOVLP), totalCveCount), ...
        timestampText, ...
        "30417d40660a946a35ab7fafa2b5b1635c19b0c01c4e49c90d5173638e8189d8", ...
        "GKykBCEVWN413RwEBiiQUoA9W81hcJagFZpyAoxnuqnB", ...
        "c8a5c17284c6690836ea609a3aaa006352180ef3bba767de858d3ff8f703c73c");
end

function label = sbomSeverityLabel(sbomOVLP)
    if isempty(sbomOVLP)
        label = "UNKNOWN";
        return;
    end
    values = zeros(numel(sbomOVLP), 1);
    for i = 1:numel(sbomOVLP)
        values(i) = double(sbomOVLP(i).VALUE);
    end
    maxValue = max(values);
    if maxValue >= 9.0
        label = "CRITICAL";
    elseif maxValue >= 7.0
        label = "HIGH";
    elseif maxValue >= 4.0
        label = "MEDIUM";
    elseif maxValue > 0
        label = "LOW";
    else
        label = "UNKNOWN";
    end
end

function cveList = antonovUc3CveList()
    rows = {
        "haxx", "curl", "8.7.1-r1", "CVE-2024-11053", "UNKNOWN", "unknown", "unknown", "unknown";
        "haxx", "curl", "8.7.1-r1", "CVE-2024-6197", "HIGH", "7.5", "3", "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:H";
        "haxx", "curl", "8.7.1-r1", "CVE-2024-7264", "MEDIUM", "6.5", "3", "CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:N/A:H";
        "haxx", "curl", "8.7.1-r1", "CVE-2024-8096", "UNKNOWN", "unknown", "unknown", "unknown";
        "haxx", "curl", "8.7.1-r1", "CVE-2024-9681", "MEDIUM", "6.5", "3", "CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:N/I:H/A:L";
        "haxx", "curl", "8.7.1-r1", "CVE-2025-0167", "UNKNOWN", "unknown", "unknown", "unknown";
        "haxx", "curl", "8.7.1-r1", "CVE-2025-0725", "UNKNOWN", "unknown", "unknown", "unknown";
        "haxx", "curl", "8.7.1-r1", "CVE-2025-5025", "UNKNOWN", "unknown", "unknown", "unknown";
        "gnu", "grub2", "2.06-5", "CVE-2021-3695", "MEDIUM", "4.5", "3", "CVSS:3.1/AV:L/AC:H/PR:L/UI:N/S:U/C:L/I:L/A:L";
        "gnu", "grub2", "2.06-5", "CVE-2021-3696", "MEDIUM", "4.5", "3", "CVSS:3.1/AV:L/AC:H/PR:L/UI:N/S:U/C:L/I:L/A:L";
        "gnu", "grub2", "2.06-5", "CVE-2021-3697", "HIGH", "7", "3", "CVSS:3.1/AV:L/AC:H/PR:L/UI:N/S:U/C:H/I:H/A:H";
        "gnu", "grub2", "2.06-5", "CVE-2021-46705", "MEDIUM", "4.4", "3", "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:N/I:L/A:L";
        "gnu", "grub2", "2.06-5", "CVE-2023-4692", "HIGH", "7.8", "3", "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H";
        "gnu", "grub2", "2.06-5", "CVE-2023-4693", "MEDIUM", "4.6", "3", "CVSS:3.1/AV:P/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N";
        "gnu", "grub2", "2.06-5", "CVE-2024-45777", "UNKNOWN", "unknown", "unknown", "unknown";
        "gnu", "grub2", "2.06-5", "CVE-2024-45778", "MEDIUM", "5.5", "3", "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:N/I:N/A:H";
        "gnu", "grub2", "2.06-5", "CVE-2024-45779", "UNKNOWN", "unknown", "unknown", "unknown";
        "gnu", "grub2", "2.06-5", "CVE-2024-45780", "MEDIUM", "6.7", "3", "CVSS:3.1/AV:L/AC:L/PR:H/UI:N/S:U/C:H/I:H/A:H";
        "gnu", "grub2", "2.06-5", "CVE-2024-45782", "UNKNOWN", "unknown", "unknown", "unknown";
        "gnu", "grub2", "2.06-5", "CVE-2024-56737", "UNKNOWN", "unknown", "unknown", "unknown";
        "gnu", "grub2", "2.06-5", "CVE-2024-56738", "UNKNOWN", "unknown", "unknown", "unknown";
        "gnu", "grub2", "2.06-5", "CVE-2025-0678", "UNKNOWN", "unknown", "unknown", "unknown";
        "gnu", "grub2", "2.06-5", "CVE-2025-0684", "MEDIUM", "6.4", "3", "CVSS:3.1/AV:L/AC:H/PR:H/UI:N/S:U/C:H/I:H/A:H";
        "gnu", "grub2", "2.06-5", "CVE-2025-0685", "MEDIUM", "6.4", "3", "CVSS:3.1/AV:L/AC:H/PR:H/UI:N/S:U/C:H/I:H/A:H";
        "gnu", "grub2", "2.06-5", "CVE-2025-0686", "MEDIUM", "6.4", "3", "CVSS:3.1/AV:L/AC:H/PR:H/UI:N/S:U/C:H/I:H/A:H";
        "gnu", "grub2", "2.06-5", "CVE-2025-0689", "MEDIUM", "6.7", "3", "CVSS:3.1/AV:L/AC:H/PR:L/UI:R/S:U/C:H/I:H/A:H";
        "gnu", "grub2", "2.06-5", "CVE-2025-1125", "MEDIUM", "6.7", "3", "CVSS:3.1/AV:L/AC:H/PR:L/UI:R/S:U/C:H/I:H/A:H";
        "insyde", "kernel", "5.15.162-1-59d1431675acc6823a33c7eb2323daeb", "CVE-2023-47252", "UNKNOWN", "unknown", "unknown", "unknown";
        "insyde", "kernel", "5.15.162-1-59d1431675acc6823a33c7eb2323daeb", "CVE-2024-25078", "UNKNOWN", "unknown", "unknown", "unknown";
        "insyde", "kernel", "5.15.162-1-59d1431675acc6823a33c7eb2323daeb", "CVE-2024-52880", "UNKNOWN", "unknown", "unknown", "unknown";
        "unknown", "kernel", "5.15.162-1-59d1431675acc6823a33c7eb2323daeb", "CVE-2025-21609", "CRITICAL", "9.1", "3", "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:H/A:H";
        "openwrt", "luci", "git-23.051.66410-a505bb1", "CVE-2019-12272", "CRITICAL", "9.8", "3", "CVSS:3.0/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H";
        "openwrt", "luci", "git-23.051.66410-a505bb1", "CVE-2021-27821", "MEDIUM", "6.1", "3", "CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N";
        "x-wrt", "luci", "git-23.051.66410-a505bb1", "CVE-2023-3085", "MEDIUM", "6.1", "3", "CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N";
        "samba", "ppp", "2.4.9.git-2021-01-04-4", "CVE-2022-4603", "MEDIUM", "6.5", "3", "CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:N/A:H";
        "zlib", "zlib", "1.2.13-1", "CVE-2023-45853", "CRITICAL", "9.8", "3", "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H";
        "cloudflare", "zlib", "1.2.13-1", "CVE-2023-6992", "MEDIUM", "5.5", "3", "CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:N/I:N/A:H";
    };

    cveList = repmat(struct('vendor', '', 'product', '', 'version', '', ...
        'cve_number', '', 'severity', '', 'score', '', 'source', 'NVD', ...
        'cvss_version', '', 'cvss_vector', '', 'paths', '', ...
        'remarks', 'NewFound', 'comments', ''), size(rows, 1), 1);
    for i = 1:size(rows, 1)
        cveList(i).vendor = char(rows{i, 1});
        cveList(i).product = char(rows{i, 2});
        cveList(i).version = char(rows{i, 3});
        cveList(i).cve_number = char(rows{i, 4});
        cveList(i).severity = char(rows{i, 5});
        cveList(i).score = char(rows{i, 6});
        cveList(i).cvss_version = char(rows{i, 7});
        cveList(i).cvss_vector = char(rows{i, 8});
    end
end

function tx = antonovUc3SbomInputTransaction(cveList, appliedCount, selectedSourceIndexes)
    data = struct();
    data.CVE_list = cveList;
    data.severity = "severity=HIGH;score=65";
    data.source = "SBOM Tool";
    data.subject = "name_src=SBOM";
    data.timestamp = "2026-04-09 06:44:52";
    data.type = "CVE list";
    data.value = char(string(numel(cveList)));
    data.applied_cve_count = appliedCount;
    data.total_cve_count = numel(cveList);
    data.selected_cve_indexes = selectedSourceIndexes(:)';

    tx = providedTransactionEnvelope(data, "TBD", ...
        "5afb5e11dd80025acfc270419b4f61d28bccd82ddbdd02fcfc97b60b5a6d7f98", ...
        "eb108444c8762016236cee8a564a8af7a1bba096c9564bd8d2c64140180ee22f", ...
        "2SMCMH5sU1fLjzbbigjE9gHA4knEXpMuYh1exmGqd8aH", ...
        "mqGBg0CEtErpUtcFErBguqKU5zf7G6wAuk_PypwpqjWv8EoVsLnej8xPgT5v3eI-miMSjhWdidZjfDJxjULYCA", ...
        "1775731492408", ...
        "cd1a2cfe8520a88947721c5ea7b7ee3cce69f19e434a94767f112c2ce68f8def");
end

function tx = antonovUc3BeconInputTransaction()
    data = struct();
    data.involved_ports = ["51129", "53"];
    data.packets_exchanged = "2";
    data.severity = "ON";
    data.source = "BACON";
    data.subject = "Flow anomaly detection event";
    data.supplementary_details = ['{"root_cause": "src_ip_type", ' ...
        '"traffic_participants": ["172.31.67.16", "172.31.0.2"], ' ...
        '"proto": "UDP", "client_bytes": "72", "server_bytes": "174", ' ...
        '"dir": "C25", "flowstart_time": 1778515121}'];
    data.timestamp = "05/11 15:58:41.1349";
    data.type = "anomaly";
    data.value = "1";

    tx = providedTransactionEnvelope(data, "", ...
        "a7f9c0db9454fc97a66c15ce352b65c4a116188143b51db6212066676516b160", ...
        "c7b805ad1896fab534a06fd9e453eaa901b1a272f7273f51a54a8a378cbebcd7", ...
        "6DXWXGihCyoQb25TjnyPYh9f3sRLiD84Qzv8sngZGgz1", ...
        "dNjBlLlA_TRMQzp2tywfjw1ywwPYXs5dpdE-fVV-AcxQI8tJ6YAzim4-QWgzyMrAV2RLXsa8g1-acXaZEoQGAw", ...
        "1778515121254", ...
        "c91f82042835e3265ca38a92bc3a49a80c23ab320066169308e18259f33a4168");
end

function tx = antonovUc3NadInputTransaction()
    data = struct();
    data.involved_ports = "80.0, 41170.0";
    data.packets_exchanged = "10";
    data.root_cause = "dst_ip_type_external, src_ip_type_local";
    data.severity = "ON";
    data.source = "NAD";
    data.subject = "Network anomaly detection event";
    data.timestamp = "07:05:2026 08:55:27";
    data.traffic_participants = "163.162.228.251, 192.168.1.3";
    data.type = "anomaly";
    data.value = "1.8515653465771647";

    tx = providedTransactionEnvelope(data, "none", ...
        "4a189bda90096ffd646157aa3721067407f1f5821e62df5443c9681a52f6d590", ...
        "c48a0db73c5292c897b38c57c00e408a2a46516bfb5cd055f0df395f8d3481b7", ...
        "CJ24XpAwwEeYufx4NY1XAKEXSWCVCwQ6WHFax62xYem", ...
        "yIt81IWMH20CIUA_wkw_lwNcuZtG8rQqBL2s0YwPWvDq70xLS847emNZUFl_nfoYHJUIe0T5ICbx5JRkkddtAw", ...
        "1778144129371", ...
        "248f56c4e85a70bc4ee3350af664ce61d0998366649e3cdb54478f2523d98afb");
end

function tx = providedTransactionEnvelope(data, followUpAction, assetId, authId, authPublicKey, signature, timestampText, contextId)
    metadata = struct();
    metadata.follow_up_actions = char(followUpAction);

    tx = struct();
    tx.asset_id = char(assetId);
    tx.auth_id = char(authId);
    tx.auth_public_key = char(authPublicKey);
    tx.data = data;
    tx.metadata = metadata;
    tx.signature = char(signature);
    tx.id = char(assetId);
    tx.timestamp = char(timestampText);
    tx.context_id = char(contextId);
end

function tx = uamInputTransaction(ctx)
    data = struct();
    data.type = "UAM user anomaly indicator";
    data.severity = ctx.uamSeverity;
    data.value = ctx.uamValue;
    data.timestamp = ctx.uamTimestamp;
    data.source = "UAM";
    data.user_id = char(ctx.targetUserId);

    tx = transactionEnvelope(data, ...
        "Investigate anomalous user behavior", ...
        "2026-01-30 17:13:43", ...
        "3f8a410fa67f846c22d0cbfc4684ac56e76831ec96dd38487b3e40dc0b93466d", ...
        "7eTPUfptn41SbVJH2eTt4PzgL2rVAi9YtBXpZ8WmArzM", ...
        "2718e8975fa329947434f1ac88d9f07a1438195b9c50e22e6401d7c054237ec8");
end

function tx = componentAnomalyInputTransaction(objects, objectName, sourceName, value, topic, txType, actionText)
    timestampText = "2026-05-07 20:30:46";
    messageCount = struct();
    messageCount.ON = 1;
    messageCount.OFF = 0;

    details = struct();
    if isNetworkAnomalySource(sourceName, txType)
        sourceIp = deviceIp(objects, objectName);
        destinationIp = "152.53.191.142";
        details.root_cause = "mock_oab_indicator";
        details.source_ip = char(sourceIp);
        details.destination_ip = char(destinationIp);
        details.traffic_participants = {char(sourceIp), char(destinationIp)};
        details.involved_ports = [123, 37158];
        details.packets_exchanged = 2;
        details.severity_label = "High";
        details.detectionTimeStamp = "2026-05-07 20:30:46";
    else
        details.oWindowRaw = 100;
        details.oThresholdRaw = 0.41;
        details.oHysteresis = 0.05;
        details.ON = char(string(value));
        details.OFF = char(string(max(0, 1 - value)));
        details.detectionTimeStamp = "2026-05-07 20:30:46.000000";
    end
    details.SieaTaskId = "931-99279e04-7b09-4b7f-9e7b-c62933e34b31";
    details.topic = char(topic);
    details.serviceLevel = "high";

    data = struct();
    data.message_count = jsonencode(messageCount);
    data.severity = "ON";
    data.source = char(sourceName);
    data.subject = transactionSubject(objects, objectName, sourceName, txType);
    data.supplementary_details = jsonencode(details);
    data.timestamp = timestampText;
    data.type = char(txType);
    data.value = char(string(value));

    tx = transactionEnvelope(data, ...
        "Check the operation of the DuT (i.e.: the subject)", timestampText, ...
        "0ac9f8071e0d1c65a1bc0ae811a233508649fdf3e0742fa405487a031310c900", ...
        "7z5PRvbZeF3uNxypRw1pAMJQ8Ta6PvrwQbqG1RvBxi1U", ...
        "9429d22af343a1dc1301af721406cfc401b13eb0adb61042be8dab6f4aa0dc18");
    tx.metadata.follow_up_actions = char(actionText);
end

function isNetwork = isNetworkAnomalySource(sourceName, txType)
    textValue = upper(string(sourceName) + " " + string(txType));
    isNetwork = contains(textValue, "NETWORK") || contains(textValue, "ATC") || ...
        contains(textValue, "ENG") || contains(textValue, "BACON");
end

function subjectText = transactionSubject(objects, objectName, sourceName, txType)
    subjectText = deviceSubject(objects, objectName);
    if ~isNetworkAnomalySource(sourceName, txType)
        return;
    end
    subjectText = subjectText + ";ip_dst=152.53.191.142;name_dst=;";
end

function tx = transactionEnvelope(data, followUpAction, timestampText, authId, publicKey, contextId)
    subjectForSeed = "";
    if isfield(data, 'subject')
        subjectForSeed = string(data.subject);
    elseif isfield(data, 'user_id')
        subjectForSeed = string(data.user_id);
    end
    seed = string(data.source) + "|" + subjectForSeed + "|" + string(data.type) + "|" + string(timestampText);
    txId = deterministicHex(seed);
    metadata = struct();
    metadata.follow_up_actions = char(followUpAction);

    tx = struct();
    tx.asset_id = txId;
    tx.auth_id = char(authId);
    tx.auth_public_key = char(publicKey);
    tx.data = data;
    tx.metadata = metadata;
    tx.signature = deterministicSignature(seed);
    tx.id = txId;
    tx.timestamp = epochMillisText(timestampText);
    tx.context_id = char(contextId);
end

function subjectText = deviceSubject(objects, objectName)
    idx = findObjectIndex(objects, objectName);
    if isempty(idx)
        subjectText = "name_src=" + string(objectName);
        return;
    end

    ipText = "";
    if isfield(objects(idx), 'IP')
        ipText = string(objects(idx).IP);
    end
    nameText = string(objects(idx).Name);
    if isfield(objects(idx), 'SymbolicName') && strlength(string(objects(idx).SymbolicName)) > 0
        nameText = string(objects(idx).SymbolicName);
    end

    if strlength(ipText) > 0
        subjectText = "ip_src=" + ipText + ";name_src=" + nameText;
    else
        subjectText = "name_src=" + nameText;
    end
end

function ipText = deviceIp(objects, objectName)
    ipText = "";
    idx = findObjectIndex(objects, objectName);
    if isempty(idx)
        return;
    end
    if isfield(objects(idx), 'IP')
        ipText = string(objects(idx).IP);
    end
end

function epochText = epochMillisText(timestampText)
    dt = datetime(timestampText, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'UTC');
    epochText = char(string(round(posixtime(dt) * 1000)));
end

function signature = deterministicSignature(seed)
    hexText = deterministicHex("signature|" + string(seed));
    signature = [hexText(1:22) '_' hexText(23:44) '-' hexText(43:64)];
end

function hexText = deterministicHex(seed)
    bytes = uint8(char(string(seed)));
    state = uint32(2166136261);
    for i = 1:numel(bytes)
        state = bitxor(state, uint32(bytes(i)));
        state = uint32(mod(uint64(state) * uint64(16777619), uint64(4294967296)));
    end

    parts = strings(1, 8);
    for i = 1:8
        state = uint32(mod(uint64(state) * uint64(1103515245) + uint64(12345 + i), uint64(4294967296)));
        parts(i) = lower(string(dec2hex(state, 8)));
    end
    hexText = char(strjoin(parts, ""));
end

function [objects, OVLP, label] = addMockCve(objects, OVLP, template, objectName, cveId, label, profileName)
    if nargin < 6 || isempty(label)
        label = "SBOM CVE -> " + string(objectName);
    end
    if nargin < 7 || isempty(profileName)
        profileName = "confirmed";
    end

    idx = findObjectIndex(objects, objectName);
    if isempty(idx)
        label = "Skipped " + string(label) + " (object not found)";
        return;
    end

    ov = cveForProfile(template, cveId, profileName);
    if isempty(OVLP)
        OVLP = ov;
    else
        OVLP(end+1, 1) = ov;
    end
    objects(idx).OVLP = unique([objects(idx).OVLP numel(OVLP)], 'stable');
end

function ov = cveForProfile(template, cveId, profileName)
    ov = template;
    ov.CVE = char(cveId);
    ov.VALUE = 9.8;
    ov.AV = 'Network';

    switch string(profileName)
        case "reported"
            ov.EM = 'Proof-of-Concept';
            ov.AC = 'High';
            ov.PR = 'High';
            ov.UI = 'Active';
            ov.VC = 'None';
            ov.VA = 'None';
            ov.VI = 'High';
            ov.AR = 'None';
        otherwise
            ov.EM = 'Attacked';
            ov.AC = 'Low';
            ov.PR = 'None';
            ov.UI = 'None';
            ov.VC = 'High';
            ov.VA = 'High';
            ov.VI = 'High';
            ov.AR = 'None';
    end
end

function [objects, label] = setObjectAnomaly(objects, objectName, level, label)
    idx = findObjectIndex(objects, objectName);
    if isempty(idx)
        label = "Skipped " + string(label) + " (object not found)";
        return;
    end
    if isnumeric(level)
        objects(idx).OAB = level;
    else
        objects(idx).OAB = char(level);
    end
end

function idx = findObjectIndex(objects, objectName)
    names = string({objects.Name});
    idx = find(names == string(objectName), 1);
    if isempty(idx)
        symbolicNames = strings(1, numel(objects));
        for i = 1:numel(objects)
            if isfield(objects(i), 'SymbolicName')
                symbolicNames(i) = string(objects(i).SymbolicName);
            end
        end
        idx = find(symbolicNames == string(objectName), 1);
    end
end

function [Risks, graphArray] = calculateRiskState(ctx, subjects, objects, OVLP)
    [Risks, ~, ~, graphArray] = calculate_risks(subjects, objects, OVLP, ...
        ctx.NT, ctx.ACL, ctx.config, @map_linguistic);
end

function riskValue = targetObjectRisk(Risks, ctx)
    riskValue = max(Risks(:, ctx.targetObjectIdx));
end

function [subjects, objects, OVLP, indicatorLabels, changedObjects, Risks, graphArray, aggregateValue, targetRisk] = ...
        ensureStepIncrease(stepIdx, previousTargetRisk, targetRisk, aggregateValue, ctx, objects, ...
        subjects, OVLP, ...
        indicatorLabels, changedObjects, Risks, graphArray)
    if stepIdx == 1 || targetRisk > previousTargetRisk + 1e-4
        return;
    end

    fprintf('Target object "%s" risk did not increase at step %d; no synthetic uplift applied. Previous %.3f, current %.3f.\n', ...
        char(ctx.targetObjectName), stepIdx, previousTargetRisk, targetRisk);
end

function stepSummary = writeStepArtifacts(stepDir, stepIdx, stepName, indicatorLabels, ...
        changedObjects, inputTransactions, Risks, aggregateValue, aggregateDetails, targetRisk, graphArray, ...
        ctx, ~, configPath, exportAllGraphs)
    saveRiskCsv(fullfile(stepDir, 'risk_matrix.csv'), Risks, ctx.usersNames, ctx.objectsNames);

    inputTransactionsPath = fullfile(stepDir, 'input_transactions.json');
    writeJsonFile(inputTransactionsPath, inputTransactions);

    adiDir = fullfile(stepDir, 'adi_json');
    if ~exist(adiDir, 'dir')
        mkdir(adiDir);
    end
    saveAdiJsonPayloads(adiDir, Risks, aggregateValue, graphArray, ctx, ...
        indicatorLabels, configPath);

    graphDir = fullfile(stepDir, 'risk_graphs');
    if ~exist(graphDir, 'dir')
        mkdir(graphDir);
    end
    graphFiles = saveGraphPngs(graphDir, graphArray, Risks, ctx.usersNames, ...
        ctx.objectsNames, changedObjects, ctx.targetObjectName, exportAllGraphs, ctx);

    screenshotRiskThreshold = NaN;
    screenshotPath = fullfile(stepDir, 'gui_screenshot.png');
    saveGuiScreenshot(screenshotPath, Risks, ctx.usersNames, ctx.objectsNames, ...
        aggregateValue, "All", aggregateValue, screenshotRiskThreshold, ctx.targetUserIdx);
    all3dScreenshotPath = fullfile(stepDir, 'gui_screenshot_all_3d.png');
    saveGuiScreenshot(all3dScreenshotPath, Risks, ctx.usersNames, ctx.objectsNames, ...
        aggregateValue, "All", aggregateValue, screenshotRiskThreshold, ctx.targetUserIdx);

    stepSummary = struct();
    stepSummary.step = stepIdx;
    stepSummary.name = char(stepName);
    stepSummary.targetObject = char(ctx.targetObjectName);
    stepSummary.targetRisk = targetRisk;
    stepSummary.targetPerUserRisk = Risks(:, ctx.targetObjectIdx)';
    if isfield(ctx, 'targetUserIdx') && ~isempty(ctx.targetUserIdx)
        stepSummary.targetUser = char(ctx.targetUserName);
        stepSummary.targetUserId = char(ctx.targetUserId);
        stepSummary.targetUserRisk = Risks(ctx.targetUserIdx, ctx.targetObjectIdx);
        stepSummary.targetUserPerObjectRisk = Risks(ctx.targetUserIdx, :);
    end
    stepSummary.aggregatedRisk = aggregateValue;
    stepSummary.aggregationMethod = char(aggregateDetails.method);
    stepSummary.aggregationAlpha = aggregateDetails.alpha;
    stepSummary.criticalityWeightedRisk = aggregateDetails.criticalityWeightedRisk;
    stepSummary.maxComponentRisk = aggregateDetails.maxRisk;
    stepSummary.impactWeightedRisk = aggregateDetails.impactWeightedRisk;
    stepSummary.changedObjects = cellstr(changedObjects);
    stepSummary.indicators = cellstr(indicatorLabels);
    stepSummary.inputTransactions = inputTransactions;
    stepSummary.directory = char(stepDir);
    stepSummary.inputTransactionsJson = char(inputTransactionsPath);
    stepSummary.riskMatrixCsv = char(fullfile(stepDir, 'risk_matrix.csv'));
    stepSummary.adiJsonDirectory = char(adiDir);
    stepSummary.graphDirectory = char(graphDir);
    stepSummary.graphFiles = cellstr(graphFiles);
    stepSummary.guiScreenshot = char(screenshotPath);
    stepSummary.guiAll3dScreenshot = char(all3dScreenshotPath);
end

function saveRiskCsv(filePath, Risks, usersNames, objectsNames)
    riskCell = cell(size(Risks, 1) + 1, size(Risks, 2) + 1);
    riskCell{1, 1} = 'User';
    riskCell(1, 2:end) = cellstr(objectsNames);
    riskCell(2:end, 1) = cellstr(usersNames);
    riskCell(2:end, 2:end) = num2cell(round(Risks, 4));
    writecell(riskCell, filePath);
end

function saveAdiJsonPayloads(adiDir, Risks, aggregateValue, graphArray, ctx, indicatorLabels, configPath)
    rootFolder = pwd;
    addpath(rootFolder);
    cleanup = onCleanup(@() cd(rootFolder));
    cd(adiDir);

    for objectIdx = 1:numel(ctx.objectsNames)
        graphsForObject = graphArray(:, objectIdx);
        resultJSON(Risks(:, objectIdx), ctx.objectsNames(objectIdx), ctx.usersNames, ...
            1, 0, cellstr(indicatorLabels), [], [], graphsForObject, configPath, indicatorLabels);
    end

    userColumn = (1:numel(ctx.usersNames))';
    tablerisks = array2table([userColumn, Risks], ...
        "VariableNames", ["Users", ctx.objectsNames]);
    tablerisks{:, 2:end} = round(tablerisks{:, 2:end}, 3);
    aggregatedIndicator(aggregateValue, tablerisks, 0, cellstr(indicatorLabels), 1, configPath);
end

function graphFiles = saveGraphPngs(graphDir, graphArray, Risks, usersNames, objectsNames, ...
        changedObjects, targetObjectName, exportAllGraphs, ctx)
    graphFiles = strings(0, 1);
    if exportAllGraphs
        graphFiles = exportRiskGraphImages(graphArray, usersNames, objectsNames, graphDir);
        return;
    end

    pairs = focusedGraphPairs(Risks, objectsNames, changedObjects, targetObjectName, ctx);
    for i = 1:size(pairs, 1)
        u = pairs(i, 1);
        o = pairs(i, 2);
        try
            newFiles = exportRiskGraphImages(graphArray, usersNames, objectsNames, graphDir, u, o);
            graphFiles = [graphFiles; newFiles(:)]; %#ok<AGROW>
        catch ME
            fprintf('Focused graph export skipped for user %d object %d: %s\n', u, o, ME.message);
        end
    end
end

function pairs = focusedGraphPairs(Risks, objectsNames, changedObjects, targetObjectName, ctx)
    pairs = zeros(0, 2);
    targetObjectIdx = find(objectsNames == targetObjectName, 1);
    if ~isempty(targetObjectIdx)
        [~, targetUserIdx] = max(Risks(:, targetObjectIdx));
        if Risks(targetUserIdx, targetObjectIdx) > 0
            pairs(end+1, :) = [targetUserIdx, targetObjectIdx];
        end
        if nargin >= 5 && isfield(ctx, 'targetUserIdx') && ~isempty(ctx.targetUserIdx)
            if Risks(ctx.targetUserIdx, targetObjectIdx) > 0
                pairs(end+1, :) = [ctx.targetUserIdx, targetObjectIdx];
            end
        end
    end

    [~, order] = sort(Risks(:), 'descend');
    for i = 1:min(5, numel(order))
        [u, o] = ind2sub(size(Risks), order(i));
        if Risks(u, o) > 0
            pairs(end+1, :) = [u, o]; %#ok<AGROW>
        end
    end

    for i = 1:numel(changedObjects)
        objectIdx = find(objectsNames == changedObjects(i), 1);
        if isempty(objectIdx)
            continue;
        end
        [~, userIdx] = max(Risks(:, objectIdx));
        if Risks(userIdx, objectIdx) > 0
            pairs(end+1, :) = [userIdx, objectIdx]; %#ok<AGROW>
        end
    end

    if isempty(pairs)
        return;
    end
    pairs = unique(pairs, 'rows', 'stable');
end

function saveGuiScreenshot(filePath, Risks, usersNames, objectsNames, aggregateValue, targetObjectName, targetRisk, riskThreshold, preferredUserIdx)
    fig = [];
    try
        if nargin < 8 || isempty(riskThreshold)
            riskThreshold = 0;
        end
        if nargin < 9
            preferredUserIdx = [];
        end
        fig = figure('Name', 'Risk levels', 'Position', [80 80 1300 850], ...
            'NumberTitle', 'off', 'InvertHardcopy', 'off', 'Visible', 'on');
        plotGUI(Risks, usersNames, objectsNames, fig, riskThreshold, preferredUserIdx);
        t = uitable(fig, 'Data', Risks, 'ColumnName', cellstr(objectsNames), ...
            'RowName', cellstr(usersNames), 'Position', [20 650 1100 120], ...
            'Tag', 'RiskTable');
        selectedPlotName = "";
        if nargin >= 6
            selectedPlotName = string(targetObjectName);
        end
        labelText = "Aggregated risk: " + string(aggregateValue);
        if selectedPlotName == "All"
            labelText = "All risks 3D bars (aggregated: " + string(round(aggregateValue, 5)) + ")";
        elseif nargin >= 7 && strlength(selectedPlotName) > 0
            labelText = string(targetObjectName) + " risk: " + string(round(targetRisk, 5)) + ...
                " (aggregated: " + string(round(aggregateValue, 5)) + ")";
        end
        riskLabel = uicontrol(fig, 'Style', 'text', ...
            'String', char(labelText), ...
            'Position', [20, 770, 1100, 30], 'HorizontalAlignment', 'center', ...
            'FontWeight', 'bold', 'Tag', 'RiskAggregateLabel');
        setappdata(fig, 'RiskTable', t);
        setappdata(fig, 'RiskAggregateLabel', riskLabel);
        riskGuiLayout(fig);
        selectTargetObjectPlot(fig, targetObjectName);
        drawnow;
        pause(0.25);

        try
            frame = getframe(fig);
            imwrite(frame.cdata, filePath);
        catch
            print(fig, filePath, '-dpng', '-r120');
        end
    catch ME
        fprintf('GUI screenshot skipped: %s\n', ME.message);
    end

    try
        if ~isempty(fig) && isvalid(fig)
            close(fig);
        end
    catch
    end
    try
        delete(timerfind('Name', 'RiskPlotSelectionPoll'));
    catch
    end
end

function selectTargetObjectPlot(fig, targetObjectName)
    try
        if nargin < 2 || strlength(string(targetObjectName)) == 0
            return;
        end
        lb = getappdata(fig, 'RiskPlotListbox');
        if isempty(lb) || ~isvalid(lb)
            return;
        end
        items = string(get(lb, 'String'));
        idx = find(items == string(targetObjectName), 1);
        if isempty(idx)
            return;
        end
        set(lb, 'Value', idx);
        riskPlotSelectionChanged(lb, []);
        riskGuiLayout(fig);
    catch ME
        fprintf('Risk GUI target selection skipped: %s\n', ME.message);
    end
end

function writeJsonFile(filePath, data)
    jsonText = jsonencode(data, "PrettyPrint", true);
    jsonText = externalTransactionFieldNames(jsonText);
    fileId = fopen(filePath, 'w');
    if fileId == -1
        error('mockRiskProgressionScenario:WriteFailed', 'Could not open %s for writing.', filePath);
    end
    cleanup = onCleanup(@() fclose(fileId));
    fwrite(fileId, jsonText, 'char');
end

function jsonText = externalTransactionFieldNames(jsonText)
    jsonText = strrep(jsonText, '"message_count":', '"message-count":');
    jsonText = strrep(jsonText, '"supplementary_details":', '"supplementary-details":');
    jsonText = strrep(jsonText, '"follow_up_actions":', '"follow-up-actions":');
    jsonText = strrep(jsonText, '"file_name":', '"file-name":');
    jsonText = strrep(jsonText, '"applied_cve_count":', '"applied-cve-count":');
    jsonText = strrep(jsonText, '"total_cve_count":', '"total-cve-count":');
    jsonText = strrep(jsonText, '"selected_cve_indexes":', '"selected-cve-indexes":');
    jsonText = strrep(jsonText, '"user_id":', '"user-id":');
end
