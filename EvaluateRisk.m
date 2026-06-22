function [RiskLevel, intermediateNodes] = EvaluateRisk(InputParameters,LOIMethod)
% Cache and safely load only required variables to avoid path conflicts
persistent AML_AC AML_AR NT_AV PRM_PR fis_AML OAF_VA ISL_VC AL_AS UI_SAB SAB_UI_AL OAB_AR OAB_AC OAB_AR_AC OAB_AR_AC_AL
if isempty(AML_AC);       S=load('fiz_AML_AC_new.mat','AML_AC');             AML_AC=S.AML_AC;               end
if isempty(AML_AR);       S=load('fiz_AML_AR_new.mat','AML_AR');             AML_AR=S.AML_AR;               end
if isempty(NT_AV);        S=load('fiz_NT_AV_new.mat','NT_AV');               NT_AV=S.NT_AV;                 end
if isempty(PRM_PR);       S=load('fiz_PRM_PR_new.mat','PRM_PR');             PRM_PR=S.PRM_PR;               end
if isempty(fis_AML);      S=load('fiz_AML_new.mat','fis_AML');               fis_AML=S.fis_AML;             end
if isempty(OAF_VA);       S=load('fiz_OAF_VA_new.mat','OAF_VA');             OAF_VA=S.OAF_VA;               end
if isempty(ISL_VC);       S=load('fiz_ISL_VC_new.mat','ISL_VC');             ISL_VC=S.ISL_VC;               end
if isempty(AL_AS);        S=load('fiz_AL_AS_new.mat','AL_AS');               AL_AS=S.AL_AS;                 end
if isempty(UI_SAB);       S=load('fiz_UI_SAB_new.mat','UI_SAB');             UI_SAB=S.UI_SAB;               end
if isempty(SAB_UI_AL);    S=load('fiz_SAB_UI_AL_new.mat','SAB_UI_AL');       SAB_UI_AL=S.SAB_UI_AL;         end
% if needed later: AR_AC_OAB (kept disabled)
if isempty(OAB_AR);       S=load('fiz_OAB_AR_new.mat','OAB_AR');             OAB_AR=S.OAB_AR;               end
if isempty(OAB_AC);       S=load('fiz_OAB_AC_new.mat','OAB_AC');             OAB_AC=S.OAB_AC;               end
if isempty(OAB_AR_AC);    S=load('fiz_OAB_AR_AC_new.mat','OAB_AR_AC');       OAB_AR_AC=S.OAB_AR_AC;         end
if isempty(OAB_AR_AC_AL); S=load('fiz_OAB_AR_AC_AL_new.mat','OAB_AR_AC_AL'); OAB_AR_AC_AL=S.OAB_AR_AC_AL;   end

%EVALUATERISK Summary of this function goes here
%   Detailed explanation goes here
PML=InputParameters("PML");
SCA=InputParameters("SCA");
AC=InputParameters("AC");
AR=InputParameters("AR");
PRM=InputParameters("PRM");
PR=InputParameters("PR");
SPI=InputParameters("SPI");
NTA=InputParameters("NTA");
NTS=InputParameters("NTS");
AV=InputParameters("AV");
EM=InputParameters("EM");
VC=InputParameters("VC");
VA=InputParameters("VA");
VI=InputParameters("VI");
OAF=InputParameters("OAF");
ISL=InputParameters("ISL");
S=InputParameters("S");
SAB=InputParameters("SAB");
UI=InputParameters("UI");
OAB=InputParameters("OAB");
   
[AML,~,~,~,~]=evalfis(fis_AML,[PML SCA]);

if isequal(AC, -1)
    coefAML_AC = 0;
else
    coefAML_AC = evalfis(AML_AC, [AML AC]);
end

if isequal(AR, -1)
    coefAML_AR = 0;
else
    coefAML_AR = evalfis(AML_AR, [AML AR]);
end

if isequal(PR, -1)
    coefPRM_PR = evalfis(PRM_PR, [PRM 0 SPI]);
else
    coefPRM_PR = evalfis(PRM_PR, [PRM PR SPI]);
end

if isequal(AV, -1)
    coefNT_AV = 0;
else
    coefNT_AV = evalfis(NT_AV, [NTA NTS SPI AV]);
end

if isequal(EM, -1)
    AL = min([coefAML_AC, coefAML_AR, coefPRM_PR, coefNT_AV]);
else
    AL = EM * mean([coefAML_AC, coefAML_AR, coefPRM_PR, coefNT_AV]);
end

if isequal(UI, -1)
    coefSAB_UI = SAB*0.5;
else
    coefSAB_UI = evalfis(UI_SAB, [SAB UI]);
end

AL = evalfis(SAB_UI_AL, [coefSAB_UI AL]);
ALbeforeOAB = AL;

if isequal(AR, -1)
    coef_OAB_AR = OAB*0.5;
else
    coef_OAB_AR = evalfis(OAB_AR, [OAB AR]);
end

if isequal(AC, -1)
    coef_OAB_AC = OAB*0.5;
else
    coef_OAB_AC = evalfis(OAB_AC, [OAB AC]);
end

coef_OAB_AR_AC = evalfis(OAB_AR_AC, [coef_OAB_AR coef_OAB_AC]);


AL = evalfis(OAB_AR_AC_AL, [coef_OAB_AR_AC AL]);

if isequal(VA, -1)
    coefOAF_VA = OAF*0.5;
else
    coefOAF_VA = evalfis(OAF_VA, [OAF VA]);
end

if isequal(VC, -1)
    coefISL_VC = ISL*0.5;
else
    coefISL_VC = evalfis(ISL_VC, [ISL VC]);
end

if isequal(VI, -1)
    AS = mean([coefOAF_VA, coefISL_VC, 0]);
else
    AS = mean([coefOAF_VA, coefISL_VC, VI]);
end

if LOIMethod=="direct"
    LOI=InputParameters("LOI"); 
    AS=AS*(1+LOI);
end
AS=AS*(1+S);
AS=min(AS,1);
RiskLevel=evalfis(AL_AS,[AL AS]);
keys=["AML" "coefAML_AC" "coefAML_AR" "coefPRM_PR" "coefNT_AV" "coefSAB_UI" "coefOAB_AR" "coefOAB_AC" "coefOAB_AR_AC" "AL" "coefOAF_VA" "coefISL_VC" "AS" "ALbeforeOAB"];
values=[AML coefAML_AC coefAML_AR coefPRM_PR coefNT_AV coefSAB_UI coef_OAB_AR coef_OAB_AC coef_OAB_AR_AC AL coefOAF_VA coefISL_VC AS ALbeforeOAB];
intermediateNodes=dictionary(keys,values);
end

