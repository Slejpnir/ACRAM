function [Risks, intermediateNodesGlobal, testInputParametersGlobal, graphArray] = calculate_risks(subjects, objects, OVLP, NT, ACL, config, map_linguistic)
%CALCULATE_RISKS Calculates the risk matrix for all users/objects using FIS.
%   Returns Risks, intermediateNodesGlobal, testInputParametersGlobal, and graphArray.

nUsers = length(subjects);
nObjects = length(objects);
Risks = zeros(nUsers, nObjects);
intermediateNodesGlobal = cell(nUsers, nObjects);
testInputParametersGlobal = cell(nUsers, nObjects);
graphArray = cell(nUsers, nObjects);
LOIMethod = config.LOIMethod;
gui = config.gui;
SPMPNames = ["Reset account lockout counter after","Minimum password age","Account Lockout Duration","Maximum password age","Enforce password history","Account Lockout Threshold","Minimum password length","Password must meet complexity requirements","Store passwords using reversible encryption"];

for user = 1:nUsers
    for object = 1:nObjects
        if isstruct(ACL{user,object})
            SPMP = dictionary();
            SPMP("RAL") = subjects(user).RAL;
            SPMP("mPA") = subjects(user).mPA;
            SPMP("ALD") = subjects(user).ALD;
            SPMP("MPA") = subjects(user).MPA;
            SPMP("EPH") = subjects(user).EPH;
            SPMP("ALT") = subjects(user).ALT;
            SPMP("MPL") = subjects(user).MPL;
            SPMP("PCR") = subjects(user).PCR;
            SPMP("SPE") = subjects(user).SPE;
            testInputParameters = dictionary();
            testInputParameters("PML") = calcPML(SPMP);
            testInputParameters("SCA") = map_linguistic(ACL{user,object}.SCA);
            testInputParameters("PRM") = map_linguistic(ACL{user,object}.Permission);
            testInputParameters("SPI") = map_linguistic(NT.SPI);
            testInputParameters("NTA") = map_linguistic(NT.NTA);
            testInputParameters("NTS") = map_linguistic(NT.NTS);
            testInputParameters("OAF") = map_linguistic(objects(object).OAF);
            testInputParameters("OAB") = map_linguistic(objects(object).OAB);
            %testInputParameters("OAB")=0.9;
            testInputParameters("ISL") = map_linguistic(objects(object).ISL);
            if LOIMethod == "direct"
                testInputParameters("LOI") = objects(object).LOI;
            end
            testInputParameters("S") = map_linguistic(objects(object).S);
            % SAB: support either numeric [0,1] or legacy strings "Low|Medium|High"
            try
                sab_raw = subjects(user).SAB;
                if isnumeric(sab_raw)
                    testInputParameters("SAB") = max(0, min(1, sab_raw));
                else
                    sab_val = upper(string(sab_raw));
                    switch sab_val
                        case "LOW"
                            testInputParameters("SAB") = map_linguistic("SABLOW");
                        case "MEDIUM"
                            testInputParameters("SAB") = map_linguistic("SABMEDIUM");
                        case "HIGH"
                            testInputParameters("SAB") = map_linguistic("SABHIGH");
                        otherwise
                            testInputParameters("SAB") = 0;
                    end
                end
            catch
                testInputParameters("SAB") = 0;
            end
            nVulnerability = max(1, length(objects(object).OVLP));
            RiskLevel = zeros(nVulnerability, 1);
            intermediateNodes = cell(nVulnerability, 1);
            testInputParametersByVulnerability = cell(nVulnerability, 1);
            for vulnerability = 1:nVulnerability
                if ~isempty(objects(object).OVLP)
                    idx = objects(object).OVLP(vulnerability);
                    testInputParameters("AC") = map_linguistic(OVLP(idx).AC);
                    testInputParameters("AR") = map_linguistic(OVLP(idx).AR);
                    testInputParameters("PR") = map_linguistic(OVLP(idx).PR);
                    testInputParameters("AV") = map_linguistic(OVLP(idx).AV);
                    em_val = upper(string(OVLP(idx).EM));
                    if em_val == "NOT-DEFINED" || em_val == "NOTDEFINED"
                        testInputParameters("EM") = map_linguistic("EMNOTDEFINED");
                    elseif em_val == "PROOF-OF-CONCEPT" || em_val == "PROOFOFCONCEPT"
                        testInputParameters("EM") = map_linguistic("PROOFOFCONCEPT");
                    else
                        testInputParameters("EM") = map_linguistic(em_val);
                    end
                    testInputParameters("VC") = map_linguistic(OVLP(idx).VC);
                    testInputParameters("VA") = map_linguistic(OVLP(idx).VA);
                    testInputParameters("VI") = map_linguistic(OVLP(idx).VI);
                    ui_val = upper(string(OVLP(idx).UI));
                    if ui_val == "NOT DEFINED" || ui_val == "NOT-DEFINED" || ui_val == "NOTDEFINED"
                        testInputParameters("UI") = map_linguistic("UINOTDEFINED");
                    elseif ui_val == "NONE"
                        testInputParameters("UI") = map_linguistic("UINONE");
                    else
                        testInputParameters("UI") = map_linguistic(ui_val);
                    end
                else
                    testInputParameters("AC") = -1;
                    testInputParameters("AR") = -1;
                    testInputParameters("PR") = -1;
                    testInputParameters("AV") = -1;
                    testInputParameters("EM") = -1;
                    testInputParameters("VC") = -1;
                    testInputParameters("VA") = -1;
                    testInputParameters("VI") = -1;
                    testInputParameters("UI") = -1;
                end
                [RiskLevel(vulnerability), intermediateNodes{vulnerability}] = EvaluateRisk(testInputParameters, LOIMethod);
                testInputParametersByVulnerability{vulnerability} = testInputParameters;
            end
            [Risks(user, object), i] = max(RiskLevel);
            intermediateNodesGlobal{user, object} = intermediateNodes{i};
            winningTestInputParameters = testInputParametersByVulnerability{i};
            testInputParametersGlobal{user, object} = winningTestInputParameters;
            % Restore createGraph and graphArray logic
            %if gui == "on"
            graphArray{user, object} = createGraph(SPMP, SPMPNames, winningTestInputParameters, intermediateNodes{i}, RiskLevel(i), LOIMethod);
            %end
        end
    end
end
end 
