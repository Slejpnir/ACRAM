function riskTableCellSelected(src, event, graphArray, usersNames, objectsNames)
%RISKTABLECELLSELECTED Open the risk-factor graph for a filtered table cell.

    try
        if isempty(event.Indices) || size(event.Indices, 2) < 2
            return;
        end

        tableRow = event.Indices(1);
        objectIdx = event.Indices(2);
        userIdx = tableRow;

        try
            userData = src.UserData;
            if isstruct(userData) && isfield(userData, 'VisibleUserIndexes') ...
                    && numel(userData.VisibleUserIndexes) >= tableRow
                userIdx = userData.VisibleUserIndexes(tableRow);
            end
        catch
        end

        if userIdx < 1 || userIdx > size(graphArray, 1) || ...
                objectIdx < 1 || objectIdx > size(graphArray, 2)
            return;
        end

        cellSelectedCallback(src, event, graphArray{userIdx, objectIdx}, ...
            usersNames, objectsNames, userIdx, objectIdx);
    catch ME
        fprintf('Risk table cell selection skipped: %s\n', ME.message);
    end
end
