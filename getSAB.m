function SAB = getSAB(fileName,nUsers)
%GETSAB Load/compute per-user SAB values.
% Returns numeric SAB in [0,1] where:
%   High   -> 1
%   Medium -> 0.5
%   Low    -> 0
%
% If the SAB file is missing, unreadable, or does not contain enough user
% columns, missing users are assigned 0.

SAB = zeros(nUsers,1); % default 0 for all users

try
    if exist(fileName, 'file') ~= 2
        return;
    end
    csvData = readtable(fileName);
catch
    return;
end

for i = 1:nUsers
    try
        colName = append('Sum_of_Sub', string(i));
        if ~ismember(colName, string(csvData.Properties.VariableNames))
            % Missing column => keep default 0
            continue;
        end
        quan = csvData.(colName);
        s = sum(quan);
        if s >= 4
            SAB(i) = 1;
        elseif s >= 2
            SAB(i) = 0.5;
        else
            SAB(i) = 0;
        end
    catch
        % Any parsing issue for this user => keep default 0
        SAB(i) = 0;
    end
end
end

