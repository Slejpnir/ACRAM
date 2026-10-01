function CVEStruct = getCVEStruct(CVEId)
%GETCVESTRUCT Retrieve and cache one CVE record from the NVD API.
%   Set NVD_API_KEY in the environment to use an NVD API key. Requests also
%   work without a key, subject to the NVD public rate limit.

% Normalize CVEId to a scalar char for consistent use.
cveIdStr = string(CVEId);
if numel(cveIdStr) ~= 1
    cveIdStr = cveIdStr(1);
end
cveIdStr = char(cveIdStr);

baseUrl = "https://services.nvd.nist.gov/rest/json/cves/2.0";
apiKey = strtrim(string(getenv("NVD_API_KEY")));
if strlength(apiKey) > 0
    options = weboptions("Timeout", 300, ...
        "HeaderFields", {'apiKey', char(apiKey)});
else
    options = weboptions("Timeout", 300);
end

% Cache settings: directory and file per-CVE, refresh at most once per day.
cacheDir = "cve_cache";
if ~isfolder(cacheDir)
    mkdir(cacheDir);
end
safeId = regexprep(cveIdStr, "[^A-Za-z0-9_-]", "_");
cacheFile = fullfile(cacheDir, "cve_" + safeId + ".mat");

% If fresh cache (< 1 day old), return it.
if isfile(cacheFile)
    try
        cached = load(cacheFile, "CVEStruct", "timestamp");
        if isfield(cached, "timestamp")
            ageMinutes = minutes(datetime("now") - cached.timestamp);
            if ageMinutes < 24 * 60
                CVEStruct = cached.CVEStruct;
                return;
            end
        end
    catch
        % Ignore cache read errors; try the network next.
    end
end

% Try to fetch from the network; on success, write the cache.
try
    CVEStruct = webread(baseUrl, "cveId", cveIdStr, options);
    timestamp = datetime("now");
    save(cacheFile, "CVEStruct", "timestamp");
catch ME
    % On failure, use any available cache even when it is stale.
    if isfile(cacheFile)
        try
            cached = load(cacheFile, "CVEStruct");
            CVEStruct = cached.CVEStruct;
            warning("Using cached CVE %s due to fetch error: %s", ...
                cveIdStr, ME.message);
            return;
        catch
            % Fall through to the explicit unavailable error.
        end
    end
    fprintf("CVE %s is not available online and no cache exists. Stopping.\n", ...
        cveIdStr);
    error("CVEUnavailable:NoCache", ...
        "CVE %s unavailable and not cached.", cveIdStr);
end
end
