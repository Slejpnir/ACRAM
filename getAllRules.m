% Export fuzzy rules for the FIS nodes actively used by EvaluateRisk.m.
%
% The workspace contains old and new fuzzy node variants. To avoid duplicate
% rule blocks, this exporter reads the load(...) calls in EvaluateRisk.m and
% exports only the exact file/variable pairs used by that script.

outputFile = 'fis_rules.txt';
driverScript = 'EvaluateRisk.m';

activeNodes = getActiveFuzzyNodes(driverScript);
generatedAt = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));

fid = fopen(outputFile, 'w');
if fid == -1
    error('getAllRules:OpenFailed', 'Cannot open %s for writing.', outputFile);
end
cleanupObj = onCleanup(@() fclose(fid));

fprintf(fid, 'Fuzzy rules export\n');
fprintf(fid, 'Generated: %s\n', generatedAt);
fprintf(fid, 'Source script: %s\n', driverScript);
fprintf(fid, 'Scope: only FIS nodes explicitly loaded by the source script\n\n');

totalFis = 0;
totalRules = 0;

for nodeIndex = 1:numel(activeNodes)
    sourceName = activeNodes(nodeIndex).Source;
    variableName = activeNodes(nodeIndex).Variable;

    if ~isfile(sourceName)
        error('getAllRules:MissingSource', ...
            'Active fuzzy node file is missing: %s.', sourceName);
    end

    sourceData = load(sourceName, variableName);
    if ~isfield(sourceData, variableName)
        error('getAllRules:MissingVariable', ...
            'Variable %s was not found in %s.', variableName, sourceName);
    end

    fuzzyObject = sourceData.(variableName);
    [fisCount, ruleCount] = exportFuzzyObjectRules( ...
        fid, fuzzyObject, sourceName, variableName);

    totalFis = totalFis + fisCount;
    totalRules = totalRules + ruleCount;
end

fprintf(fid, '================================================================================\n');
fprintf(fid, 'Summary\n');
fprintf(fid, 'Source script: %s\n', driverScript);
fprintf(fid, 'Active fuzzy node sources: %d\n', numel(activeNodes));
fprintf(fid, 'FIS rule bases: %d\n', totalFis);
fprintf(fid, 'Rules exported: %d\n', totalRules);

clear cleanupObj
fprintf('Rules have been saved to %s (%d rules from %d active FIS nodes in %s).\n', ...
    outputFile, totalRules, totalFis, driverScript);

function activeNodes = getActiveFuzzyNodes(scriptName)
scriptText = fileread(scriptName);
tokens = regexp(scriptText, ...
    'load\s*\(\s*''([^'']*fiz[^'']*\.mat)''\s*,\s*''([^'']+)''\s*\)', ...
    'tokens');

if isempty(tokens)
    error('getAllRules:NoActiveNodes', ...
        'No fuzzy node load(...) calls were found in %s.', scriptName);
end

sourceNames = strings(numel(tokens), 1);
variableNames = strings(numel(tokens), 1);

for tokenIndex = 1:numel(tokens)
    sourceNames(tokenIndex) = string(tokens{tokenIndex}{1});
    variableNames(tokenIndex) = string(tokens{tokenIndex}{2});
end

[~, uniqueIndices] = unique(sourceNames + "|" + variableNames, 'stable');
sourceNames = sourceNames(uniqueIndices);
variableNames = variableNames(uniqueIndices);

activeNodes = struct( ...
    'Source', cellstr(sourceNames), ...
    'Variable', cellstr(variableNames));
end

function [fisCount, ruleCount] = exportFuzzyObjectRules(fid, fuzzyObject, sourceName, variableName)
fisCount = 0;
ruleCount = 0;

if isRuleBase(fuzzyObject)
    [fisCount, ruleCount] = exportSingleRuleBase( ...
        fid, fuzzyObject, sourceName, variableName, '');
    return
end

if isa(fuzzyObject, 'fistree')
    fprintf(fid, '================================================================================\n');
    fprintf(fid, 'Source: %s\n', sourceName);
    fprintf(fid, 'Variable: %s (%s)\n', variableName, class(fuzzyObject));
    fprintf(fid, 'Tree: %s\n', string(fuzzyObject.Name));

    treeFIS = fuzzyObject.FIS;
    if isempty(treeFIS)
        fprintf(fid, 'No contained FIS rule bases found.\n\n');
        return
    end

    for nodeIndex = 1:numel(treeFIS)
        if isRuleBase(treeFIS(nodeIndex))
            nodeLabel = sprintf('Tree node %d of %d', nodeIndex, numel(treeFIS));
            [nodeFisCount, nodeRuleCount] = exportSingleRuleBase( ...
                fid, treeFIS(nodeIndex), sourceName, variableName, nodeLabel);
            fisCount = fisCount + nodeFisCount;
            ruleCount = ruleCount + nodeRuleCount;
        end
    end
    return
end

error('getAllRules:UnsupportedFuzzyObject', ...
    'Unsupported fuzzy object %s in %s:%s.', ...
    class(fuzzyObject), sourceName, variableName);
end

function tf = isRuleBase(fuzzyObject)
tf = isa(fuzzyObject, 'mamfis') || isa(fuzzyObject, 'sugfis');
end

function [fisCount, ruleCount] = exportSingleRuleBase(fid, fisObject, sourceName, variableName, nodeLabel)
fisCount = 1;
ruleCount = numel(fisObject.Rules);

if nodeLabel == ""
    fprintf(fid, '================================================================================\n');
    fprintf(fid, 'Source: %s\n', sourceName);
    fprintf(fid, 'Variable: %s (%s)\n', variableName, class(fisObject));
else
    fprintf(fid, '\n%s\n', nodeLabel);
end

fprintf(fid, 'FIS: %s (%s)\n', string(fisObject.Name), class(fisObject));
fprintf(fid, 'Rules: %d\n', ruleCount);

if ruleCount == 0
    fprintf(fid, 'No rules found.\n\n');
    return
end

rules = showrule(fisObject);
writeRules(fid, rules);
fprintf(fid, '\n');
end

function writeRules(fid, rules)
if ischar(rules)
    for ruleIndex = 1:size(rules, 1)
        fprintf(fid, '%s\n', deblank(rules(ruleIndex, :)));
    end
elseif isstring(rules)
    for ruleIndex = 1:numel(rules)
        fprintf(fid, '%s\n', rules(ruleIndex));
    end
elseif iscellstr(rules)
    for ruleIndex = 1:numel(rules)
        fprintf(fid, '%s\n', rules{ruleIndex});
    end
else
    error('getAllRules:UnsupportedRuleFormat', ...
        'Unsupported showrule output type: %s.', class(rules));
end
end
