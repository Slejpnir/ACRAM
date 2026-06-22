function config_validator(config)
%CONFIG_VALIDATOR Validate configuration parameters
%   Validates all configuration parameters and provides helpful error messages

% Validate required fields
required_fields = {'gui', 'realTime', 'realTimeMode', 'env', 'LOIMethod', 'LOIinput', 'OVLPMethod', 'mockOAB', 'minimalImpactLevel', 'sbom'};
for field = required_fields
    if ~isfield(config, field{1})
        error('Missing required configuration field: %s', field{1});
    end
end

% Validate GUI setting
if ~ismember(config.gui, ["on", "off"])
    error('Invalid GUI setting: %s. Must be "on" or "off"', config.gui);
end

% Validate real-time settings
if ~ismember(config.realTime, ["on", "off"])
    error('Invalid realTime setting: %s. Must be "on" or "off"', config.realTime);
end

if config.realTime == "on"
    if ~ismember(config.realTimeMode, ["local", "aggregator", "ADI"])
        error('Invalid realTimeMode: %s. Must be "local", "aggregator", or "ADI"', config.realTimeMode);
    end
end

% Validate LOI method
if ~ismember(config.LOIMethod, ["direct", "indirect"])
    error('Invalid LOIMethod: %s. Must be "zabbix" or "csv"', config.LOIMethod);
end

% Validate LOI input
if ~ismember(config.LOIinput, ["zabbix", "csv"])
    error('Invalid LOIinput: %s. Must be "zabbix" or "csv"', config.LOIinput);
end

% Validate OVLP method
if ~ismember(config.OVLPMethod, ["inherit", "direct"])
    error('Invalid OVLPMethod: %s. Must be "inherit" or "direct"', config.OVLPMethod);
end

% Validate minimal impact level
if ~isnumeric(config.minimalImpactLevel) || config.minimalImpactLevel < 0 || config.minimalImpactLevel > 1
    error('Invalid minimalImpactLevel: %f. Must be a number between 0 and 1', config.minimalImpactLevel);
end

% Validate SBOM setting
if ~ismember(config.sbom, ["manual", "file"])
    error('Invalid sbom setting: %s. Must be "manual" or "file"', config.sbom);
end

% Validate file existence for file-based settings
if config.sbom == "file" && ~isfield(config, 'sbomFileName')
    error('sbomFileName required when sbom is "file"');
end

if config.LOIinput == "zabbix" && ~isfield(config, 'networkFileName')
    error('networkFileName required when LOIinput is "zabbix"');
end

if ~isfield(config, 'OAFFilename')
    error('OAFFilename is required');
end

if ~isfield(config, 'SABFileName')
    error('SABFileName is required');
end

% Validate subjects and objects
if ~isfield(config, 'subjects') || isempty(config.subjects)
    error('subjects array is required and cannot be empty');
end

if ~isfield(config, 'objects') || isempty(config.objects)
    error('objects array is required and cannot be empty');
end

fprintf('Configuration validation passed successfully\n');
end 