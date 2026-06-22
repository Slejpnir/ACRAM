function token = generate_token(id, private_key, serviceName)
    % Generate JWT token for authentication
    % 
    % Inputs:
    %   id - User/entity identifier
    %   private_key - Private key for signing the token
    %   serviceName - Python package name ('smartqc' or 'contextchain')
    %
    % Outputs:
    %   token - Generated JWT token string
    
    if nargin < 3 || isempty(serviceName)
        serviceName = 'smartqc';
    end
    serviceName = scalarTextToChar(serviceName, 'serviceName');
    id = scalarTextToChar(id, 'id');
    private_key = scalarTextToChar(private_key, 'private_key');
    
    try
        % Import Python JWT module from selected service
        jwtMod = py.importlib.import_module([serviceName '.jwt']);
        
        % Generate token using the JWT module
        token = jwtMod.JWT.token(id, private_key);
        
        % Convert Python string to MATLAB char if needed
        %if isa(token, 'py.str')
        %    token = char(token);
        %end
        
    catch ME
        fprintf('Error generating JWT token: %s\n', ME.message);
        rethrow(ME);
    end
end 

function value = scalarTextToChar(value, valueName)
    if isstring(value)
        if ~isscalar(value)
            error('generate_token:NonScalarText', '%s must be scalar text.', valueName);
        end
        value = char(value);
    elseif ischar(value)
        % Already Python-compatible text.
    else
        try
            value = char(string(value));
        catch ME
            error('generate_token:InvalidText', ...
                'Unable to convert %s to text: %s', valueName, ME.message);
        end
    end
end
