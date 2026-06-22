function riskResetMonitoring(src, ~)
%RISKRESETMONITORING Reset the active real-time monitor from the risk GUI.

    try
        setRiskResetButtonState(src, 'Resetting...');
        real_time_monitor('reset');
        fprintf('Real-time monitoring reset from GUI.\n');
        setRiskResetButtonState(src, 'Reset');
    catch ME
        fprintf('Failed to reset real-time monitoring from GUI: %s\n', ME.message);
        setRiskResetButtonState(src, 'Reset failed');
    end
end

function setRiskResetButtonState(button, label)
    try
        if isempty(button) || ~isvalid(button)
            return;
        end
        set(button, 'String', char(label));
        drawnow limitrate
    catch
    end
end
