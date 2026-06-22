function outputRoot = mockAntonovUc1Scenario(outputRoot, exportAllGraphs)
%MOCKANTONOVUC1SCENARIO Generate the Antonov UC1 three-step mock scenario.

    if nargin < 1 || isempty(outputRoot)
        stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
        outputRoot = fullfile('mock_outputs', ['risk_progression_antonov_uc1_' stamp]);
    end
    if nargin < 2 || isempty(exportAllGraphs)
        exportAllGraphs = false;
    end

    outputRoot = mockRiskProgressionScenario( ...
        'config_antonov_2025.json', outputRoot, exportAllGraphs, 'antonov_uc1');
end
