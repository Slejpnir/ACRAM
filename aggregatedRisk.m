function [risk, details] = aggregatedRisk(risks, impacts, objects, alpha)
%AGGREGATEDRISK Computes whole-system aggregated access-control risk.
%   Backward-compatible mode:
%       risk = aggregatedRisk(risks, impacts)
%   uses the previous impact-weighted max-per-object aggregate.
%
%   Criticality + Max-aware mode:
%       risk = aggregatedRisk(risks, impacts, objects, alpha)
%   computes:
%       R = alpha * R_cwa + (1 - alpha) * max(R_i)
%   where R_cwa is a criticality-weighted aggregate over max per-object
%   risks and object weights are:
%       w_j = 1 + OVL_j + OAF_j + ISL_j + S_j

if nargin < 4 || isempty(alpha)
    alpha = 0.7;
end

maxRisks = max(risks, [], 1);
globalMaxRisk = max(maxRisks);

details = struct();
details.method = "impact_weighted";
details.alpha = [];
details.maxRisk = globalMaxRisk;
details.criticalityWeightedRisk = [];
details.impactWeightedRisk = [];
details.objectWeights = [];

impactWeights = impacts(:);
if isempty(impactWeights) || sum(impactWeights) == 0
    impactWeights = ones(numel(maxRisks), 1);
end
impactWeightedRisk = maxRisks * impactWeights / sum(impactWeights);
details.impactWeightedRisk = impactWeightedRisk;

if nargin < 3 || isempty(objects)
    risk = impactWeightedRisk;
    return;
end

objectWeights = criticalityWeights(objects);
if numel(objectWeights) ~= numel(maxRisks) || sum(objectWeights) == 0
    risk = impactWeightedRisk;
    return;
end

criticalityWeightedRisk = maxRisks * objectWeights(:) / sum(objectWeights);
risk = alpha * criticalityWeightedRisk + (1 - alpha) * globalMaxRisk;

details.method = "criticality_weighted_max_aware";
details.alpha = alpha;
details.criticalityWeightedRisk = criticalityWeightedRisk;
details.objectWeights = objectWeights(:)';
end

function weights = criticalityWeights(objects)
objects = normalizeObjects(objects);
weights = zeros(1, numel(objects));
for i = 1:numel(objects)
    weights(i) = 1 ...
        + fieldScore(objects(i), 'OVL') ...
        + fieldScore(objects(i), 'OAF') ...
        + fieldScore(objects(i), 'ISL') ...
        + fieldScore(objects(i), 'S');
end
end

function objects = normalizeObjects(objects)
if iscell(objects)
    objects = [objects{:}];
elseif istable(objects)
    objects = table2struct(objects);
end
end

function score = fieldScore(object, fieldName)
score = 0;
if ~isfield(object, fieldName) || isempty(object.(fieldName))
    return;
end
try
    score = map_linguistic(object.(fieldName));
catch
    if isnumeric(object.(fieldName))
        score = object.(fieldName);
    end
end
if isempty(score) || ~isfinite(double(score))
    score = 0;
end
score = double(score);
end

