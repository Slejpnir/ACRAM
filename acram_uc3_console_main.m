function acram_uc3_console_main(varargin)
%ACRAM_UC3_CONSOLE_MAIN Run UC3 risk evaluation and retain its ADI listener.
mode = '';
if nargin > 0, mode = char(string(varargin{1})); end
assert(nargin <= 1 && any(strcmp(mode, {'', '--offline', '--listen-only'})), ...
    'UC3:InvalidOption', 'Supported options: --offline, --listen-only.');
offline = strcmp(mode, '--offline');
appRoot = getenv('ACRAM_WORKDIR');
if isempty(appRoot), appRoot = pwd; end
appRoot = char(java.io.File(appRoot).getCanonicalPath());
sourceConfig = fullfile(appRoot, 'config_Telco3PC_console.json');
assert(isfile(sourceConfig), 'UC3:MissingConfig', 'UC3 configuration is missing: %s', sourceConfig);

pythonExe = getenv('ACRAM_PYTHON');
if isempty(pythonExe), pythonExe = fullfile(appRoot, 'python', 'python.exe'); end
assert(isfile(pythonExe), 'UC3:MissingPython', 'The UC3 Python runtime is missing.');
pyenv('Version', pythonExe, 'ExecutionMode', 'OutOfProcess');
insert(py.sys.path, int32(0), fullfile(appRoot, 'python-libs'));
insert(py.sys.path, int32(0), appRoot);
py.importlib.import_module('smartqc');
py.importlib.import_module('contextchain');
py.importlib.import_module('websocket');

