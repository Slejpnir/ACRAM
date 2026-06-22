%% Auto-fill monotonically increasing rules for a Mamdani FIS
% If your FIS is already in the workspace as `fis`, this will use it.
% Otherwise, load it from file:
if ~exist('OAB_input.fis','var')
    % <-- change the filename if needed
    fis = readfis('OAB_input.fis');
end

% Safety checks
assert(strcmpi(fis.Type,'mamdani'), 'This script expects a Mamdani FIS.');
assert(numel(fis.Outputs)==1, 'Script assumes exactly one output.');

% -------- Settings you may change ----------
% Input weights (importance of each input in the gradual increase).
% Default: equal weights. Example for 5 inputs:
w = ones(1,numel(fis.Inputs));  % e.g., [1 1 1 1 1]
w = w / sum(w);                 % normalized weights

logicConnective = 1;            % 1 = AND, 2 = OR for rule antecedents
ruleWeight      = 1;            % rule weight (0..1)
% ------------------------------------------

% Start from a clean rule base
fis.Rules = [];

% Count MFs for each input
nIn  = numel(fis.Inputs);
nMF  = zeros(1,nIn);
for i = 1:nIn
    nMF(i) = numel(fis.Inputs(i).MembershipFunctions);
end

% Build full antecedent grid (all MF index combinations)
idx = cell(1,nIn);
for i = 1:nIn
    idx{i} = 1:nMF(i);
end
[A{1:nIn}] = ndgrid(idx{:});
Ante = zeros(prod(nMF), nIn);
for i = 1:nIn
    Ante(:,i) = A{i}(:);
end

% Convert antecedent MF indices to a normalized 0..1 scale per input
% (Low=0, ..., High=1 even if an input has only 2 MFs)
normAnte = zeros(size(Ante));
for i = 1:nIn
    if nMF(i) == 1
        normAnte(:,i) = 0; % degenerate case
    else
        normAnte(:,i) = (Ante(:,i) - 1) / (nMF(i) - 1);
    end
end

% Weighted average score in [0,1] – ensures gradual/monotone mapping
gamma = 0.6;  % 0.3–0.9; smaller => more rapid increase (concave curve)

% Weighted score, then concave power to boost early growth
score  = (normAnte * w(:)).^gamma;   % was: score = normAnte * w(:);

% Quantize to output MFs (monotone)
nOutMF = numel(fis.Outputs(1).MembershipFunctions);
outIdx = floor(score * (nOutMF - 1)) + 1;
outIdx = min(max(outIdx,1), nOutMF);

% Assemble rule list: [in1 ... inN  out1  weight connective]
ruleList = [Ante, outIdx, ruleWeight*ones(size(outIdx)), logicConnective*ones(size(outIdx))];

% Add all rules at once
fis = addRule(fis, ruleList);

% (Optional) Save a copy
writeFIS(fis, 'mamdantitype1_auto_rules.fis');

% Quick peek
disp('First 10 rules:');
showrule(fis, 1:min(10,numel(fis.Rules)));

% You can now open in Designer or evaluate:
% fuzzyLogicDesigner(fis)
% y = evalfis(fis, [0.2 0.7 1.0 0.5 0.3]);  % example input row
