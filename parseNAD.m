function riskLevel = parseNAD(json)
%UNTITLED4 Summary of this function goes here
%   Detailed explanation goes here
    msgCount = jsondecode(msgCountJson);
    
    % Extract individual message counts
    n_red    = msgCount.RED;
    n_orange = msgCount.ORANGE;
    n_yellow = msgCount.YELLOW;
    n_off    = msgCount.OFF;
    
    % Calculate the total number of messages
    total = n_red + n_orange + n_yellow + n_off;
    
    % If total is zero, return 0 to avoid division by zero
    if total == 0
        riskLevel = 0;
        return;
    end
    
    % Define weights for each severity level
    w_red    = 1.0;
    w_orange = 0.7;
    w_yellow = 0.3;
    w_off    = 0.0;
    
    % Compute the weighted risk score and normalize it between 0 and 1
    riskLevel = (w_red * n_red + w_orange * n_orange + w_yellow * n_yellow + w_off * n_off) / total;
end