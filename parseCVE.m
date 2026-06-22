function OVLP = parseCVE(CVEStruct,OVLPTemplate)
%PARSECVE Summary of this function goes here
%   Detailed explanation goes here
%"UI", "None","VC", "High","VA", "High","VI", "High","AR","None");
OVLP=OVLPTemplate;
OVLP.CVE=CVEStruct.vulnerabilities.cve.id;
OVLP.VALUE=CVEStruct.vulnerabilities.cve.metrics.cvssMetricV31(1).cvssData.baseScore;
if isfield(CVEStruct.vulnerabilities.cve.metrics.cvssMetricV31(1).cvssData,'exploitCodeMaturityType')
    OVLP.EM=CVEStruct.vulnerabilities.cve.metrics.cvssMetricV31(1).cvssData.exploitCodeMaturityType;
else
    OVLP.EM='NOT-DEFINED';
OVLP.AV=CVEStruct.vulnerabilities.cve.metrics.cvssMetricV31(1).cvssData.attackVector;
OVLP.AC=CVEStruct.vulnerabilities.cve.metrics.cvssMetricV31(1).cvssData.attackComplexity;
OVLP.PR=CVEStruct.vulnerabilities.cve.metrics.cvssMetricV31(1).cvssData.privilegesRequired;
OVLP.UI=CVEStruct.vulnerabilities.cve.metrics.cvssMetricV31(1).cvssData.userInteraction;
OVLP.VC=CVEStruct.vulnerabilities.cve.metrics.cvssMetricV31(1).cvssData.confidentialityImpact;
OVLP.VA=CVEStruct.vulnerabilities.cve.metrics.cvssMetricV31(1).cvssData.availabilityImpact;
OVLP.VI=CVEStruct.vulnerabilities.cve.metrics.cvssMetricV31(1).cvssData.integrityImpact;
OVLP.AR='NONE';
end

