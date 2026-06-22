function riskPlotSelectionChanged(lb, event)
%RISKPLOTSELECTIONCHANGED Redraw the risk plot for a listbox selection.

    fig = ancestor(lb, 'figure');
    try
        state = getappdata(fig, 'RiskPlotState');
        viewState = riskGuiApplyThreshold(fig);
        updatePlot(lb, event, state.Axes, viewState.Risks, viewState.UsersNames, ...
            viewState.ObjectsNames, viewState.RiskThreshold);
        setappdata(fig, 'RiskPlotLastValue', get(lb, 'Value'));
    catch ME
        fprintf('Risk GUI selection failed: %s\n', ME.message);
        for k = 1:numel(ME.stack)
            fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
        end
    end

    try
        uistack(lb, 'top');
    catch
    end
end
