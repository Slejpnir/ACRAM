function buildResult = build_kubernetes(outputDir)
%BUILD_KUBERNETES Build the Linux ACRAM executable consumed by Dockerfile.
%   Run this function with MATLAB Compiler on Linux using the same MATLAB
%   release as the MATLAB Runtime container (R2025b by default):
%
%     matlab -batch "build_kubernetes('dist/bin')"
%
%   MATLAB Compiler output is platform-specific. A Windows build cannot run
%   in the Linux Kubernetes image.

projectRoot = fileparts(mfilename("fullpath"));
if nargin < 1 || strlength(string(outputDir)) == 0
    outputDir = fullfile(projectRoot, "dist", "bin");
elseif ~startsWith(string(outputDir), filesep)
    outputDir = fullfile(projectRoot, string(outputDir));
end
outputDir = char(outputDir);

if ~isunix || ismac
    error("build_kubernetes:LinuxRequired", ...
        "Build the Kubernetes executable with MATLAB Compiler on Linux.");
end

if isfolder(outputDir)
    existing = dir(outputDir);
    existing = existing(~ismember({existing.name}, {'.', '..'}));
    if ~isempty(existing)
        error("build_kubernetes:OutputNotEmpty", ...
            "Output directory is not empty: %s", outputDir);
    end
else
    mkdir(outputDir);
end

entryPoint = fullfile(projectRoot, "acram_k8s_main.m");
options = compiler.build.StandaloneApplicationOptions(entryPoint);
options.OutputDir = outputDir;
options.ExecutableName = "ACRAM";
options.TreatInputsAsNumeric = false;
options.AutoDetectDataFiles = false;
options.EmbedArchive = true;
options.ObfuscateArchive = false;
options.Verbose = true;

fprintf("[build] Compiling %s into %s\n", entryPoint, outputDir);
buildResult = compiler.build.standaloneApplication(options);
fprintf("[build] Linux standalone application created in %s\n", outputDir);
end
