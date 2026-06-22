function RiskLevel = updateOAB(OAB, AR, AC, AS, AL)
%UPDATEOAB Recompute risk after an object anomaly behavior adjustment.

persistent OAB_AR OAB_AC OAB_AR_AC OAB_AR_AC_AL AL_AS

if isempty(OAB_AR)
    fisData = load('fiz_OAB_AR_new.mat', 'OAB_AR');
    OAB_AR = fisData.OAB_AR;
    fisData = load('fiz_OAB_AC_new.mat', 'OAB_AC');
    OAB_AC = fisData.OAB_AC;
    fisData = load('fiz_OAB_AR_AC_new.mat', 'OAB_AR_AC');
    OAB_AR_AC = fisData.OAB_AR_AC;
    fisData = load('fiz_OAB_AR_AC_AL_new.mat', 'OAB_AR_AC_AL');
    OAB_AR_AC_AL = fisData.OAB_AR_AC_AL;
    fisData = load('fiz_AL_AS_new.mat', 'AL_AS');
    AL_AS = fisData.AL_AS;
end

if isequal(AR, -1)
    AR = 0;
end
if isequal(AC, -1)
    AC = 0;
end

coef_OAB_AR = evalfis(OAB_AR, [OAB AR]);
coef_OAB_AC = evalfis(OAB_AC, [OAB AC]);
coef_OAB_AR_AC = evalfis(OAB_AR_AC, [coef_OAB_AR coef_OAB_AC]);
ALnew = evalfis(OAB_AR_AC_AL, [coef_OAB_AR_AC AL]);
RiskLevel = evalfis(AL_AS, [ALnew AS]);
end
