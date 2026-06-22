function riskThresholdChanged(src, ~)
%RISKTHRESHOLDCHANGED Update the GUI user-risk visibility threshold.

    fig = ancestor(src, 'figure');
    if isempty(fig) || ~isvalid(fig)
        return;
    end

    threshold = readThresholdValue(src);
    try
        state = getappdata(fig, 'RiskPlotState');
        if isstruct(state)
            state.RiskThreshold = threshold;
            setappdata(fig, 'RiskPlotState', state);
        end
    catch
    end

    riskGuiApplyThreshold(fig);

    try
        lb = getappdata(fig, 'RiskPlotListbox');
        if ~isempty(lb) && isvalid(lb)
            riskPlotSelectionChanged(lb, []);
        end
    catch ME
        fprintf('Risk threshold redraw skipped: %s\n', ME.message);
    end
end

function threshold = readThresholdValue(src)
    try
        style = lower(string(get(src, 'Style')));
        if style == "slider"
            threshold = get(src, 'Value');
        else
            textValue = lower(strtrim(string(get(src, 'String'))));
            if any(textValue == ["off", "none", "all"])
                threshold = NaN;
                return;
            end
            threshold = str2double(textValue);
        end
    catch
        threshold = 0;
    end
    if isnan(threshold)
        return;
    end
    if ~isfinite(threshold)
        threshold = 0;
    end
    threshold = max(0, min(1, threshold));
end
