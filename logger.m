function logger(level, message, varargin)
%LOGGER Comprehensive logging system with different levels and formats
%   Usage:
%     logger('info', 'Operation started')
%     logger('warning', 'Configuration issue detected')
%     logger('error', 'Failed to load file', error_struct)
%     logger('debug', 'Variable value: %s', value)
%     logger('set_level', 'info')
%     logger('set_file', 'custom_log.txt')

persistent log_file log_level log_levels

% Initialize log levels if not set
if isempty(log_levels)
    log_levels = containers.Map({'debug', 'info', 'warning', 'error'}, {1, 2, 3, 4});
    log_level = 2; % Default to 'info' level
end

switch lower(level)
    case 'set_level'
        if isKey(log_levels, varargin{1})
            log_level = log_levels(varargin{1});
            fprintf('Log level set to: %s\n', varargin{1});
        else
            fprintf('Invalid log level. Available levels: debug, info, warning, error\n');
        end
        
    case 'set_file'
        if ~isempty(log_file) && log_file ~= -1
            fclose(log_file);
        end
        log_file = fopen(varargin{1}, 'a');
        fprintf('Log file set to: %s\n', varargin{1});
        
    case 'debug'
        if log_level <= 1
            write_log('DEBUG', message, varargin);
        end
        
    case 'info'
        if log_level <= 2
            write_log('INFO', message, varargin);
        end
        
    case 'warning'
        if log_level <= 3
            write_log('WARNING', message, varargin);
        end
        
    case 'error'
        if log_level <= 4
            write_log('ERROR', message, varargin);
        end
        
    case 'cleanup'
        if ~isempty(log_file) && log_file ~= -1
            fclose(log_file);
            log_file = -1;
        end
        
    otherwise
        fprintf('Unknown log level: %s\n', level);
end
end

function write_log(level_str, message, args)
% Helper function to write log entries
persistent log_file

if isempty(log_file) || log_file == -1
    log_file = fopen('system.log', 'a');
end

timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF');
caller = get_caller_info();

% Format message with arguments if provided
if ~isempty(args)
    try
        formatted_message = sprintf(message, args{:});
    catch
        formatted_message = message;
    end
else
    formatted_message = message;
end

% Write to log file
log_entry = sprintf('[%s] %s [%s] %s\n', timestamp, level_str, caller, formatted_message);
fprintf(log_file, log_entry);

% Also display to console for warnings and errors
if strcmp(level_str, 'WARNING') || strcmp(level_str, 'ERROR')
    fprintf('%s', log_entry);
end
end

function caller = get_caller_info()
% Get information about the calling function
try
    stack = dbstack(2); % Skip logger and write_log functions
    if length(stack) >= 1
        caller = sprintf('%s:%d', stack(1).name, stack(1).line);
    else
        caller = 'unknown';
    end
catch
    caller = 'unknown';
end
end 