function outputRoot = mockAntonovUc3Scenario(outputRoot, exportAllGraphs)
%MOCKANTONOVUC3SCENARIO Generate the Antonov UC3 four-step mock scenario.

    if nargin < 1 || isempty(outputRoot)
        stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
        outputRoot = fullfile('mock_outputs', ['risk_progression_antonov_uc3_' stamp]);
    end
    if nargin < 2 || isempty(exportAllGraphs)
        exportAllGraphs = false;
    end

    outputRoot = mockRiskProgressionScenario( ...
        'config_antonov_2025.json', outputRoot, exportAllGraphs, 'antonov_uc3');
end
