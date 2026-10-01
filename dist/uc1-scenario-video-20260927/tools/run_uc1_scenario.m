function run_uc1_scenario(appRoot, outputRoot, mode)
% Run the SBOM/UAM sequence, then keep the real ADI listener active.
% Live mode uses UC1's actual ADI websocket and signed/read-back-verified PUTs.
if nargin < 3, mode = 'live'; end
live = strcmp(mode, 'live');
assert(live || strcmp(mode, 'offline'), 'Mode must be live or offline.');
toolsRoot = fileparts(mfilename('fullpath'));
addpath(appRoot, toolsRoot);
assert(~isfolder(outputRoot), 'Use a new output directory for each run.');
mkdir(outputRoot);
oldDir = pwd;
cleanup = onCleanup(@() finishScenario(oldDir));
configPath = fullfile(outputRoot, 'scenario_config.json');
cd(outputRoot);
performance_monitor('clear');
performance_monitor('start', 'total_execution');
fprintf('[k8s] Starting ACRAM with config %s\n', configPath);
performance_monitor('start', 'config_loading');
config = config_manager(fullfile(appRoot, 'config_antonov_2025.json'));
if iscell(config.subjects), config.subjects = [config.subjects{:}]; end
if iscell(config.objects), config.objects = [config.objects{:}]; end
subjects = config.subjects(1:3);
objects = config.objects;
nUsers = numel(subjects); nObjects = numel(objects);
names = string({objects.Name});
target = find(names == "Router_1", 1);
assert(~isempty(target), 'UC1 Router_1 not found.');
config.subjects = subjects;
config.gui = 'off'; config.realTime = 'off'; config.realTimeMode = 'ADI';
config.sendToDataSpace = double(live); config.sendToDashboard = 0;
config.exportRiskGraphs = false; config.parseCVEListFromWebsocket = true;
config.saveRealtimeResultsToFile = true;
config.sbomTargetObjectName = 'Router_1';
config.disableAdiSend = ~live;
config.credentialsFileName = fullfile(appRoot, config.credentialsFileName);
config.sbom = 'manual'; config.CVEList = [];
config_validator(config);
performance_monitor('end', 'config_loading');
performance_monitor('start', 'data_preparation');
ACL = cell(nUsers, nObjects); ACL(:) = {"None"};
fields = fieldnames(config.ACL);
drop = false(size(fields));
for k = 1:numel(fields)
    idx = regexp(fields{k}, '^x?(\d+)_(\d+)$', 'tokens', 'once');
    assert(~isempty(idx), 'Unexpected ACL key.');
    u = str2double(idx{1}); o = str2double(idx{2});
    if u <= nUsers && o <= nObjects
        ACL{u,o} = config.ACL.(fields{k});
    else
        drop(k) = true;
    end
end
config.ACL = rmfield(config.ACL, fields(drop));
writePermissionMatrix(ACL, names);
oaf = getOAF(fullfile(appRoot, config.OAFFilename), names);
[~, ranks, networkNames, ~] = parseXML_ID(fullfile(appRoot, config.networkFileName), 'off');
impacts = zeros(nObjects,1);
for o = 1:nObjects
    objects(o).OAF = oaf(o); objects(o).OVLP = [];
    idx = find(networkNames == names(o), 1);
    if ~isempty(idx), objects(o).LOI = ranks(idx); impacts(o) = ranks(idx); end
end
config.objects = objects;
models = [dir(fullfile(appRoot, 'fiz_*_new.mat')); dir(fullfile(appRoot, 'fiz_OAB.fis'))];
for k = 1:numel(models)
    copyfile(fullfile(models(k).folder, models(k).name), fullfile(outputRoot, models(k).name));
