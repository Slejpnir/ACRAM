function stopRiskTool()
%STOPRISKTOOL Request the running real-time risk monitor to stop.
%   From MATLAB:
%       stopRiskTool
%
%   From a shell/SSH session in this project directory:
%       matlab -batch "stopRiskTool"
%
%   The helper creates the same stop flag watched by real_time_monitor.

real_time_monitor('request_stop');
end
