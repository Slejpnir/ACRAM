function SPMPFromFile = getPML(filename)
%GETPML Read password policy JSON and map it to SPMP binary controls.
%   The returned dictionary uses the same keys consumed by calcPML:
%   RAL, mPA, ALD, MPA, EPH, ALT, MPL, PCR, SPE.

jsonText = fileread(filename);
data = jsondecode(jsonText);
if ~isfield(data, 'password_policy')
    error('getPML:MissingPasswordPolicy', ...
        'File %s does not contain a password_policy object.', filename);
end

policy = data.password_policy;
SPMPFromFile = dictionary();

SPMPFromFile("RAL") = double(durationMinutes(getFieldOrDefault(policy, 'reset_count_interval', 0)) >= 15);
SPMPFromFile("mPA") = double(getNumericField(policy, 'min_age', getNumericField(policy, 'minimum_password_age', 0)) >= 1);
SPMPFromFile("ALD") = double(durationMinutes(getFieldOrDefault(policy, 'lockout_duration', 0)) >= 15);
SPMPFromFile("MPA") = double(getNumericField(policy, 'max_age', getNumericField(policy, 'maximum_password_age', inf)) <= 90);
SPMPFromFile("EPH") = double(getNumericField(policy, 'history_length', 0) >= 24);
SPMPFromFile("ALT") = double(getNumericField(policy, 'lockout_threshold', inf) <= 5);
SPMPFromFile("MPL") = double(getNumericField(policy, 'min_length', 0) >= 14);
SPMPFromFile("PCR") = double(getLogicalField(policy, 'complexity_enabled', false));
SPMPFromFile("SPE") = double(~getLogicalField(policy, 'reversible_encryption_enabled', false));
end

function value = getFieldOrDefault(s, fieldName, defaultValue)
if isfield(s, fieldName)
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function value = getNumericField(s, fieldName, defaultValue)
raw = getFieldOrDefault(s, fieldName, defaultValue);
value = str2double(string(raw));
if isnan(value)
    value = defaultValue;
end
end

function value = getLogicalField(s, fieldName, defaultValue)
raw = getFieldOrDefault(s, fieldName, defaultValue);
if islogical(raw)
    value = raw;
elseif isnumeric(raw)
    value = raw ~= 0;
else
    rawText = lower(strtrim(string(raw)));
    if any(rawText == ["true", "yes", "on", "1"])
        value = true;
    elseif any(rawText == ["false", "no", "off", "0"])
        value = false;
    else
        value = defaultValue;
    end
end
end

function minutesOut = durationMinutes(raw)
if isnumeric(raw)
    minutesOut = raw;
    return;
end

txt = lower(strtrim(string(raw)));
numVal = str2double(regexp(txt, '[-+]?\d+(\.\d+)?', 'match', 'once'));
if isnan(numVal)
    minutesOut = 0;
elseif contains(txt, "hour")
    minutesOut = numVal * 60;
elseif contains(txt, "day")
    minutesOut = numVal * 24 * 60;
else
    minutesOut = numVal;
end
end
