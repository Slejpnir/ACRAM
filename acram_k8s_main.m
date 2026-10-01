function acram_k8s_main(varargin)
%ACRAM_K8S_MAIN Long-running, headless entry point for container deployment.
%   The regular ACRAM entry point starts ADI/aggregator listeners in the
%   background and then returns to an interactive MATLAB session. A compiled
%   Kubernetes process has no interactive session to keep those listeners
%   alive, so this wrapper owns the process lifetime and probe marker files.

runtimeDir = environmentValue("ACRAM_WORKDIR", pwd);
configFile = environmentValue("ACRAM_CONFIG", ...
    fullfile(runtimeDir, "config_Nokia_robot_CVE_2025.json"));
readyFile = environmentValue("ACRAM_READY_FILE", ...
    fullfile(tempdir, "acram", "ready"));
stopFile = environmentValue("ACRAM_STOP_FILE", ...
    fullfile(tempdir, "acram", "stop"));

if ~isempty(varargin) && strlength(string(varargin{1})) > 0
    configFile = string(varargin{1});
end

if ~isfolder(runtimeDir)
    mkdir(runtimeDir);
end
if ~isfile(configFile)
    error("acram_k8s_main:ConfigMissing", ...
        "ACRAM configuration file not found: %s", configFile);
end

ensureParentDirectory(readyFile);
ensureParentDirectory(stopFile);
deleteIfPresent(readyFile);
deleteIfPresent(stopFile);

previousDir = pwd;
cd(runtimeDir);
cleanup = onCleanup(@() shutdownRuntime(readyFile, previousDir));

fprintf("[k8s] Starting ACRAM with config %s\n", configFile);
EvaluateRisk_main_enhanced(configFile);

writeMarker(readyFile, "ready");
fprintf("[k8s] ACRAM is ready; waiting for stop request at %s\n", stopFile);

while ~isfile(stopFile)
    % pause/drawnow let MATLAB timer callbacks service WebSocket events.
    pause(0.5);
    processGuiEvents();
end

fprintf("[k8s] Stop requested; shutting down ACRAM\n");
deleteIfPresent(readyFile);
clear cleanup
end

function value = environmentValue(name, defaultValue)
value = string(getenv(name));
if strlength(value) == 0
    value = string(defaultValue);
end
end

function ensureParentDirectory(filePath)
parentDir = fileparts(char(filePath));
if ~isempty(parentDir) && ~isfolder(parentDir)
    mkdir(parentDir);
end
end

function writeMarker(filePath, state)
fileId = fopen(filePath, "w");
if fileId == -1
    error("acram_k8s_main:MarkerWriteFailed", ...
        "Unable to write runtime marker: %s", filePath);
end
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s %s\n", state, ...
    char(datetime("now", "TimeZone", "UTC", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX")));
clear cleanup
end

function deleteIfPresent(filePath)
if isfile(filePath)
    delete(filePath);
end
end

function shutdownRuntime(readyFile, previousDir)
deleteIfPresent(readyFile);
try
    real_time_monitor("stop");
catch ME
    fprintf("[k8s] Real-time monitor cleanup failed: %s\n", ME.message);
end
try
    http_server("stop");
catch ME
    fprintf("[k8s] HTTP server cleanup failed: %s\n", ME.message);
end
try
    cd(previousDir);
catch
end
end
