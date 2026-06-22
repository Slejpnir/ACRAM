function viewState = riskGuiApplyThreshold(fig)
%RISKGUIAPPLYTHRESHOLD Filter the risk GUI to users above the threshold.
%   Users remain visible when at least one object risk is above the current
%   threshold. Object-specific plots apply the same threshold to that object
%   again in updatePlot.m.

    viewState = emptyViewState();
    try
        if isempty(fig) || ~isvalid(fig)
            return;
        end

        state = getappdata(fig, 'RiskPlotState');
        if isempty(state) || ~isstruct(state) || ~isfield(state, 'Risks')
            return;
        end

        threshold = 0;
        filterDisabled = false;
        if isfield(state, 'RiskThreshold') && ~isempty(state.RiskThreshold)
            [threshold, filterDisabled] = normalizeRiskThreshold(state.RiskThreshold);
        end

        risks = state.Risks;
        usersNames = string(state.UsersNames(:));
        objectsNames = string(state.ObjectsNames(:));
        fallbackApplied = false;
        fallbackReason = "";
        if isempty(risks)
            visibleUserIndexes = zeros(0, 1);
        elseif filterDisabled
            visibleUserIndexes = (1:size(risks, 1))';
        else
            maxUserRisks = max(risks, [], 2);
            visibleUserIndexes = find(maxUserRisks > threshold);
            if isempty(visibleUserIndexes) && ~isempty(maxUserRisks)
                preferredUserIdx = preferredVisibleUserIndex(state, size(risks, 1));
                if ~isempty(preferredUserIdx)
                    visibleUserIndexes = preferredUserIdx;
                    fallbackReason = "preferred";
                else
                    [~, topUserIdx] = max(maxUserRisks);
                    visibleUserIndexes = topUserIdx;
                    fallbackReason = "top";
                end
                fallbackApplied = true;
            end
        end

        state.RiskThreshold = threshold;
        state.VisibleUserIndexes = visibleUserIndexes(:);
        state.RiskFilterDisabled = filterDisabled;
        state.RiskThresholdFallbackApplied = fallbackApplied;
        state.RiskThresholdFallbackReason = fallbackReason;
        setappdata(fig, 'RiskPlotState', state);

        viewState = struct( ...
            'Risks', risks(visibleUserIndexes, :), ...
            'UsersNames', usersNames(visibleUserIndexes), ...
            'ObjectsNames', objectsNames, ...
            'RiskThreshold', threshold, ...
            'RiskFilterDisabled', filterDisabled, ...
            'VisibleUserIndexes', visibleUserIndexes(:), ...
            'FallbackApplied', fallbackApplied, ...
            'FallbackReason', fallbackReason);

        syncThresholdControls(fig, threshold, filterDisabled, numel(visibleUserIndexes), ...
            size(risks, 1), fallbackApplied, fallbackReason);
        syncListbox(fig, viewState);
        syncRiskTable(fig, viewState);
    catch ME
        fprintf('Risk threshold filter skipped: %s\n', ME.message);
    end
end

function viewState = emptyViewState()
    viewState = struct( ...
        'Risks', [], ...
        'UsersNames', strings(0, 1), ...
        'ObjectsNames', strings(0, 1), ...
        'RiskThreshold', 0, ...
        'RiskFilterDisabled', false, ...
        'VisibleUserIndexes', zeros(0, 1), ...
        'FallbackApplied', false, ...
        'FallbackReason', "");
end

function idx = preferredVisibleUserIndex(state, nUsers)
    idx = [];
    try
        if isfield(state, 'PreferredVisibleUserIdx') && ~isempty(state.PreferredVisibleUserIdx)
            candidate = double(state.PreferredVisibleUserIdx);
            if isfinite(candidate) && candidate >= 1 && candidate <= nUsers
                idx = round(candidate);
            end
        end
    catch
        idx = [];
    end
end

function [threshold, filterDisabled] = normalizeRiskThreshold(threshold)
    filterDisabled = isnumeric(threshold) && isscalar(threshold) && isnan(threshold);
    if filterDisabled
        return;
    end
    threshold = max(0, min(1, double(threshold)));
end

function syncThresholdControls(fig, threshold, filterDisabled, visibleCount, totalCount, fallbackApplied, fallbackReason)
    try
        editBox = getappdata(fig, 'RiskThresholdEdit');
        if ~isempty(editBox) && isvalid(editBox)
            if filterDisabled
                set(editBox, 'String', 'off');
            else
                set(editBox, 'String', sprintf('%.2f', threshold));
            end
        end
    catch
    end
    try
        slider = getappdata(fig, 'RiskThresholdSlider');
        if ~isempty(slider) && isvalid(slider)
            if filterDisabled
                set(slider, 'Value', 0);
            else
                set(slider, 'Value', threshold);
            end
        end
    catch
    end
    try
        countLabel = getappdata(fig, 'RiskThresholdCount');
        if ~isempty(countLabel) && isvalid(countLabel)
            if filterDisabled
                countText = sprintf('%d/%d users (filter off)', visibleCount, totalCount);
            elseif fallbackApplied
                if string(fallbackReason) == "preferred"
                    countText = sprintf('%d/%d users (preferred)', visibleCount, totalCount);
                else
                    countText = sprintf('%d/%d users (top)', visibleCount, totalCount);
                end
            else
                countText = sprintf('%d/%d users', visibleCount, totalCount);
            end
            set(countLabel, 'String', countText);
        end
    catch
    end
end

function syncListbox(fig, viewState)
    try
        lb = getappdata(fig, 'RiskPlotListbox');
        if isempty(lb) || ~isvalid(lb)
            return;
        end

        oldItems = string(get(lb, 'String'));
        oldValue = get(lb, 'Value');
        selectedText = "All";
        if ~isempty(oldItems) && ~isempty(oldValue)
            oldValue = max(1, min(numel(oldItems), oldValue(1)));
            selectedText = oldItems(oldValue);
        end

        items = cellstr(["All"; viewState.UsersNames(:); viewState.ObjectsNames(:)]);
        set(lb, 'String', items);

        newItems = string(items);
        newValue = find(newItems == selectedText, 1);
        if isempty(newValue)
            newValue = 1;
        end
        set(lb, 'Value', newValue);
        setappdata(fig, 'RiskPlotLastValue', newValue);
    catch ME
        fprintf('Risk list threshold sync skipped: %s\n', ME.message);
    end
end

function syncRiskTable(fig, viewState)
    try
        t = getappdata(fig, 'RiskTable');
        if isempty(t) || ~isvalid(t)
            return;
        end
        t.Data = viewState.Risks;
        t.ColumnName = cellstr(viewState.ObjectsNames);
        t.RowName = cellstr(viewState.UsersNames);
        userData = struct();
        userData.VisibleUserIndexes = viewState.VisibleUserIndexes;
        userData.RiskThreshold = viewState.RiskThreshold;
        userData.RiskFilterDisabled = viewState.RiskFilterDisabled;
        userData.RiskThresholdFallbackApplied = viewState.FallbackApplied;
        userData.RiskThresholdFallbackReason = viewState.FallbackReason;
        t.UserData = userData;
    catch ME
        fprintf('Risk table threshold sync skipped: %s\n', ME.message);
    end
end
