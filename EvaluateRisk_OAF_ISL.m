clear objects subjects OVLP NT ACL
%inputParameters=["PML"];
%values=[5];

api_key="5c597a2b-2ead-4142-b70c-9541228534bb";
env="nokia";
testInputParameters=dictionary();
SPMP=dictionary();
LOIMethod="direct";
minimalImpactLevel=0.5;
SPMPNames=["Reset account lockout counter after","Minimum password age","Account Lockout Duration","Maximum password age","Enforce password history","Account Lockout Threshold","Minimum password length","Password must meet complexity requirements","Store passwords using reversible encryption"];
if env=="test1"

    SPMP("RAL")=1;
    SPMP("mPA")=1;
    SPMP("ALD")=1;
    SPMP("MPA")=1;
    SPMP("EPH")=1;
    SPMP("ALT")=1;
    SPMP("MPL")=1;
    SPMP("PCR")=1;
    SPMP("SPE")=1;

    testInputParameters("PML")=calcPML(SPMP);
    testInputParameters("SCA")=5;
    testInputParameters("AC")=0;%0-Low 1 - High
    testInputParameters("AR")=0;%0-None 1 - Present
    testInputParameters("PRM")=0.3;%0.1 - R, 0.3 - A, 0.5 - D, 0.7 - E, 0.9 - P
    testInputParameters("PR")=0.3;
    testInputParameters("SPI")=0.5;
    testInputParameters("NTA")=0;%0 - CAN, 0.5 - LAN, 1 - PAN
    testInputParameters("NTS")=0;%0 - open, 0.5 - close, 1 - VPN
    testInputParameters("AV")=0;%0 - network, 0.37 - adjacent, 0.62 - local, 0.87 - physical
    testInputParameters("EM")=0.5;%0 - impossible, 0.25 - unlikely, 0.5 - possible, 0.75 - likely, 1 - very likely
    testInputParameters("VC")=0.5;
    testInputParameters("VA")=0.5;
    testInputParameters("VI")=0.5;
    testInputParameters("OAF")=0.5;
    testInputParameters("ISL")=0.5;
    testInputParameters("LOI")=0.5;
