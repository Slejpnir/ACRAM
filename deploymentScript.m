function deploymentScript(targetDir, doBuild)
%DEPLOYMENTSCRIPT Prepare a runtime bundle with all required non-code files
%   deploymentScript() copies required data/config assets into ./deploy
%   deploymentScript(targetDir) copies into the specified directory.
%
%   This script is intended to fix missing additional files in deployment
%   archives. It collects configuration, credentials, models and data files
%   that the compiled/runtime app expects to find relative to the executable.

    if nargin < 1 || isempty(targetDir)
        targetDir = fullfile(pwd, 'deploy');
    end
    if nargin < 2 || isempty(doBuild)
        doBuild = true;
    end
    if ~exist(targetDir, 'dir')
        mkdir(targetDir);
    end

    % Core configuration and data dependencies used at runtime
    candidateFiles = { ...
        'config_Nokia_robot_CVE_2025.json'; ...
        'network_nokia_2025.xml'; ...
        'nokia_OAF_2025.csv'; ...
        'nokia_SAB.csv'; ...
        'sbom.csv'; ...
        'influence_nokia.csv'; ...
        'fiz_OAB.fis'; ...
        ... % Telco 3PC configuration assets
        'config_Telco3PC.json'; ...
        'network_telco3PC.xml'; ...
        'telco_3PC_OAF.csv'; ...
        'telco_3PC_SAB.csv' ...
    };

    % Include Python library (package) directories if present
    candidateDirs = {};
    try
        if exist('smartqc', 'dir')
            candidateDirs{end+1} = 'smartqc'; %#ok<AGROW>
        end
        if exist('contextchain', 'dir')
            candidateDirs{end+1} = 'contextchain'; %#ok<AGROW>
        end
    catch
    end

    % Optional, include license/readme if present
    optionalFiles = {
        'IMPROVEMENTS_GUIDE.md'
    };

    % Dynamically gather files referenced by all config_*.json files
    additionalFromConfigs = {};
    try
        cfgList = dir('config_*.json');
        for c = 1:numel(cfgList)
            cfgPath = cfgList(c).name;
            try
                cfg = jsondecode(fileread(cfgPath));
                fields = {'networkFileName','OAFFilename','SABFileName','sbomFileName','credentialsFileName'};
                for f = 1:numel(fields)
                    fn = fields{f};
                    if isfield(cfg, fn)
                        val = string(cfg.(fn));
                        if strlength(val) > 0 && exist(char(val), 'file')
                            additionalFromConfigs{end+1} = char(val); %#ok<AGROW>
                        end
                    end
                end
            catch MEc
                fprintf('[deploy] Failed to parse %s: %s\n', cfgPath, MEc.message);
            end
        end
    catch
    end

    % Include inference matrices and model files used at runtime
    extraPatterns = {
        'influence_nokia.csv', ...
        'fiz_*.mat', ...
        '*.fis' ...
    };
    extraMatched = {};
    for p = 1:numel(extraPatterns)
        dd = dir(extraPatterns{p});
        for k = 1:numel(dd)
            extraMatched{end+1} = dd(k).name; %#ok<AGROW>
        end
    end

    % Merge and de-duplicate (normalize to column vectors to avoid size mismatch)
    filesToCopy = [candidateFiles(:); optionalFiles(:); additionalFromConfigs(:); extraMatched(:); candidateDirs(:)];
    filesToCopy = unique(filesToCopy);
    % Absolute paths for build/package additional files (not used directly)
    % Intentionally omitted to avoid linter warnings and accidental inclusion

    manifest = {};
    for i = 1:numel(filesToCopy)
        src = filesToCopy{i};
        try
            if exist(src, 'file')
                % Copy individual file
                copyfile(src, fullfile(targetDir, src));
                manifest{end+1,1} = src; %#ok<AGROW>
            elseif exist(src, 'dir')
                % Copy entire directory (e.g., smartqc Python package)
                destDir = fullfile(targetDir, src);
                if ~exist(destDir, 'dir'), mkdir(destDir); end
                copyfile(src, destDir);
                manifest{end+1,1} = src; %#ok<AGROW>
            else
                fprintf('[deploy] Skipped missing file or directory: %s\n', src);
            end
        catch ME
            fprintf('[deploy] Failed to copy %s: %s\n', src, ME.message);
        end
    end

    % Write manifest for verification
    try
        fid = fopen(fullfile(targetDir, 'files_manifest.txt'), 'w');
        if fid ~= -1
            for i = 1:numel(manifest)
                fprintf(fid, '%s\n', manifest{i});
            end
            fclose(fid);
        end
    catch
    end

    fprintf('[deploy] Copied %d files to %s\n', numel(manifest), targetDir);

    % Optional build/package phase (requires MATLAB Compiler)
    if doBuild
        try
            projectRoot = pwd;
            % Ensure installer uses the copied payload from targetDir
            try
                % Use relative paths rooted at 'deploy' for most assets,
                % but place 'smartqc' / 'contextchain' at the application root.
                deployRelFromRoot = 'deploy';
                additionalRelFromDeploy = cellfun(@(f) fullfile(deployRelFromRoot, f), manifest, 'UniformOutput', false);
                % If smartqc is present, move it to root-level in the package
                hasSmartqc = any(strcmp(manifest, 'smartqc'));
                hasContextchain = any(strcmp(manifest, 'contextchain'));
                if hasSmartqc
                    % Remove deploy/smartqc from additional files
                    isSmartqcInDeploy = cellfun(@(p) endsWith(p, fullfile('deploy','smartqc')), additionalRelFromDeploy);
                    additionalRelFromDeploy = additionalRelFromDeploy(~isSmartqcInDeploy);
                    % Ensure a root-level smartqc exists for packaging
                    try
                        projectRoot = pwd;
                        srcSmartqc = fullfile(projectRoot, 'deploy', 'smartqc');
                        dstSmartqc = fullfile(projectRoot, 'smartqc');
                        cleanupSmartqc = false;
                        if exist(srcSmartqc, 'dir')
                            if ~exist(dstSmartqc, 'dir')
                                copyfile(srcSmartqc, dstSmartqc);
                                cleanupSmartqc = true;
                            end
                            % Add root-level smartqc to AdditionalFiles
                            additionalRelFromDeploy{end+1} = 'smartqc'; %#ok<AGROW>
                        end
                    catch
                    end
                end
                % If contextchain is present, move it to root-level in the package
                if hasContextchain
                    % Remove deploy/contextchain from additional files
                    isCtxInDeploy = cellfun(@(p) endsWith(p, fullfile('deploy','contextchain')), additionalRelFromDeploy);
                    additionalRelFromDeploy = additionalRelFromDeploy(~isCtxInDeploy);
                    % Ensure a root-level contextchain exists for packaging
                    try
                        projectRoot = pwd;
                        srcCtx = fullfile(projectRoot, 'deploy', 'contextchain');
                        dstCtx = fullfile(projectRoot, 'contextchain');
                        if exist(srcCtx, 'dir')
                            if ~exist(dstCtx, 'dir')
                                copyfile(srcCtx, dstCtx);
                            end
                            % Add root-level contextchain to AdditionalFiles
                            additionalRelFromDeploy{end+1} = 'contextchain'; %#ok<AGROW>
                        end
                    catch
                    end
                end
            catch
                additionalRelFromDeploy = {};
            end
            % Exclude any hidden dot-directories, just in case
            try
                sep = filesep;
                isDotDir = cellfun(@(p) contains(p, [sep '.']), additionalRelFromDeploy);
                additionalRelFromDeploy = additionalRelFromDeploy(~isDotDir);
            catch
            end

            % Select entry point per OS
            entryPoint = fullfile(projectRoot, "acram_main.m");
            if ~ispc
                entryPoint = fullfile(projectRoot, "EvaluateRisk_main_enhanced.m");
            end

            % Common build options
            buildOpts = compiler.build.StandaloneApplicationOptions(entryPoint);
            % Auto-detection can pull user dot-dirs on Linux; disable off Windows
            buildOpts.AutoDetectDataFiles = false;
            buildOpts.OutputDir = fullfile(projectRoot, "StandaloneDesktopApp1", "output", "build");
            buildOpts.ObfuscateArchive = false;
            buildOpts.Verbose = true;
            buildOpts.EmbedArchive = false;
            try
                buildOpts.AdditionalFiles = additionalRelFromDeploy;
            catch
            end
            if exist(fullfile(projectRoot, "logo.jpg"), 'file')
                buildOpts.ExecutableIcon = fullfile(projectRoot, "logo.jpg");
                buildOpts.ExecutableSplashScreen = fullfile(projectRoot, "logo.jpg");
            end
            buildOpts.ExecutableName = "ACRAM";
            buildOpts.ExecutableVersion = "0.0.2";
            buildOpts.TreatInputsAsNumeric = false;

            % Build per platform
            if ispc
                buildResult = compiler.build.standaloneWindowsApplication(buildOpts);
            elseif ismac
                buildResult = compiler.build.standaloneMacApplication(buildOpts);
            else
                % Linux and other UNIX-like
                buildResult = compiler.build.standaloneApplication(buildOpts);
            end

            % After build: copy runtime assets next to the executable so
            % running ACRAM.exe from the build folder works without install
            try
                buildOut = buildOpts.OutputDir;
                for i = 1:numel(manifest)
                    src = manifest{i};
                    srcPath = fullfile(targetDir, src);
                    dstPath = fullfile(buildOut, src);
                    if exist(srcPath, 'file')
                        copyfile(srcPath, dstPath);
                    elseif exist(srcPath, 'dir')
                        if ~exist(dstPath, 'dir'), mkdir(dstPath); end
                        copyfile(srcPath, dstPath);
                    end
                end
                fprintf('[deploy] Mirrored %d assets to build output: %s\n', numel(manifest), buildOut);
            catch MEmirror
                fprintf('[deploy] Post-build asset mirror failed: %s\n', MEmirror.message);
            end

            % Package: Windows-only installer. On Linux/macOS, emit a tar.gz bundle instead.
            if ispc
                packageOpts = compiler.package.InstallerOptions(buildResult);
                packageOpts.ApplicationName = "ACRAM";
                packageOpts.AuthorName = "Dmytro SHYROKORAD";
                packageOpts.AuthorEmail = "hoveringphoenix@gmail.com";
                packageOpts.AuthorCompany = "NU ""Zaporizhzhia Polytechnic""";
                if exist(fullfile(projectRoot, "logo.jpg"), 'file')
                    packageOpts.InstallerIcon = fullfile(projectRoot, "logo.jpg");
                    packageOpts.InstallerSplash = fullfile(projectRoot, "logo.jpg");
                end
                packageOpts.OutputDir = fullfile(projectRoot, "StandaloneDesktopApp1", "output", "package");
                packageOpts.RuntimeDelivery = "none";
                packageOpts.Summary = "ACRAM tool for risk levels assessment";
                packageOpts.Verbose = true;
                packageOpts.Version = "0.0.2";
                try
                    packageOpts.AdditionalFiles = additionalRelFromDeploy;
                catch
                end
                compiler.package.installer(buildResult, "Options", packageOpts);
            else
                % Create a simple distributable archive on non-Windows platforms
                try
                    outDir = fullfile(projectRoot, "StandaloneDesktopApp1", "output", "package");
                    if ~exist(outDir, 'dir'), mkdir(outDir); end
                    bundleName = sprintf('ACRAM_%s_%s.tar.gz', computer('arch'), datestr(now,'yyyymmdd_HHMMSS'));
                    bundlePath = fullfile(outDir, bundleName);
                    % Collect files from build output directory
                    buildOut = buildOpts.OutputDir;
                    % Use MATLAB's built-in tar on all platforms
                    tar(bundlePath, {'*'}, buildOut);
                    fprintf('[deploy] Created archive: %s\n', bundlePath);
                catch MEt
                    fprintf('[deploy] Packaging (tar) failed: %s\n', MEt.message);
                end
            end

        catch ME
            fprintf('[deploy] Build/package skipped or failed: %s\n', ME.message);
        end
    end
end