function outputRoot = mockTelcoUc3Scenario(outputRoot, exportAllGraphs)
%MOCKTELCOUC3SCENARIO Generate the Telco UC3 four-step mock scenario.

    if nargin < 1 || isempty(outputRoot)
        stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
        outputRoot = fullfile('mock_outputs', ['risk_progression_telco_uc3_' stamp]);
    end
    if nargin < 2 || isempty(exportAllGraphs)
        exportAllGraphs = false;
    end

    outputRoot = mockRiskProgressionScenario( ...
        'config_Telco3PC.json', outputRoot, exportAllGraphs, 'telco_uc3');
end
