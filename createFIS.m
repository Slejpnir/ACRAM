function fis = createFIS(fisName,inputRanges,inputNames,outputName)
% Construct a fuzzy inference system (FIS).

fis = sugfis(Name=fisName);
numInputMFs = 3;
numInputs = size(inputRanges,2);
for inputId = 1:numInputs
    fis = addInput(fis,inputRanges(:,inputId)', ...
        Name=inputNames{inputId},NumMFs=numInputMFs);
    fis.Inputs(inputId).MembershipFunctions(1).Name = "low";
    fis.Inputs(inputId).MembershipFunctions(1).Type = "linzmf";
    fis.Inputs(inputId).MembershipFunctions(2).Name = "medium";
    fis.Inputs(inputId).MembershipFunctions(2).Type = "linsmf";
    fis.Inputs(inputId).MembershipFunctions(3).Name = "high";
    fis.Inputs(inputId).MembershipFunctions(3).Type = "linsmf";
end
%numOutputMFs = numInputs*numInputMFs-(numInputs-1);
numOutputMFs=5;
fis = addOutput(fis,[0 1], ...
    Name=outputName,NumMFs=numOutputMFs);
mfIds = 1:numInputMFs;
if numOutputMFs==5
    fis.Outputs(1).MembershipFunctions(1).Name = "veryLow";
    fis.Outputs(1).MembershipFunctions(2).Name = "low";
    fis.Outputs(1).MembershipFunctions(3).Name = "medium";
    fis.Outputs(1).MembershipFunctions(4).Name = "high";
    fis.Outputs(1).MembershipFunctions(5).Name = "veryHigh";
    [in1,in2,in3,in4] = ndgrid(mfIds,mfIds,mfIds,mfIds);
    antecedents = [in1(:) in2(:) in3(:) in4(:)];
elseif numOutputMFs==4
    fis.Outputs(1).MembershipFunctions(1).Name = "veryLow";
    fis.Outputs(1).MembershipFunctions(2).Name = "low";
    fis.Outputs(1).MembershipFunctions(3).Name = "high";
    fis.Outputs(1).MembershipFunctions(4).Name = "veryHigh";
    [in1,in2,in3] = ndgrid(mfIds,mfIds,mfIds);
    antecedents = [in1(:) in2(:) in3(:)];
end
numRules = size(antecedents,1);
consequents = ones(numRules,1);
weights = ones(numRules,1);
connections = ones(numRules,1);

k = numInputs*numInputMFs-numOutputMFs;
for ruleId = 1:numRules
    consequents(ruleId) = max(1,sum(antecedents(ruleId,:))-k);
end
%rules = [antecedents consequents connections weights];
%fis = addRule(fis,rules);
end