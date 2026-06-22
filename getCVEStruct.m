function CVEStruct = getCVEStruct(CVEId)
% Normalize CVEId to a scalar char for consistent use
cveIdStr = string(CVEId);
if numel(cveIdStr) ~= 1
    cveIdStr = cveIdStr(1);
end
cveIdStr = char(cveIdStr);
base_url = "https://services.nvd.nist.gov/rest/json/cves/2.0";
api_key = '5c597a2b-2ead-4142-b70c-9541228534bb';
options = weboptions('Timeout', 300, 'HeaderFields', {'apiKey' api_key});

% Cache settings: directory and file per-CVE, refresh at most once per day
cacheDir = 'cve_cache';
if ~isfolder(cacheDir)
    mkdir(cacheDir);
end
safeId = regexprep(cveIdStr, '[^A-Za-z0-9_-]', '_');
cacheFile = fullfile(cacheDir, ['cve_' safeId '.mat']);

% If fresh cache (< 1 day old), return it
if isfile(cacheFile)
    try
        S = load(cacheFile, 'CVEStruct', 'timestamp');
        if isfield(S, 'timestamp')
            ageMinutes = minutes(datetime('now') - S.timestamp);
            if ageMinutes < 24*60
                CVEStruct = S.CVEStruct;
                return;
            end
        end
    catch
        % Ignore cache read errors; we'll try network next
    end
end

% Try to fetch from network; on success, write cache
try
    CVEStruct = webread(base_url, 'cveId', cveIdStr, options);
    timestamp = datetime('now'); %#ok<NASGU>
    save(cacheFile, 'CVEStruct', 'timestamp');
catch ME
    % On failure: use any available cache, even if stale
    if isfile(cacheFile)
        try
            S = load(cacheFile, 'CVEStruct');
            CVEStruct = S.CVEStruct;
            warning('Using cached CVE %s due to fetch error: %s', cveIdStr, ME.message);
            return;
        catch
            % fall through to error
        end
    end
    fprintf('CVE %s is not available online and no cache exists. Stopping.\n', cveIdStr);
    error('CVEUnavailable:NoCache', 'CVE %s unavailable and not cached.', cveIdStr);
end
end

