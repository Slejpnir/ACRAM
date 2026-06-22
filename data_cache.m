function varargout = data_cache(action, varargin)
%DATA_CACHE Caching system for expensive operations
%   Usage:
%     data_cache('store', 'key', data)
%     cached_data = data_cache('get', 'key')
%     data_cache('clear')
%     data_cache('list')

persistent cache_data cache_timestamps max_age

if isempty(max_age)
    max_age = 3600; % 1 hour default cache age
end

switch lower(action)
    case 'store'
        key = varargin{1};
        data = varargin{2};
        
        if isempty(cache_data)
            cache_data = containers.Map();
            cache_timestamps = containers.Map();
        end
        
        cache_data(key) = data;
        cache_timestamps(key) = now;
        
    case 'get'
        key = varargin{1};
        
        if isempty(cache_data) || ~isKey(cache_data, key)
            varargout{1} = [];
            return;
        end
        
        % Check if cache is still valid
        age_hours = (now - cache_timestamps(key)) * 24;
        if age_hours > max_age / 3600
            remove(cache_data, key);
            remove(cache_timestamps, key);
            varargout{1} = [];
            return;
        end
        
        varargout{1} = cache_data(key);
        
    case 'clear'
        cache_data = [];
        cache_timestamps = [];
        
    case 'list'
        if isempty(cache_data)
            fprintf('Cache is empty\n');
        else
            keys_list = keys(cache_data);
            fprintf('Cached items:\n');
            for i = 1:length(keys_list)
                key = keys_list{i};
                age_hours = (now - cache_timestamps(key)) * 24;
                fprintf('  %s (age: %.2f hours)\n', key, age_hours);
            end
        end
        
    case 'set_max_age'
        max_age = varargin{1};
        
    otherwise
        error('Unknown data cache action: %s', action);
end
end 