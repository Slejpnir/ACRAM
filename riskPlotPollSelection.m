function riskPlotPollSelection(fig)
%RISKPLOTPOLLSELECTION Fallback redraw when listbox selection changed.

    try
        if isempty(fig) || ~isvalid(fig)
            return;
        end

        lb = getappdata(fig, 'RiskPlotListbox');
        if isempty(lb) || ~isvalid(lb)
            lb = findobj(fig, 'Style', 'listbox');
            if isempty(lb)
                return;
            end
            lb = lb(1);
            setappdata(fig, 'RiskPlotListbox', lb);
        end

        currentValue = get(lb, 'Value');
        lastValue = getappdata(fig, 'RiskPlotLastValue');
        if isempty(lastValue) || ~isequal(currentValue, lastValue)
            riskPlotSelectionChanged(lb, []);
        end
    catch ME
        fprintf('Risk GUI selection poll failed: %s\n', ME.message);
    end
end
