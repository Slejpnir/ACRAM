function riskStopMonitoring(src, ~)
%RISKSTOPMONITORING Stop the active real-time monitor from the risk GUI.

    fig = [];
    try
        fig = ancestor(src, 'figure');
    catch
    end

    try
        real_time_monitor('stop');
        fprintf('Real-time monitoring stopped from GUI.\n');
        setRiskStopButtonState(src, true, '');
        if ~isempty(fig) && isvalid(fig)
            setappdata(fig, 'RiskRealtimeStopped', true);
        end
    catch ME
        fprintf('Failed to stop real-time monitoring from GUI: %s\n', ME.message);
        setRiskStopButtonState(src, false, ME.message);
    end
end

function setRiskStopButtonState(button, stopped, message)
    try
        if isempty(button) || ~isvalid(button)
            return;
        end
        if stopped
            set(button, 'String', 'Stopped', 'Enable', 'off', ...
                'TooltipString', 'Real-time monitoring has been stopped');
        else
            set(button, 'String', 'Stop failed', 'Enable', 'on', ...
                'TooltipString', char("Stop failed: " + string(message)));
        end
    catch
    end
end
