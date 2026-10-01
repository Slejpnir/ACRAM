function build_uc1_scenario_update(appRoot)
%BUILD_UC1_SCENARIO_UPDATE Build a separate UC1 binary with SBOM/UAM updates.
%   build_uc1_scenario_update('/home/wrcve/TELEMETRY/dist')
%   The installed source must already contain the updated real_time_monitor.m.
assert(nargin == 1, 'Pass the absolute installed UC1 application directory.');
assert(isunix && ~ismac, 'Build UC1 on Linux.');
assert(strcmp(version('-release'), '2025a'), 'This UC1 package targets R2025a.');
appRoot = char(string(appRoot));
assert(startsWith(appRoot, filesep) && isfolder(appRoot), ...
    'The UC1 application directory must be an existing absolute path.');
entryFile = fullfile(appRoot, 'acram_uc1_main.m');
monitorFile = fullfile(appRoot, 'real_time_monitor.m');
assert(isfile(entryFile) && isfile(monitorFile), 'Required UC1 source files are missing.');
out = fullfile(appRoot, 'bin-sbom-uam-update');
assert(~isfolder(out) && ~isfile(out), ...
    'Updated build directory already exists; preserve it before rebuilding.');

originalFolder = pwd;
originalPath = path;
cleanup = onCleanup(@() restoreEnvironment(originalFolder, originalPath)); %#ok<NASGU>
cd(appRoot);
addpath(appRoot, '-begin');
clear real_time_monitor acram_uc1_main acram_k8s_main EvaluateRisk_main_enhanced
rehash;
assert(strcmp(which('real_time_monitor'), monitorFile), ...
    'real_time_monitor must resolve to the installed UC1 source.');
monitorSource = fileread(monitorFile);
assert(contains(monitorSource, 'UAM component result send failed') && ...
    contains(monitorSource, 'Received UAM transaction'), ...
    'Install the SBOM/UAM publishing update before compiling.');

opts = compiler.build.StandaloneApplicationOptions(entryFile);
opts.OutputDir = out;
opts.ExecutableName = 'ACRAM';
opts.TreatInputsAsNumeric = false;
opts.AutoDetectDataFiles = false;
opts.EmbedArchive = true;
opts.ObfuscateArchive = false;
opts.Verbose = true;
opts.AdditionalFiles = {monitorFile};
fprintf('UC1 update dependency: %s\n', monitorFile);
compiler.build.standaloneApplication(opts);
assert(isfile(fullfile(out, 'ACRAM')), 'Updated Linux executable is missing.');
fprintf('UC1_SBOM_UAM_BUILD_PASS: %s\n', fullfile(out, 'ACRAM'));
end

function restoreEnvironment(originalFolder, originalPath)
cd(originalFolder);
path(originalPath);
end
