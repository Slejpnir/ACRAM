function riskGuiUpdate(newRisks, impacts, objects)
%RISKGUIUPDATE Push fresh risk values into the live "Risk levels" GUI.
%   riskGuiUpdate(newRisks) updates the cached Risks matrix used by the
%   listbox / 3-D bar chart, the per-user/per-object table and (if impacts
%   is provided) the "Aggregated risk:" label, then forces a redraw of the
%   chart for the currently selected listbox entry.
%
%   riskGuiUpdate(newRisks, impacts, objects) additionally recomputes and
%   updates the aggregated-risk label using the current aggregate formula.
%
%   The function is safe to call from any context (timer callbacks, WS
%   transaction handlers, the local real_time_monitor while-loop). If no
%   GUI is currently registered (e.g. running headless or after the user
%   closed the window), the call is a no-op.
%
%   Visible chart redraws are throttled to at most one per second so a
%   burst of incoming transactions does not thrash the GUI thread. The
%   underlying state cache (Risks matrix and table contents) is always
%   updated immediately; only the bar-chart redraw is throttled.
%
%   The currently selected listbox entry is preserved across redraws.

    persistent lastRedraw
    if isempty(lastRedraw), lastRedraw = -inf; end

    fig = [];
    try
        fig = getappdata(0, 'RiskGuiFigure');
    catch
    end
    if isempty(fig) || ~ishandle(fig) || ~isvalid(fig)
        return;
    end

    state = getappdata(fig, 'RiskPlotState');
    if isempty(state) || ~isstruct(state) || ~isfield(state, 'Risks')
        return;
    end
    if ~isnumeric(newRisks) || ~isequal(size(newRisks), size(state.Risks))
        return;
    end

    if isequal(state.Risks, newRisks)
        return; % no actual change - skip even the cheap updates
    end

    state.Risks = newRisks;
    setappdata(fig, 'RiskPlotState', state);

    % Update the table/list selector through the threshold filter.
    riskGuiApplyThreshold(fig);

    % Update the aggregated-risk label.
    if nargin >= 2 && ~isempty(impacts)
        try
            if nargin >= 3 && ~isempty(objects)
                aggRisk = aggregatedRisk(newRisks, impacts, objects, 0.7);
            else
                aggRisk = aggregatedRisk(newRisks, impacts);
            end
            lbl = getappdata(fig, 'RiskAggregateLabel');
            if ~isempty(lbl) && isvalid(lbl)
                set(lbl, 'String', char(append('Aggregated risk: ', string(aggRisk))));
            end
        catch
        end
    end

    % Throttle the bar-chart redraw to ~1 Hz.
    nowTime = now * 86400;
    if nowTime - lastRedraw < 1.0
        return;
    end
    lastRedraw = nowTime;

    try
        lb = getappdata(fig, 'RiskPlotListbox');
        if ~isempty(lb) && isvalid(lb)
            riskPlotSelectionChanged(lb, []);
        end
    catch ME
        fprintf('riskGuiUpdate redraw skipped: %s\n', ME.message);
    end
end
