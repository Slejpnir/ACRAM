function resetRiskTool()
%RESETRISKTOOL Request the running real-time risk monitor to reset.
%   From MATLAB:
%       resetRiskTool
%
%   From a shell/SSH session in this project directory:
%       matlab -batch "resetRiskTool"
%
%   The helper creates the same reset flag watched by real_time_monitor.

real_time_monitor('request_reset');
end