end
if env=="nokia"
    subjects(1)=struct("RAL", 1,"mPA", 1,"ALD", 1,"MPA", 1,"EPH", 1,"ALT", 1,"MPL", 1,"PCR", 1,"SPE", 1);
    subjects(2)=struct("RAL", 0,"mPA", 0,"ALD", 0,"MPA", 1,"EPH", 1,"ALT", 0,"MPL", 0,"PCR", 1,"SPE", 0);
    subjects(3)=struct("RAL", 0,"mPA", 0,"ALD", 0,"MPA", 1,"EPH", 1,"ALT", 0,"MPL", 1,"PCR", 0,"SPE", 0);
    
    CVEList=["CVE-2022-32548","CVE-2020-35221","CVE-2021-34086"];
    nCVEs=length(CVEList);
    OVLPTemplate = struct ("CVE", "","VALUE", 0,"EM", "","AV", "","AC", "","PR", "","UI", "","VC", "","VA", "","VI", "","AR","");
    OVLP=repmat(OVLPTemplate, nCVEs, 1);
    for CVE=1:nCVEs
        CVEStruct=getCVEStruct(CVEList(CVE));
        OVLP(CVE)=parseCVE(CVEStruct,OVLPTemplate);
    end

    %OVLP(1)=	struct ("CVE", "CVE-2022-32548","VALUE", 9.8,"EM", "Proof-of-Concept","AV", "Network","AC", "High","PR", "None","UI", "None","VC", "High","VA", "High","VI", "High","AR","None");
    %OVLP(2)=	struct ("CVE", "CVE-2020-35221","VALUE", 8.8,"EM", "Not-Defined","AV", "Adjacent","AC", "Low","PR", "None","UI", "None","VC", "High","VA", "High","VI", "High","AR","None");
    %OVLP(3)=	struct ("CVE", "CVE-2021-34086","VALUE", 8.8,"EM", "Attacked","AV", "Network","AC" ,"Low","PR", "None","UI", "Active","VC", "High","VA", "High","VI", "High","AR","None");
    
    objects(1)=	struct("Name", "Router","OVL", "Critical","OAF", "Constantly","ISL", "High","LOD", "Low","LOI", "Low","OVLP",[1],"S","Negligible");
    objects(2)=	struct("Name", "Switch","OVL", "High","OAF", "Constantly","ISL", "High","LOD", "Low","LOI", "High","OVLP",[2],"S","Negligible");
    objects(3)=	struct("Name", "Robot","OVL", "High","OAF", "Often","ISL", "Low","LOD", "Medium","LOI", "Low","OVLP",[],"S","Marginal");
    objects(4)=	struct("Name", "PC 1 left TV","OVL", "None","OAF", "Rarely","ISL", "Low","LOD", "Low","LOI", "Low","OVLP",[],"S","Negligible");
    objects(5)=	struct("Name", "IP Camera","OVL", "None","OAF", "Constantly","ISL", "High","LOD", "Medium","LOI", "Low","OVLP",[],"S","Negligible");
    objects(6)=	struct("Name", "Google ML Board","OVL", "None","OAF", "Constantly","ISL", "High","LOD", "Low","LOI", "Low","OVLP",[],"S","Negligible");
    objects(7)=	struct("Name", "MES","OVL", "None","OAF", "Constantly","ISL", "High","LOD", "Medium","LOI", "Medium","OVLP",[],"S","Negligible");
    objects(8)=	struct("Name", "Kafka","OVL", "None","OAF", "Constantly","ISL", "High","LOD", "Low","LOI", "Medium","OVLP",[],"S","Negligible");
    objects(9)=	struct("Name", "3D Printer","OVL", "None","OAF", "Rarely","ISL", "Low","LOD", "High","LOI", "Low","OVLP",[3],"S","Negligible");
    
    NT=struct("NTA", "CAN","NTS", "Open","SPI", "Average");
    nUsers=length(subjects);
    nObjects=length(objects);
    ACL=cell(nUsers,nObjects);
    Risks=zeros(nUsers,nObjects);
    graphArray = cell(nUsers,nObjects);
    ACL(:,:)={"None"};
    ACL(1,1)={struct("Permission", "P","SCA", "AAL-1")};
    ACL(1,2)={struct("Permission", "P","SCA", "AAL-1")};
    ACL(1,3)={struct("Permission", "P","SCA", "AAL-1")};
    ACL(1,4)={struct("Permission", "P","SCA", "AAL-1")};
    ACL(1,5)={struct("Permission", "P","SCA", "AAL-1")};
    ACL(1,6)={struct("Permission", "P","SCA", "AAL-1")};
    ACL(1,7)={struct("Permission", "P","SCA", "AAL-1")};
    ACL(1,8)={struct("Permission", "P","SCA", "AAL-1")};
    ACL(2,3)={struct("Permission", "E","SCA", "AAL-1")};
    ACL(2,7)={struct("Permission", "R","SCA", "AAL-1")};
    ACL(2,9)={struct("Permission", "E","SCA", "AAL-1")};
    ACL(3,4)={struct("Permission", "R","SCA", "AAL-1")};
    ACL(3,5)={struct("Permission", "E","SCA", "AAL-1")};
    ACL(3,6)={struct("Permission", "P","SCA", "AAL-1")};
    ACL(3,7)={struct("Permission", "R","SCA", "AAL-1")};
    LOIMatrix=getLOIMatrix('influence_nokia.csv');
    impacts=sum(LOIMatrix,2);
    OAFArray=0:0.05:1;
    ISLArray=0:0.05:1;
    RisksArray=zeros(length(ISLArray),length(OAFArray));

    for object=1:nObjects
        objects(object).LOI=impacts(object)/sum(impacts);
    end
    %if LOIMethod=="direct"
    %    for object=1:nObjects
    %        objects(object).LOI=impacts(object)/sum(impacts);
    %    end
    %end
    if LOIMethod=="indirect"
        %emptyStruct=struct();
        %OVLPInitial=rep[mat(OVLP(1),1,nObjects);
        %for object=1:nObjects
        OVLPInitial={objects.OVLP};
        %end
        for object1=1:nObjects
            for object2=1:nObjects
                if LOIMatrix(object1,object2)>minimalImpactLevel
                    if ~isempty(OVLPInitial(object1))
                        %test=OVLPInitial{object1};
                        objects(object2).OVLP=[objects(object2).OVLP OVLPInitial{object1}];
                    end
                end
            end
        end
        for object=1:nObjects
            objects(object).OVLP=unique(objects(object).OVLP);
        end
    end
    %for user=1:nUsers
    %    for object=1:nObjects
    user=1;
    object=1;
    for i=1:length(ISLArray)
        for j=1:length(OAFArray)
            if isstruct(ACL{user,object})
                %%{ 
                    SPMP("RAL")=subjects(user).RAL;
                    SPMP("mPA")=subjects(user).mPA;
                    SPMP("ALD")=subjects(user).ALD;
                    SPMP("MPA")=subjects(user).MPA;
                    SPMP("EPH")=subjects(user).EPH;
                    SPMP("ALT")=subjects(user).ALT;
                    SPMP("MPL")=subjects(user).MPL;
                    SPMP("PCR")=subjects(user).PCR;
                    SPMP("SPE")=subjects(user).SPE;
                %%}
                    %SPMP=getPML("PML_"+user+".json");
                    testInputParameters("PML")=calcPML(SPMP);
                    switch ACL{user,object}.SCA
                        case "AAL-1"
                            testInputParameters("SCA")=0;
                        case "AAL-2"
                            testInputParameters("SCA")=5;
                        case "AAL-3"
                            testInputParameters("SCA")=10;
                    end
                    
                    switch ACL{user,object}.Permission
                        case "R"
                            testInputParameters("PRM")=0.1;
                        case "A"
                            testInputParameters("PRM")=0.3;
                        case "D"
                            testInputParameters("PRM")=0.5; 
                        case "E"
                            testInputParameters("PRM")=0.7;
                        case "P"
                            testInputParameters("PRM")=0.9;
                    end
                    switch NT.SPI
                        case "Low"
                            testInputParameters("SPI")=0;
                        case "Average"
                            testInputParameters("SPI")=0.5;
                        case "High"
                            testInputParameters("SPI")=1;
                    end
                    switch NT.NTA
                        case "CAN"
                            testInputParameters("NTA")=0;
                        case "LAN"
                            testInputParameters("NTA")=0.5;
                        case "PAN"
                            testInputParameters("NTA")=1;
                    end
                    switch NT.NTS
                        case "Open"
                            testInputParameters("NTS")=0;
                        case "Close"
                            testInputParameters("NTS")=0.5;
                        case "VPN"
                            testInputParameters("NTS")=1;
                    end

                    % switch objects(object).OAF
                    %     case "Ftf"
                    %         testInputParameters("OAF")=0;
                    %     case "Rarely"
                    %         testInputParameters("OAF")=0.25;
                    %     case "Average"
                    %         testInputParameters("OAF")=0.5;
                    %     case "Often"
                    %         testInputParameters("OAF")=0.75;
                    %     case "Constantly"
                    %         testInputParameters("OAF")=1;
                    % end
                    % switch objects(object).ISL
                    %     case "Low"
                    %         testInputParameters("ISL")=0;
                    %     case "Medium"
                    %         testInputParameters("ISL")=0.5;
                    %     case "High"
                    %         testInputParameters("ISL")=1;
                    % end
                    testInputParameters("OAF")=OAFArray(j);
                    testInputParameters("ISL")=ISLArray(i);

                    %switch objects(object).LOI
                    %    case "None"
                    %        testInputParameters("LOI")=0.12;                        
                    %    case "Low"
                    %        testInputParameters("LOI")=0.37;
                    %    case "Medium"
                    %        testInputParameters("LOI")=0.62;
                    %    case "High"
                    %        testInputParameters("LOI")=0.87;
                    %end
                    if LOIMethod=="direct"
                        testInputParameters("LOI")=objects(object).LOI;
                    end
                    switch objects(object).S
                        case "Negligible"
                            testInputParameters("S")=0;
                        case "Marginal"
                            testInputParameters("S")=0.5;
                        case "Critical"
                            testInputParameters("S")=0.75;
                        case "Catastrophic"
                            testInputParameters("S")=1;
                    end
                    nVulnerability=max(1,length(objects(object).OVLP));
                    RiskLevel=zeros(nVulnerability,1);
                    intermediateNodes = cell(nVulnerability,1);
                    for vulnerability=1:nVulnerability
                        if ~isempty(objects(object).OVLP)
                            switch OVLP(objects(object).OVLP(vulnerability)).AC
                                case "LOW"
                                    testInputParameters("AC")=0;
                                case "HIGH"
                                    testInputParameters("AC")=1;
                            end
                            switch OVLP(objects(object).OVLP(vulnerability)).AR
                                case "NONE"
                                    testInputParameters("AR")=0;
                                case "PRESENT"
                                    testInputParameters("AR")=1;
                            end
                            switch OVLP(objects(object).OVLP(vulnerability)).PR
                                case "NONE"
                                    testInputParameters("PR")=0;
                                case "LOW"
                                    testInputParameters("PR")=0.5;
                                case "HIGH"
                                    testInputParameters("PR")=1;
                            end
                            switch OVLP(objects(object).OVLP(vulnerability)).AV
                                case "NETWORK"
                                    testInputParameters("AV")=0.12;
                                case "ADJACENT"
                                    testInputParameters("AV")=0.37;
                                case "LOCAL"
                                    testInputParameters("AV")=0.62;
                                case "PHYSICAL"
                                    testInputParameters("AV")=0.87;    
                            end
                            switch OVLP(objects(object).OVLP(vulnerability)).EM
                                case "UNREPORTED"
                                    testInputParameters("EM")=0.12;
                                case "PROOF-OF-CONCEPT"
                                    testInputParameters("EM")=0.37;
                                case "ATTACKED"
                                    testInputParameters("EM")=0.62;
                                case "NOT-DEFINED"
                                    testInputParameters("EM")=0.87;    
                            end
                            switch OVLP(objects(object).OVLP(vulnerability)).VC
                                case "NONE"
                                    testInputParameters("VC")=0;
                                case "LOW"
                                    testInputParameters("VC")=0.5;
                                case "HIGH"
                                    testInputParameters("VC")=1;
                            end
                            switch OVLP(objects(object).OVLP(vulnerability)).VA
                                case "NONE"
                                    testInputParameters("VA")=0;
                                case "LOW"
                                    testInputParameters("VA")=0.5;
                                case "HIGH"
                                    testInputParameters("VA")=1;
                            end
                            switch OVLP(objects(object).OVLP(vulnerability)).VI
                                case "NONE"
                                    testInputParameters("VI")=0;
                                case "LOW"
                                    testInputParameters("VI")=0.5;
                                case "HIGH"
                                    testInputParameters("VI")=1;
                            end
                        else
                            testInputParameters("AC")=0;
                            testInputParameters("AR")=0;
                            testInputParameters("PR")=0;
                            testInputParameters("AV")=0;
                            testInputParameters("EM")=0;
                            testInputParameters("VC")=0;
                            testInputParameters("VA")=0;
                            testInputParameters("VI")=0;
                        end
                        [RiskLevel(vulnerability), intermediateNodes{vulnerability}]=EvaluateRisk(testInputParameters,LOIMethod);
                    end
                    
                    RisksArray(i,j)=max(RiskLevel);
                    %[Risks(user,object), i]=max(RiskLevel);
                    %graphArray{user,object}=graphArrayOne{i};
                    %if user==1 && object==1
                        %fig1 = uifigure('Position', [100 100 1200 800]);
                        %ax = uiaxes(fig1,'Position', [20 20 1100 750]);
                    %graphArray{user,object}=createGraph(SPMP,SPMPNames,testInputParameters,intermediateNodes{i},RiskLevel(i),LOIMethod);
                    %if user==1 && object==1
                    %    fig1 = uifigure('Position', [100 100 1200 800]);
                    %    ax = uiaxes(fig1,'Position', [20 20 1100 750]);
                    %    plotGraph(ax,graphArray{user,object})
                    %end
                    %objects(object).Name
                    %user
                    %RiskLevel
            end
        end
    end
end
[X, Y] = meshgrid(ISLArray,OAFArray);
surf(X, Y, RisksArray);
xlabel('ISL');
ylabel('OAF');
zlabel('Risks');
title('Risk surface');
c = colorbar();
c.Ticks = [0 0.2 0.4 0.6 0.8];
c.TickLabels = {'Slight', 'Possible', 'Substantial', 'High', 'Very high'};
c.Label.String="Risk levels";
shading("interp");
userColumn = (1:nUsers)';
objectsNames=strings(1,nObjects);
for i = 1:length(objects)
    objectsNames(i) = objects(i).Name;
end
tablerisks=array2table([userColumn,Risks],"VariableNames",["Users",objectsNames]);
%global usersNames, objectsNames, Risks
usersNames="User "+string(userColumn);
%plotRiskSurface(Risks,usersNames,objectsNames);
mainFig = uifigure('Name', 'Risk levels', 'Position', [100 100 1200 800]);
plotGUI(Risks,usersNames,objectsNames,mainFig);
aggRisk=aggregatedRisk(Risks,impacts,objects,0.7);

%tablerisks

tableData = table2cell(tablerisks);
columnNames = tablerisks.Properties.VariableNames;
t = uitable(mainFig, 'Data', Risks, 'ColumnName', objectsNames, 'RowName', usersNames, ...
    'Position', [20 650 1100 120], 'Tag', 'RiskTable');
t.CellSelectionCallback = @(src, event) riskTableCellSelected(src, event, graphArray, usersNames, objectsNames);
setappdata(mainFig, 'RiskTable', t);
riskGuiLayout(mainFig);
labelText=append('Aggregated risk: ',string(aggRisk));
uilabel(mainFig, ...
        'Text', labelText, ...
        'Position', [20, 770, 1100, 30], ...  % [x, y, width, height]
        'HorizontalAlignment', 'center');
%fprintf('Aggregated risk: %f\n', aggRisk);
%RiskLevel=EvaluateRisk(testInputParameters);
%RiskLevel
