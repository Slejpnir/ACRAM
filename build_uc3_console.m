function result = build_uc3_console(outputDir)
%BUILD_UC3_CONSOLE Build the portable Windows console executable.
projectRoot = fileparts(mfilename('fullpath'));
if nargin < 1 || isempty(outputDir)
    outputDir = fullfile(projectRoot, 'dist', 'uc3-console-build', 'compiler');
end
addpath(projectRoot);
opts = compiler.build.StandaloneApplicationOptions(fullfile(projectRoot, 'acram_uc3_console_main.m'));
opts.OutputDir = outputDir;
opts.ExecutableName = 'ACRAM_UC3';
opts.ExecutableVersion = '0.0.4';
opts.TreatInputsAsNumeric = false;
opts.AutoDetectDataFiles = false;
opts.EmbedArchive = false;
opts.ObfuscateArchive = false;
opts.Verbose = true;
opts.ExecutableIcon = fullfile(projectRoot, 'logo.jpg');
% standaloneApplication keeps stdout/stderr attached to the caller's console.
result = compiler.build.standaloneApplication(opts);
assert(isfile(fullfile(outputDir, 'ACRAM_UC3.exe')));
assert(isfile(fullfile(outputDir, 'ACRAM_UC3.ctf')));
fprintf('UC3_CONSOLE_BUILD_SUCCESS=%s\n', outputDir);
end
