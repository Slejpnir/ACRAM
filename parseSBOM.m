
function [objects,OVLP] = parseSBOM(filePath,OVLPTemplate,objects,objectNo)
%PARSESBOM Summary of this function goes here
%   Detailed explanation goes here
data = readtable(filePath, 'PreserveVariableNames', true);
k=1;
OVLP=repmat(OVLPTemplate, height(data), 1);
for i = 1:height(data)
    if ~ismissing(data.cvss_vector{i})
        if contains(data.cve_number{i}, 'CVE')
        % Split the vector string by '/'
            objects(objectNo).OVLP=[objects(objectNo).OVLP];
            OVLP(k,1).CVE=data.cve_number{i};
            OVLP(k,1).VALUE=data.score(i);
            components = strsplit(data.cvss_vector{i}, '/');
            % Extract and assign individual components
            for j = 1:length(components)
                switch extractBefore(components{j}, ':')
                    case 'AV' % Attack Vector
                        switch extractAfter(components{j}, ':')
                            case 'N'
                                OVLP(k,1).AV='NETWORK';
                            case 'A'
                                OVLP(k,1).AV='ADJACENT';
                            case 'L'
                                OVLP(k,1).AV='LOCAL';
                            case 'P'
                                OVLP(k,1).AV='PHYSICAL';
                        end
                    case 'AC' % Access Complexity
                        switch extractAfter(components{j}, ':')
                            case 'L'
                                OVLP(k,1).AC='LOW';
                            case 'H'
                                OVLP(k,1).AC='HIGH';
                        end
                    case 'PR' % Privileges Required
                        switch extractAfter(components{j}, ':')
                            case 'N'
                                OVLP(k,1).PR='NONE';
                            case 'L'
                                OVLP(k,1).PR='LOW';
                            case 'H'
                                OVLP(k,1).PR='HIGH';
                        end
                    case 'UI' % User Interaction
                        switch extractAfter(components{j}, ':')
                            case 'N'
                                OVLP(k,1).UI='NONE';
                            case 'P'
                                OVLP(k,1).UI='PASSIVE';
                            case {'A','R'}
                                OVLP(k,1).UI='ACTIVE';
                        end
                    case {'C','VC'} % Confidentiality
                        switch extractAfter(components{j}, ':')
                            case 'N'
                                OVLP(k,1).VC='NONE';
                            case 'L'
                                OVLP(k,1).VC='LOW';
                            case 'H'
                                OVLP(k,1).VC='HIGH';
                        end
                    case {'I','VI'} % Integrity
                        switch extractAfter(components{j}, ':')
                            case 'N'
                                OVLP(k,1).VI='NONE';
                            case 'L'
                                OVLP(k,1).VI='LOW';
                            case 'H'
                                OVLP(k,1).VI='HIGH';
                        end
                    case {'A','VA'} % Availability Impact
                        switch extractAfter(components{j}, ':')
                            case 'N'
                                OVLP(k,1).VA='NONE';
                            case 'L'
                                OVLP(k,1).VA='LOW';
                            case 'H'
                                OVLP(k,1).VA='HIGH';
                        end
                    case 'E'
                        switch extractAfter(components{j}, ':')
                            case 'X'
                                OVLP(k,1).EM='NOT-DEFINED';
                            case 'A'
                                OVLP(k,1).EM='ATTACKED';
                            case 'P'
                                OVLP(k,1).EM='PROOF-OF-CONCEPT';
                            case 'U'
                                OVLP(k,1).EM='UNREPORTED';
                        end
                    case 'MAT'
                        switch extractAfter(components{j}, ':')
                            case 'X'
                                OVLP(k,1).AR='NOT-DEFINED';
                            case 'N'
                                OVLP(k,1).AR='NONE';
                            case 'P'
                                OVLP(k,1).AR='PRESENT';
           
                        end
                end
            end
            if OVLP(k,1).EM==""
                OVLP(k,1).EM='NOT-DEFINED';
            end
            if OVLP(k,1).AR==""
                OVLP(k,1).AR='NOT-DEFINED';
            end
            if OVLP(k,1).UI==""
                OVLP(k,1).UI='NOT-DEFINED';
            end
            k=k+1;
        end
    end
end
end

