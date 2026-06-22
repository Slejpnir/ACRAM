function [objects, OVLP] = parseSBOMJson(filePath, OVLPTemplate, objects, objectNo)
%PARSESBOMJSON Parse SBOM from Antonov/contextchain JSON format (asset_id, data.CVE_list).
%   Expects JSON with "data"."CVE_list" array of CVE entries (cve_number, score, cvss_vector, remarks).
%   Handles malformed JSON where array elements lack commas (} { -> }, {).
%   Resolves target object from data.subject (e.g. "this CVE relates to UC1 Router." -> Router_1).
%   Falls back to objectNo when subject is missing or no match found.
    txt = fileread(filePath);
    % Fix common malformation: missing commas between array objects
    txt = regexprep(txt, '\}\s*\{', '}, {');
    % Wrap if root object braces are missing (e.g. Antonov export)
    txt = strtrim(txt);
    if ~startsWith(txt, '{')
        txt = ['{' txt '}'];
    end
    raw = jsondecode(txt);
    cves = [];
    if isfield(raw, 'data') && isfield(raw.data, 'CVE_list')
        cves = raw.data.CVE_list;
    elseif isfield(raw, 'CVE_list')
        cves = raw.CVE_list;
    end
    if isempty(cves)
        OVLP = repmat(OVLPTemplate, 0, 1);
        return;
    end
    % Resolve object index from subject metadata (e.g. "this CVE relates to UC1 Router.")
    objIdx = objectNo;
    subj = '';
    if isfield(raw, 'data') && isfield(raw.data, 'subject')
        subj = char(string(raw.data.subject));
    elseif isfield(raw, 'subject')
        subj = char(string(raw.subject));
    end
    if ~isempty(subj)
        resolved = resolveObjectFromSubject(subj, objects);
        if resolved > 0
            objIdx = resolved;
            fprintf('SBOM subject "%s" -> object %d (%s)\n', strtrim(subj), objIdx, objects(objIdx).Name);
        else
            fprintf('SBOM subject "%s" did not match any object; using fallback index %d\n', strtrim(subj), objectNo);
        end
    end
    objectNo = objIdx;
    if isstruct(cves) && ~iscell(cves)
        cves = num2cell(cves);
    end
    n = numel(cves);
    OVLP = repmat(OVLPTemplate, n, 1);
    k = 1;
    for i = 1:n
        if iscell(cves)
            e = cves{i};
        else
            e = cves(i);
        end
        if ~isstruct(e), continue; end
        cveNum = '';
        if isfield(e, 'cve_number')
            cveNum = char(string(e.cve_number));
        elseif isfield(e, 'CVE')
            cveNum = char(string(e.CVE));
        end
        if isempty(cveNum) || ~contains(cveNum, 'CVE')
            continue;
        end
        objects(objectNo).OVLP = [objects(objectNo).OVLP];
        OVLP(k, 1).CVE = cveNum;
        try
            OVLP(k, 1).VALUE = str2double(string(e.score));
            if isnan(OVLP(k, 1).VALUE), OVLP(k, 1).VALUE = 0; end
        catch
            OVLP(k, 1).VALUE = 0;
        end
        if isfield(e, 'remarks')
            rem = upper(strtrim(string(e.remarks)));
            if rem == "NEWFOUND"
                OVLP(k, 1).EM = 'UNREPORTED';
            end
        end
        if isfield(e, 'cvss_vector')
            vec = char(string(e.cvss_vector));
            if isempty(strtrim(vec)) || strcmpi(strtrim(vec), 'unknown')
                % Skip CVSS parsing for empty or unknown
            else
            components = strsplit(vec, '/');
            for j = 1:length(components)
                part = components{j};
                idx = strfind(part, ':');
                if isempty(idx), continue; end
                key = char(extractBefore(part, ':'));
                val = char(extractAfter(part, ':'));
                switch key
                    case 'AV'
                        switch val
                            case 'N', OVLP(k, 1).AV = 'NETWORK';
                            case 'A', OVLP(k, 1).AV = 'ADJACENT';
                            case 'L', OVLP(k, 1).AV = 'LOCAL';
                            case 'P', OVLP(k, 1).AV = 'PHYSICAL';
                        end
                    case 'AC'
                        if strcmpi(char(val), 'L'), OVLP(k, 1).AC = 'LOW'; else, OVLP(k, 1).AC = 'HIGH'; end
                    case 'PR'
                        switch val
                            case 'N', OVLP(k, 1).PR = 'NONE';
                            case 'L', OVLP(k, 1).PR = 'LOW';
                            case 'H', OVLP(k, 1).PR = 'HIGH';
                        end
                    case 'UI'
                        switch val
                            case 'N', OVLP(k, 1).UI = 'NONE';
                            case 'P', OVLP(k, 1).UI = 'PASSIVE';
                            case {'A', 'R'}, OVLP(k, 1).UI = 'ACTIVE';
                        end
                    case {'C', 'VC'}
                        switch val
                            case 'N', OVLP(k, 1).VC = 'NONE';
                            case 'L', OVLP(k, 1).VC = 'LOW';
                            case 'H', OVLP(k, 1).VC = 'HIGH';
                        end
                    case {'I', 'VI'}
                        switch val
                            case 'N', OVLP(k, 1).VI = 'NONE';
                            case 'L', OVLP(k, 1).VI = 'LOW';
                            case 'H', OVLP(k, 1).VI = 'HIGH';
                        end
                    case {'A', 'VA'}
                        switch val
                            case 'N', OVLP(k, 1).VA = 'NONE';
                            case 'L', OVLP(k, 1).VA = 'LOW';
                            case 'H', OVLP(k, 1).VA = 'HIGH';
                        end
                    case 'E'
                        switch val
                            case 'X', OVLP(k, 1).EM = 'NOT-DEFINED';
                            case 'A', OVLP(k, 1).EM = 'ATTACKED';
                            case 'P', OVLP(k, 1).EM = 'PROOF-OF-CONCEPT';
                            case 'U', OVLP(k, 1).EM = 'UNREPORTED';
                        end
                    case 'MAT'
                        switch val
                            case 'X', OVLP(k, 1).AR = 'NOT-DEFINED';
                            case 'N', OVLP(k, 1).AR = 'NONE';
                            case 'P', OVLP(k, 1).AR = 'PRESENT';
                        end
                end
            end
            end
        end
        if OVLP(k, 1).EM == ""
            OVLP(k, 1).EM = 'NOT-DEFINED';
        end
        if OVLP(k, 1).AR == ""
            OVLP(k, 1).AR = 'NOT-DEFINED';
        end
        if OVLP(k, 1).UI == ""
            OVLP(k, 1).UI = 'NOT-DEFINED';
        end
        k = k + 1;
    end
    OVLP = OVLP(1:k-1, :);
    objects(objectNo).OVLP = 1:numel(OVLP);
end

function objIdx = resolveObjectFromSubject(subject, objects)
% Resolve object index by matching subject text to object names.
% E.g. "this CVE relates to UC1 Router." -> object with "Router" in name (Router_1).
    objIdx = 0;
    if isempty(subject) || isempty(objects)
        return;
    end
    subj = lower(strtrim(char(string(subject))));
    if iscell(objects)
        objects = [objects{:}];
    end
    bestScore = 0;
    for i = 1:numel(objects)
        try
            name = objects(i).Name;
        catch
            continue;
        end
        nameStr = lower(char(string(name)));
        tokens = regexp(nameStr, '[a-zA-Z]{2,}', 'match');  % words 2+ chars
        if isempty(tokens)
            continue;
        end
        score = 0;
        for t = 1:length(tokens)
            if contains(subj, tokens{t})
                score = score + length(tokens{t});
            end
        end
        if score > bestScore
            bestScore = score;
            objIdx = i;
        end
    end
end