runParent = fullfile(appRoot, 'uc3-console-runs');
if ~isfolder(runParent), mkdir(runParent); end
[~, nonce] = fileparts(tempname(runParent));
runDir = fullfile(runParent, [char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', 'yyyyMMdd''T''HHmmss''Z''')) '-' nonce]);
assert(~isfolder(runDir), 'UC3:ExistingRun', 'The output directory must be new.');
mkdir(runDir);
oldDir = pwd;
oldStop = getenv('ACRAM_STOP_FILE');
oldReset = getenv('ACRAM_RESET_FILE');
cleanup = onCleanup(@() finishRuntime(oldDir, runDir, oldStop, oldReset));
config = config_manager(sourceConfig);
config.gui = 'off';
config.realTimeMode = 'ADI';
config.sendToDashboard = 0;
config.exportRiskGraphs = false;
config.saveRealtimeResultsToFile = true;
if offline
    config.realTime = 'off';
    config.sendToDataSpace = 0;
    config.disableAdiSend = true;
    config.sbom = 'manual';
    config.CVEList = [];
else
    config.realTime = 'on';
    config.sendToDataSpace = 1;
    config.disableAdiSend = false;
end
pathFields = {'credentialsFileName', 'sbomFileName', 'networkFileName', ...
    'OAFFilename', 'SABFileName'};
for k = 1:numel(pathFields)
    field = pathFields{k};
    if isfield(config, field) && ~isempty(config.(field))
        path = char(string(config.(field)));
        if ~isAbsolutePath(path), path = fullfile(appRoot, path); end
        config.(field) = path;
    end
end
if offline
    config.credentialsFileName = fullfile(runDir, 'offline-no-credentials.json');
end
models = [dir(fullfile(appRoot, 'fiz_*_new.mat')); dir(fullfile(appRoot, 'fiz_OAB.fis'))];
assert(~isempty(models), 'UC3:MissingModels', 'UC3 risk models are missing.');
for k = 1:numel(models)
    copyfile(fullfile(models(k).folder, models(k).name), fullfile(runDir, models(k).name));
end
configPath = fullfile(runDir, 'config.json');
writeJson(configPath, config);
cd(runDir);
assignin('base', 'configFileName', configPath);
setenv('ACRAM_STOP_FILE', fullfile(runDir, 'stop'));
setenv('ACRAM_RESET_FILE', fullfile(runDir, 'reset'));
diary(fullfile(runDir, 'console.txt'));
writeState(runDir, 'initializing');

inputs = [];
if ~offline
    adi = py.importlib.import_module('uc3_adi_console');
    adi.initialize(configPath, runDir);
    if ~strcmp(mode, '--listen-only')
        % Read existing ADI transactions before publishing any baseline risk.
        inputs = jsondecode(char(adi.read_inputs()));
        assert(numel(inputs) == 2, 'UC3:MissingInputs', ...
            'Expected one existing BACON transaction and one existing ATC transaction.');
    end
    adi.set_stage('baseline');
end
fprintf('[UC3] Starting ACRAM with config %s\n', configPath);
EvaluateRisk_main_enhanced(configPath);
if offline
    validateOfflineResult(config, runDir);
    writeState(runDir, 'offline-complete');
    fprintf('[UC3] Offline calculation passed; publishing and monitoring are disabled.\n');
    clear cleanup;
    return;
end
adi.assert_stage('baseline', int32(numel(config.objects)), int32(1));
adi.save_summary();
waitForAuthorization(runDir, 60);
for k = 1:numel(inputs)
    if iscell(inputs), entry = inputs{k}; else, entry = inputs(k); end
    kind = char(string(entry.kind));
    assert(any(strcmp(kind, {'bacon', 'atc'})), 'UC3:InputKind', 'Unexpected input kind.');
    adi.set_stage(kind);
    fprintf('[%s] Processing stored %s transaction: transactionId=%s\n', ...
        char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), upper(kind), ...
        char(string(entry.transaction.id)));
    real_time_monitor_adi_callback(entry.transaction);
    adi.save_summary();
    assertListenerAlive(runDir);
end
if ~isempty(inputs)
    finalSummary = jsondecode(char(adi.publish_final_summary()));
    fprintf('[%s] Sent ADI aggregated transaction: severity=%s, value=%.3f, transactionId=%s\n', ...
        char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        char(string(finalSummary.data.severity)), finalSummary.data.value, ...
        char(string(finalSummary.transaction_id)));
end
adi.set_stage('monitoring');
adi.save_summary();
writeState(runDir, 'listening');
fprintf('[UC3] ACRAM is ready; waiting for stop request at %s\n', getenv('ACRAM_STOP_FILE'));
waitForStop(runDir);
clear cleanup;
end

function tf = isAbsolutePath(path)
tf = startsWith(path, '/') || startsWith(path, '\\') || ...
    ~isempty(regexp(path, '^[A-Za-z]:[\\/]', 'once'));
end

function waitForAuthorization(runDir, timeoutSeconds)
started = tic;
while toc(started) < timeoutSeconds
    pause(0.25);
    processGuiEvents();
    assertListenerAlive(runDir);
    outputPath = fullfile(runDir, 'smartqc_output.json');
    if isfile(outputPath)
        output = fileread(outputPath);
        if contains(output, '[SUCCESS] Authorized'), return; end
        assert(~contains(output, 'Max authentication attempts reached'), ...
            'UC3:AuthorizationFailed', 'ADI WebSocket authorization failed.');
    end
end
error('UC3:AuthorizationTimeout', 'ADI WebSocket authorization did not complete within %d seconds.', timeoutSeconds);
end

function waitForStop(runDir)
stopPath = getenv('ACRAM_STOP_FILE');
assert(~isempty(timerfindall('Name', 'RiskConsoleStopWatcher')), ...
    'UC3:StopWatcherMissing', 'The ADI stop watcher is not running.');
lastPidCheck = tic;
while ~isfile(stopPath)
    pause(0.5);
    processGuiEvents();
    % The native stop watcher consumes/deletes the marker during its callback.
    if isempty(timerfindall('Name', 'RiskConsoleStopWatcher')), return; end
    assert(~isempty(timerfindall('Name', 'SmartQCMonitorPoll', 'Running', 'on')), ...
        'UC3:ListenerStopped', 'The ADI listener stopped unexpectedly.');
    if toc(lastPidCheck) >= 5
        assertListenerAlive(runDir);
        lastPidCheck = tic;
    end
end
end

function assertListenerAlive(runDir)
assert(~isempty(timerfindall('Name', 'RiskConsoleStopWatcher')) && ...
    ~isempty(timerfindall('Name', 'SmartQCMonitorPoll', 'Running', 'on')), ...
    'UC3:ListenerStopped', 'The ADI listener stopped unexpectedly.');
pidPath = fullfile(runDir, 'smartqc_pid.txt');
assert(isfile(pidPath), 'UC3:ListenerStopped', 'The ADI listener PID file is missing.');
pid = str2double(strtrim(fileread(pidPath)));
assert(isfinite(pid) && pid > 0 && fix(pid) == pid, ...
    'UC3:ListenerStopped', 'The ADI listener PID is invalid.');
if ispc
    try
        process = System.Diagnostics.Process.GetProcessById(int32(pid));
        alive = ~process.HasExited;
        process.Dispose();
    catch
        alive = false;
    end
else
    [status, ~] = system(sprintf('kill -0 %.0f 2>/dev/null', pid));
    alive = status == 0;
end
assert(alive, 'UC3:ListenerStopped', 'The ADI listener process stopped unexpectedly.');
end

function validateOfflineResult(config, runDir)
risks = readtable(fullfile(runDir, 'risks.csv'), 'VariableNamingRule', 'preserve');
values = risks{:, 2:end};
assert(isequal(size(values), [numel(config.subjects), numel(config.objects)]), ...
    'UC3:OfflineRisks', 'Unexpected UC3 risk matrix size.');
assert(all(isfinite(values), 'all') && all(values >= 0 & values <= 1, 'all'), ...
    'UC3:OfflineRisks', 'UC3 risk values are invalid.');
for k = 1:numel(config.objects)
    payload = jsondecode(fileread(fullfile(runDir, ['acram_' char(config.objects(k).Name) '_output.json'])));
    assert(isfield(payload, 'value') && isfinite(payload.value), 'UC3:OfflineResult', 'Invalid component result.');
end
aggregate = jsondecode(fileread(fullfile(runDir, 'acram_aggregated_output.json')));
assert(isfield(aggregate, 'data') && isfinite(aggregate.data.value), 'UC3:OfflineResult', 'Invalid aggregate result.');
assert(~isfile(fullfile(runDir, 'smartqc_pid.txt')), 'UC3:OfflineListener', 'Offline execution started a listener.');
end

function writeState(runDir, status)
state = struct('status', status, 'updatedAtUtc', ...
    char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z''')));
