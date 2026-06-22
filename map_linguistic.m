function num = map_linguistic(value)
%MAP_LINGUISTIC Converts linguistic/categorical FIS input values to numeric codes for FIS evaluation.
%   Comprehensive mapping for all values found in FIS, rules, and code. Throws error for unknown values.
    if isnumeric(value)
        num = value;
        return;
    end
    % Normalize: remove dashes, underscores, spaces, and uppercase
    v = upper(strrep(strrep(strrep(strrep(string(value),'-',''), '_',''), ' ', ''),'.',''));
    switch v
        % SCA
        case {"AAL1"}
            num = 0;
        case {"AAL2"}
            num = 5;
        case {"AAL3"}
            num = 10;
        % Permission/PRM
        case {"R"}
            num = 0.1;
        case {"A"}
            num = 0.3;
        case {"D"}
            num = 0.5;
        case {"E"}
            num = 0.7;
        case {"P"}
            num = 0.9;
        % SPI, OAF, OAB, ISL, SAB, S, OVLP AC/PR/VC/VA/VI
        case {"LOW"}
            num = 0;
        case {"MEDIUM", "AVERAGE", "AVG", "MED"}
            num = 0.5;
        case {"HIGH"}
            num = 1;
        % OAF
        case {"FTF", "FTT"}
            num = 0;
        case {"RARELY"}
            num = 0.25;
        case {"OFTEN"}
            num = 0.75;
        case {"CONSTANTLY", "CONST"}
            num = 1;
        % S
        case {"NEGLIGIBLE"}
            num = 0;
        case {"MARGINAL"}
            num = 0.5;
        case {"CRITICAL"}
            num = 0.75;
        case {"CATASTROPHIC"}
            num = 1;
        % SAB
        case {"SABLOW"}
            num = 0.2;
        case {"SABMEDIUM"}
            num = 0.5;
        case {"SABHIGH"}
            num = 0.8;
        % NTA
        case {"CAN"}
            num = 0;
        case {"LAN"}
            num = 0.5;
        case {"PAN"}
            num = 1;
        case {"WAN"}
            num = 0.75;
        % NTS
        case {"OPEN"}
            num = 0;
        case {"CLOSE"}
            num = 0.5;
        case {"VPN"}
            num = 1;
        % OVLP AR
        case {"NONE", "NOTDEFINED"}
            num = 0;
        case {"PRESENT"}
            num = 1;
        % OVLP AV
        case {"NETWORK", "N", "ADJACENTNETWORK"}
            num = 0.12;
        case {"ADJACENT"}
            num = 0.37;
        case {"LOCAL", "L"}
            num = 0.62;
        case {"PHYSICAL"}
            num = 0.87;
        % OVLP EM
        case {"UNREPORTED", "U"}
            num = 0.12;
        case {"PROOFOFCONCEPT", "POC", "PROOFCONCEPT"}
            num = 0.37;
        case {"ATTACKED"}
            num = 0.62;
        case {"EMNOTDEFINED"}
            num = 0.87;
        % OVLP UI
        case {"UINOTDEFINED"}
            num = 0.12;
        case {"UINONE"}
            num = 0.37;
        case {"PASSIVE"}
            num = 0.62;
        case {"ACTIVE", "REQUIRED"}
            num = 0.87;
        % FIS output/other
        case {"ORDINARY"}
            num = 0;
        case {"DEVIATION"}
            num = 0.5;
        case {"ANOMALY"}
            num = 1;
        case {"SUB"}
            num = 0.5;
        case {"VHIGH"}
            num = 1;
        case {"X"}
            num = 0;
        otherwise
            error('Unknown linguistic value: %s', value);
    end
end 