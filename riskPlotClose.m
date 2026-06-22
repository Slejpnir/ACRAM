function riskPlotClose(fig, ~)
%RISKPLOTCLOSE Stop GUI polling timer before closing the risk figure.

    try
        pollTimer = getappdata(fig, 'RiskPlotTimer');
        if ~isempty(pollTimer) && isvalid(pollTimer)
            stop(pollTimer);
            delete(pollTimer);
        end
    catch
    end

    % Drop the global GUI registration so subsequent riskGuiUpdate(...)
    % calls (from real_time_monitor / WS callbacks) skip cleanly instead
    % of trying to draw on a deleted figure.
    try
        regFig = getappdata(0, 'RiskGuiFigure');
        if isequal(regFig, fig)
            try
                rmappdata(0, 'RiskGuiFigure');
            catch
            end
        end
    catch
    end

    try
        delete(fig);
    catch
    end
end