writeJson(fullfile(runDir, 'monitor-state.json'), state);
end

function writeJson(path, value)
fileId = fopen(path, 'w');
assert(fileId >= 0, 'UC3:WriteFailed', 'Unable to write %s.', path);
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, '%s\n', jsonencode(value, 'PrettyPrint', true));
clear cleanup;
end

function finishRuntime(oldDir, runDir, oldStop, oldReset)
try
    for name = {'smartqc_output.json', 'smartqc_error.log'}
        source = fullfile(runDir, name{1});
        if isfile(source), copyfile(source, fullfile(runDir, ['listener-' name{1}])); end
    end
catch
end
try
    real_time_monitor('stop');
catch
end
try
    adi = py.importlib.import_module('uc3_adi_console');
    adi.save_summary();
catch
end
try
    adi = py.importlib.import_module('uc3_adi_console');
    adi.restore();
catch
end
try
    statePath = fullfile(runDir, 'monitor-state.json');
    state = jsondecode(fileread(statePath));
    if ~strcmp(state.status, 'offline-complete'), writeState(runDir, 'stopped'); end
catch
end
try
    diary off;
catch
end
setenv('ACRAM_STOP_FILE', oldStop);
setenv('ACRAM_RESET_FILE', oldReset);
try
    cd(oldDir);
catch
end
end
