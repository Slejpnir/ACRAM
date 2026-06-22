function config = config_manager(configFileName)
%CONFIG_MANAGER Loads and validates configuration from a JSON file.
%   Throws an error if required fields are missing.
    if nargin < 1
        error('config_manager:NoFile', 'No config file name provided.');
    end
    if ~isfile(configFileName)
        error('config_manager:FileNotFound', 'Config file not found: %s', configFileName);
    end
    config = jsondecode(fileread(configFileName));

    % Normalize objects container and ensure IP field exists
    if isfield(config,'objects')
        objs = config.objects;
        if iscell(objs)
            % ensure each cell struct has IP field
            for k = 1:numel(objs)
                if ~isfield(objs{k},'IP') || isempty(objs{k}.IP)
                    objs{k}.IP = ""; %#ok<*AGROW>
                else
                    objs{k}.IP = string(objs{k}.IP);
                end
            end
            try
                config.objects = [objs{:}]; % struct array
            catch
                % if heterogeneous, leave as cell
                config.objects = objs;
            end
        elseif isstruct(objs)
            if ~isfield(objs,'IP')
                [objs.IP] = deal("");
            else
                for k = 1:numel(objs)
                    if isempty(objs(k).IP)
                        objs(k).IP = "";
                    else
                        objs(k).IP = string(objs(k).IP);
                    end
                end
            end
            config.objects = objs;
        end
    end

    % List of required fields (add/remove as needed)
    requiredFields = {'gui', 'realTime', 'realTimeMode', 'env', 'LOIMethod', 'LOIinput', 'OVLPMethod', 'mockOAB', 'minimalImpactLevel', 'sbom'};
    for i = 1:numel(requiredFields)
        if ~isfield(config, requiredFields{i})
            error('config_manager:MissingField', 'Missing required config field: %s', requiredFields{i});
        end
    end
end 