function [csvFileName, assertsList, aggregatedRiskAssertID] = export_results(Risks, subjects, objects, impacts, env_new, realTimeMode, sendToDataSpace, sendToDashboard, graphArray, varargin)
% Optional config file path
configFileName = [];
if ~isempty(varargin)
    configFileName = varargin{1};
end
%EXPORT_RESULTS Handles all result export logic: CSV, dashboard, etc.

nUsers = length(subjects);
nObjects = length(objects);
userColumn = (1:nUsers)';
objectsNames = strings(1, nObjects);
for i = 1:nObjects
    objectsNames(i) = objects(i).Name;
end
usersNames = "User " + string(userColumn);

% Create table and write to CSV
csvFileName = 'risks.csv';
tablerisks = array2table([userColumn, Risks], "VariableNames", ["Users", objectsNames]);
tablerisks{:, 2:end} = round(tablerisks{:, 2:end}, 3);
writetable(tablerisks, csvFileName);

% Dashboard/JSON export
assertsList = {};
aggregatedRiskAssertID = [];
aggRisk = aggregatedRisk(Risks, impacts, objects, 0.7);
if contains(env_new, "nokia") || contains(env_new, "telco") || contains(env_new, "antonov")
    if realTimeMode == "aggregator" || realTimeMode == "ADI" || contains(env_new, "antonov")
        for object = 1:nObjects
            % Pass per-user graphs for this object if provided
            graphsForObject = {};
            try
                if nargin >= 9 && ~isempty(graphArray)
                    graphsForObject = graphArray(:, object);
                end
            catch
            end
            if ~isempty(configFileName)
                assertsList{object} = resultJSON(tablerisks{:, object+1}, tablerisks.Properties.VariableNames{object+1}, usersNames, 1, sendToDataSpace, [], [], [], graphsForObject, configFileName);
            else
                assertsList{object} = resultJSON(tablerisks{:, object+1}, tablerisks.Properties.VariableNames{object+1}, usersNames, 1, sendToDataSpace, [], [], [], graphsForObject);
            end
            processGuiEvents();
        end
        if ~isempty(configFileName)
            aggregatedRiskAssertID = aggregatedIndicator(aggRisk, tablerisks, sendToDataSpace, assertsList, 1, configFileName);
        else
        aggregatedRiskAssertID = aggregatedIndicator(aggRisk, tablerisks, sendToDataSpace, assertsList, 1);
        end
    end
end
if contains(env_new, "telco")
    for object = 1:nObjects
        resultJSON_dashboard(tablerisks{:, object+1}, tablerisks.Properties.VariableNames{object+1}, usersNames, 1, sendToDashboard);
        processGuiEvents();
    end
end
end 
