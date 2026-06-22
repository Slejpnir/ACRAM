function performance_monitor(action, varargin)
%PERFORMANCE_MONITOR Track execution times and resource usage
%   Usage:
%     performance_monitor('start', 'operation_name')
%     performance_monitor('end', 'operation_name')
%     performance_monitor('report')

persistent timers memory_usage

% Global enable/disable switch (default: enabled)
try
    enabled = true;
    if evalin('base', 'exist(''performanceMonitorEnabled'',''var'')')
        enabled = evalin('base', 'performanceMonitorEnabled');
        if ischar(enabled) || isstring(enabled)
            enabled = ~(string(enabled) == "off");
        end
    end
catch
    enabled = true;
end
if ~enabled
    % Keep ability to clear internal state when disabled
    if strcmpi(action, 'clear')
        timers = [];
        memory_usage = [];
    end
    return;
end

switch lower(action)
    case 'start'
        operation_name = varargin{1};
        if isempty(timers)
            timers = containers.Map();
            memory_usage = containers.Map();
        end
        
        timers(operation_name) = tic;
        try
            if ispc
                memory_usage(operation_name) = memory;
            else
                % On non-Windows platforms, skip memory usage calculation
                memory_usage(operation_name) = [];
            end
        catch
            memory_usage(operation_name) = [];
        end
        
    case 'end'
        operation_name = varargin{1};
        if isKey(timers, operation_name)
            elapsed_time = toc(timers(operation_name));
            memMsg = '';
            try
                if ispc && ~isempty(memory_usage(operation_name))
                    current_memory = memory;
                    initial_memory = memory_usage(operation_name);
                    memory_diff = current_memory.MemUsedMATLAB - initial_memory.MemUsedMATLAB;
                    memMsg = sprintf(', memory change: %.2f MB', memory_diff / 1024 / 1024);
                end
            catch
            end
            fprintf('Performance: %s took %.3f seconds%s\n', operation_name, elapsed_time, memMsg);
            
            remove(timers, operation_name);
            remove(memory_usage, operation_name);
        end
        
    case 'report'
        if ~isempty(timers)
            fprintf('Active operations: %s\n', strjoin(keys(timers), ', '));
        else
            fprintf('No active operations\n');
        end
        
    case 'clear'
        timers = [];
        memory_usage = [];
        
    otherwise
        error('Unknown performance monitor action: %s', action);
end
end 