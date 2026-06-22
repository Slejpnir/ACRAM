function error_handler(operation, varargin)
%ERROR_HANDLER Centralized error handling for the risk evaluation system
%   Usage:
%     error_handler('validate_config', config)
%     error_handler('log_error', 'Operation failed', error_struct)
%     error_handler('check_dependencies', required_functions)

persistent log_file

switch lower(operation)
    case 'validate_config'
        config = varargin{1};
        required_fields = {'gui', 'realTime', 'realTimeMode', 'env', 'LOIMethod', 'LOIinput', 'OVLPMethod', 'mockOAB', 'minimalImpactLevel', 'sbom'};
        
        missing_fields = {};
        for field = required_fields
            if ~isfield(config, field{1})
                missing_fields{end+1} = field{1};
            end
        end
        
        if ~isempty(missing_fields)
            error('Configuration missing required fields: %s', strjoin(missing_fields, ', '));
        end
        
    case 'log_error'
        error_msg = varargin{1};
        if isempty(log_file) || log_file == -1
            log_file = fopen('error_log.txt', 'a');
        end
        
        timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
        fprintf(log_file, '[%s] ERROR: %s\n', timestamp, error_msg);
        
        if nargin > 2
            error_struct = varargin{2};
            fprintf(log_file, 'Details: %s\n', getReport(error_struct, 'extended'));
        end
        
    case 'check_dependencies'
        required_functions = varargin{1};
        missing_functions = {};
        
        for func = required_functions
            if ~exist(func{1}, 'file')
                missing_functions{end+1} = func{1};
            end
        end
        
        if ~isempty(missing_functions)
            error('Missing required functions: %s', strjoin(missing_functions, ', '));
        end
        
    case 'cleanup'
        if ~isempty(log_file) && log_file ~= -1
            fclose(log_file);
            log_file = -1; % Reset to invalid file handle
        end
        
    otherwise
        error('Unknown error handler operation: %s', operation);
end
end 