end
writeJson(configPath, config);
assignin('base', 'configFileName', configPath);
setenv('ACRAM_STOP_FILE', fullfile(outputRoot, 'stop'));
setenv('ACRAM_RESET_FILE', fullfile(outputRoot, 'reset'));
performance_monitor('end', 'data_preparation');
OVLP = [];
performance_monitor('start', 'risk_calculation');
[risks, intermediate, inputs, graphs] = calculate_risks(subjects, objects, OVLP, config.NT, ACL, config, @map_linguistic);
performance_monitor('end', 'risk_calculation');
baselineAggregate = aggregatedRisk(risks, impacts, objects, 0.7);
writeJson(fullfile(outputRoot, 'baseline.json'), struct('risks',risks,'aggregate',baselineAggregate));
performance_monitor('start', 'graph_image_export');
exportRiskGraphImages(graphs, "User " + string((1:nUsers)'), names, config);
performance_monitor('end', 'graph_image_export');
if live
    pythonExe = getenv('ACRAM_PYTHON');
    if isempty(pythonExe), pythonExe = '/usr/bin/python3'; end
    pyenv('Version', pythonExe, 'ExecutionMode', 'OutOfProcess');
    insert(py.sys.path, int32(0), appRoot);
    insert(py.sys.path, int32(0), toolsRoot);
    adi = py.importlib.import_module('scenario_adi');
    runId = ['uc1-demo-' char(datetime('now','TimeZone','UTC','Format','yyyyMMdd-HHmmss'))];
    adi.initialize(config.credentialsFileName, outputRoot, runId, ...
        '4b6eab81f65a6a3a89ccc726b5d6cfe161f41dbca3d827dbd0369595380e2cbe');
    adi.set_stage('baseline');
end
performance_monitor('start', 'result_export');
export_results(risks, subjects, objects, impacts, config.env, 'ADI', double(live), 0, graphs, configPath);
baselineDir = fullfile(outputRoot, 'initial-transactions');
mkdir(baselineDir);
for o = 1:nObjects
    fileName = ['acram_' char(names(o)) '_output.json'];
    copyfile(fullfile(outputRoot,fileName), fullfile(baselineDir,fileName));
end
copyfile(fullfile(outputRoot,'acram_aggregated_output.json'), fullfile(baselineDir,'acram_aggregated_output.json'));
copyfile(fullfile(outputRoot,'risks.csv'), fullfile(baselineDir,'risks.csv'));
baselinePayload = jsondecode(fileread(fullfile(baselineDir,'acram_Router_1_output.json')));
publishedBaseline = [baselinePayload.data.per_user_risk_levels.level]';
if live
    adi.assert_stage('baseline', int32(nObjects), int32(1));
    assert(double(adi.verified_component_count('baseline')) == nObjects && ...
        double(adi.verified_aggregate_count('baseline')) == 1, 'Initial risk publication is incomplete.');
end
performance_monitor('end', 'result_export');
if live
    performance_monitor('start', 'real_time_setup');
    real_time_monitor('start', 'ADI', config.env, risks, nUsers, nObjects, ACL, objects, ...
        inputs, intermediate, impacts, names, graphs, subjects, OVLP, config.NT, config);
    performance_monitor('end', 'real_time_setup');
end
performance_monitor('end', 'total_execution');
performance_monitor('report');
fprintf('Risk evaluation completed successfully\n');
if live
    fprintf('[k8s] ACRAM is ready; waiting for stop request at %s\n', getenv('ACRAM_STOP_FILE'));
    waitForWebSocket(45);
    consoleInfo('Submitting SBOM transaction: object=Router_1');
    adi.set_stage('sbom');
    sbomId = char(adi.send_sbom('name_src=Router_1'));
    waitForStage(adi, 'sbom', sbomId, 120, 1);
    sbomState = reportStage(outputRoot, 'sbom');
    assert(any(abs(sbomState.component - publishedBaseline) > 1e-6), 'SBOM did not change Router_1 risk.');
    consoleInfo('Submitting UAM transaction: user=user-1, value=0.890');
    adi.set_stage('uam');
    uamId = char(adi.send_uam('user-1', 0.89));
    waitForStage(adi, 'uam', uamId, 120, 5);
    uamState = reportStage(outputRoot, 'uam');
    assert(abs(uamState.component(1) - sbomState.component(1)) > 1e-6, 'UAM did not change user-1 risk.');
    summary = jsondecode(char(adi.summary_json()));
    writeJson(fullfile(outputRoot, 'live-summary.json'), summary);
    adi.set_stage('complete');
    waitForStop(outputRoot);
else
    tx = struct('id',repmat('a',1,64),'context_id','offline-sbom');
    cve = struct('cve_number','DEMO-CVE-UC1','score','8.8','remarks','NewFound', ...
        'cvss_vector','CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:H');
    tx.data = struct('source','SBOM Tool','type','CVE list','subject','name_src=Router_1','value','1','CVE_list',cve);
    consoleInfo('Processing SBOM transaction: object=Router_1, publishing=disabled');
    real_time_monitor('test_adi_transaction', tx, risks, ACL, objects, inputs, intermediate, impacts, config, subjects, OVLP, config.NT, graphs, true);
    sbomState = reportStage(outputRoot, 'sbom');
    assert(any(abs(sbomState.component - publishedBaseline) > 1e-6), 'SBOM did not change Router_1 risk.');
    tx = struct('id',repmat('b',1,64),'context_id','2718e8975fa329947434f1ac88d9f07a1438195b9c50e22e6401d7c054237ec8');
    tx.data = struct('source','UAM','type','UAM user anomaly indicator','value',0.89);
    tx.data.user_id = 'user-1';
    consoleInfo('Processing UAM transaction: user=user-1, value=0.890, publishing=disabled');
    real_time_monitor('test_adi_transaction', tx, risks, ACL, objects, inputs, intermediate, impacts, config, subjects, OVLP, config.NT, graphs, false);
    uamState = reportStage(outputRoot, 'uam');
    assert(abs(uamState.component(1) - sbomState.component(1)) > 1e-6, 'UAM did not change user-1 risk.');
    consoleInfo('Processing completed: inputTransactions=2, publishing=disabled');
end
clear cleanup;
end

function waitForStop(outputRoot)
% The monitor's stop timer deletes the stop file as it consumes the request.
% Its disappearance must also end this loop, or MATLAB would remain idle
% after the listener had already been disconnected.
stopPath = getenv('ACRAM_STOP_FILE');
assert(~isempty(timerfindall('Name', 'RiskConsoleStopWatcher')), ...
    'UC1:StopWatcherMissing', 'The ADI stop watcher is not running.');
state = struct('status', 'listening', 'startedAtUtc', ...
    char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')));
writeJson(fullfile(outputRoot, 'monitor-state.json'), state);
lastPidCheck = tic;
while ~isfile(stopPath)
    pause(0.5);
    processGuiEvents();
    if isempty(timerfindall('Name', 'RiskConsoleStopWatcher'))
        break;
    end
    pollers = timerfindall('Name', 'SmartQCMonitorPoll', 'Running', 'on');
    assert(~isempty(pollers), 'UC1:ListenerStopped', 'The ADI listener stopped unexpectedly.');
    if isunix && ~ismac && toc(lastPidCheck) >= 5
        pidPath = fullfile(outputRoot, 'smartqc_pid.txt');
        assert(isfile(pidPath), 'UC1:ListenerStopped', 'The ADI listener PID file is missing.');
        pid = str2double(strtrim(fileread(pidPath)));
        assert(isfinite(pid) && pid > 0 && fix(pid) == pid, ...
            'UC1:ListenerStopped', 'The ADI listener PID is invalid.');
        [status, ~] = system(sprintf('kill -0 %.0f 2>/dev/null', pid));
        assert(status == 0, 'UC1:ListenerStopped', 'The ADI listener process stopped unexpectedly.');
        lastPidCheck = tic;
    end
end
end

function waitForWebSocket(timeout)
started = tic;
while toc(started) < timeout
    pause(0.5);
    if isfile('smartqc_output.json')
        text = fileread('smartqc_output.json');
        if contains(lower(text), 'authorized') || contains(text, 'Authorization successful')
            return;
        end
        assert(~contains(text, 'Max authentication attempts'), 'ADI websocket authentication failed.');
    end
end
error('UC1:WebSocketTimeout','No authenticated websocket confirmation in %d seconds.',timeout);
end

function waitForStage(adi, stage, txId, timeout, expectedComponents)
started = tic;
recovered = false;
while toc(started) < timeout
    pause(0.5);
    if double(adi.verified_component_count(stage)) >= expectedComponents && double(adi.verified_aggregate_count(stage)) >= 1
        receivedOnWebSocket = isfile('smartqc_output.json') && contains(fileread('smartqc_output.json'), txId);
        assert(receivedOnWebSocket || recovered, 'Input transaction receipt was not confirmed.');
        adi.assert_stage(stage, int32(expectedComponents), int32(1));
        receiptMethod = 'websocket';
        if recovered, receiptMethod = 'http-readback'; end
        consoleInfo('%s risk update completed: receipt=%s, ADI storage verified', upper(stage), receiptMethod);
        writeJson(fullfile(pwd,[stage '-delivery.json']),struct('transactionId',txId,'transport',receiptMethod));
        return;
    end
    if ~recovered && toc(started) >= 15
        receivedOnWebSocket = isfile('smartqc_output.json') && contains(fileread('smartqc_output.json'), txId);
        if ~receivedOnWebSocket
            transaction = jsondecode(char(adi.read_input_json(stage, txId)));
            consoleInfo('%s notification delayed; receiving stored ADI transaction over HTTP: transactionId=%s', upper(stage), txId);
            real_time_monitor_adi_callback(transaction);
            recovered = true;
        end
    end
end
error('UC1:StageTimeout','No complete verified %s risk update within %d seconds.',stage,timeout);
end

function state = reportStage(outputRoot, stage)
componentPath = fullfile(outputRoot,'acram_Router_1_output.json');
aggregatePath = fullfile(outputRoot,'acram_aggregated_output.json');
assert(isfile(componentPath) && isfile(aggregatePath), 'Scenario output JSON files are missing.');
component = jsondecode(fileread(componentPath));
aggregate = jsondecode(fileread(aggregatePath));
users = component.data.('per_user_risk_levels');
assert(numel(users)==3, 'Scenario output must contain exactly three users.');
state = struct('component',[users.level]','aggregate',aggregate.data.value);
consoleInfo('Risk updated: trigger=%s, object=Router_1, user=user-1, value=%.3f, aggregate=%.3f', upper(stage), state.component(1), state.aggregate);
writeJson(fullfile(outputRoot,[stage '-risk-state.json']),state);
copyfile(componentPath,fullfile(outputRoot,[stage '-component.json']));
copyfile(aggregatePath,fullfile(outputRoot,[stage '-aggregate.json']));
end

function consoleInfo(format, varargin)
timestamp = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
fprintf('[%s] %s\n', timestamp, sprintf(format, varargin{:}));
end

function writePermissionMatrix(ACL, names)
permissions = strings(size(ACL));
for u = 1:size(ACL,1)
    for o = 1:size(ACL,2)
        entry = ACL{u,o};
        if isstruct(entry)
            permissions(u,o) = string(entry.Permission) + " (" + string(entry.SCA) + ")";
        else
            permissions(u,o) = string(entry);
        end
    end
end
columns = matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(cellstr(names)));
matrix = array2table(permissions, 'VariableNames', columns);
matrix = [table("User " + string((1:size(ACL,1))'), 'VariableNames', {'Users'}), matrix];
writetable(matrix, 'permissions_matrix.csv');
fprintf('Permission matrix saved to permissions_matrix.csv\n');
end

function writeJson(path, value)
fid=fopen(path,'w'); assert(fid>=0,'Cannot write scenario artifact.');
c=onCleanup(@() fclose(fid)); fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true)); clear c;
end

function finishScenario(oldDir)
try
    if isfile(fullfile(pwd,'smartqc_output.json'))
        copyfile(fullfile(pwd,'smartqc_output.json'),fullfile(pwd,'listener-output.log'));
    end
    if isfile(fullfile(pwd,'smartqc_error.log'))
        copyfile(fullfile(pwd,'smartqc_error.log'),fullfile(pwd,'listener-error.log'));
    end
catch
end
try, real_time_monitor('stop'); catch, end
try
    statePath = fullfile(pwd, 'monitor-state.json');
    if isfile(statePath)
        state = jsondecode(fileread(statePath));
        state.status = 'stopped';
        state.stoppedAtUtc = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
        writeJson(statePath, state);
    end
catch
end
try, py.scenario_adi.restore(); catch, end
try, performance_monitor('clear'); catch, end
cd(oldDir);
end
