function summary = test_uam_risk_publishing(outputRoot)
%TEST_UAM_RISK_PUBLISHING Exercise real SBOM/UAM calculations without a network.
% Only the two publishing boundaries are captured; the model and transaction
% handler are the production functions. Artifacts remain under outputRoot.
root = fileparts(mfilename('fullpath'));
if nargin == 0
    outputRoot = tempname(fullfile(root, 'dist'));
end
if ~isfolder(outputRoot), mkdir(outputRoot); end
originalFolder = pwd;
originalPath = path;
cleanup = onCleanup(@() restoreEnvironment(originalFolder, originalPath)); %#ok<NASGU>
addpath(root);
writeCapture(fullfile(outputRoot, 'resultJSON.m'), 'component');
writeCapture(fullfile(outputRoot, 'aggregatedIndicator.m'), 'aggregate');
cd(outputRoot);
clear resultJSON aggregatedIndicator real_time_monitor
setappdata(0, 'uamPublishCalls', {});

subject = struct('RAL',1,'mPA',1,'ALD',1,'MPA',1,'EPH',1,'ALT',1, ...
    'MPL',1,'PCR',1,'SPE',1,'SAB','Low');
subjects = [subject subject];
object = struct('Name','Router_1','OVL','None','OAF','Constantly', ...
    'ISL','High','LOD','Low','LOI',0.5,'OVLP',[],'S','Critical', ...
    'OAB','Low','IP','');
objects = [object object];
objects(2).Name = 'No access target';
objects(2).IP = '192.0.2.11';
impacts = [0.5;0.5];
ACL = repmat({'None'},2,2);
ACL{1,1} = struct('Permission','A','SCA','AAL-1');
ACL{2,1} = ACL{1,1};
NT = struct('NTA','WAN','NTS','VPN','SPI','High');
config = struct('gui','off','LOIMethod','indirect', ...
    'parseCVEListFromWebsocket',true,'sendRealtimeResultsToDataSpace',true, ...
    'saveRealtimeResultsToFile',true,'exportRiskGraphs',false);
OVLP = [];
[Risks, intermediate, inputs, graphs] = calculate_risks(subjects, objects, OVLP, NT, ACL, config, @map_linguistic);

cve = struct('cve_number','CVE-TEST-0001','score',8.8,'remarks','NewFound', ...
    'cvss_vector','CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:H');
sbom = struct('id','test-sbom-1','data',struct('source','SBOM Tool', ...
    'type','CVE list','subject','name_src=Router_1', ...
    'CVE_list',cve,'value','1'));
replay(sbom, true);
calls = getappdata(0, 'uamPublishCalls');
assert(numel(calls)==2, 'First SBOM must export one changed component and the changed aggregate.');
assert(strcmp(calls{1}.kind,'component') && strcmp(calls{2}.kind,'aggregate'));
assert(calls{1}.args{5}==false && calls{2}.args{3}==false, 'Offline replay must disable sending.');
assert(calls{1}.args{4}==true && calls{2}.args{5}==true, 'SBOM must honor requested JSON saving.');
assert(string(calls{1}.args{6})=="test-sbom-1", 'Component must identify its SBOM input.');
sbomRisks = calls{1}.args{1};
assert(max(abs(sbomRisks-Risks(:,1)))>1e-6, 'Fixture must actually alter model risk.');

uam = struct('id','test-uam-1','context_id', ...
    '2718e8975fa329947434f1ac88d9f07a1438195b9c50e22e6401d7c054237ec8', ...
    'data',struct('source','UAM','value',0.89,'user_id','user-1'));
replay(uam, false);
calls = getappdata(0, 'uamPublishCalls');
assert(numel(calls)==4, 'UAM must export changed component and aggregate risks.');
component = calls{3};
aggregate = calls{4};
assert(strcmp(component.kind,'component') && strcmp(aggregate.kind,'aggregate'));
assert(strcmp(component.args{2},objects(1).Name), 'Inaccessible object must not be exported.');
assert(string(component.args{6})=="test-uam-1", 'Component must identify its UAM input.');
assert(component.args{5}==false && aggregate.args{3}==false, 'Offline UAM replay must never send.');
assert(component.args{4}==true && aggregate.args{5}==true, 'UAM must honor requested JSON saving.');
uamRisks = component.args{1};
assert(abs(uamRisks(1)-sbomRisks(1))>1e-6, 'UAM must change the addressed user risk.');
assert(abs(uamRisks(2)-sbomRisks(2))<1e-10, 'UAM must preserve other users.');

expectedObjects = objects;
expectedObjects(1).OVLP = 1;
expectedSubjects = subjects;
expectedSubjects(1).SAB = 'High';
expectedOvlp = struct('CVE','CVE-TEST-0001','VALUE',8.8,'EM','Unreported', ...
    'AV','Network','AC','Low','PR','None','UI','Active', ...
    'VC','High','VA','High','VI','High','AR','None');
expectedRisks = calculate_risks(expectedSubjects, expectedObjects, expectedOvlp, NT, ACL, config, @map_linguistic);
assert(max(abs(uamRisks-expectedRisks(:,1)))<1e-10, 'Published UAM risks must equal an independent full recalculation.');
expectedAggregate = aggregatedRisk(expectedRisks, impacts, objects, 0.7);
assert(abs(aggregate.args{1}-expectedAggregate)<1e-10, 'Published aggregate must match current risk matrix.');
assert(isequal(aggregate.args{2}{:,2:end},expectedRisks), 'Aggregate table must contain the current risks.');

replay(uam, false);
assert(numel(getappdata(0,'uamPublishCalls'))==4, 'Duplicate transaction must not republish.');
uam.id = 'test-uam-same-level';
uam.data.value = 0.95;
replay(uam, false);
assert(numel(getappdata(0,'uamPublishCalls'))==4, 'Same SAB level must not republish.');
sbom.id = 'test-sbom-after-uam';
sbom.data.subject = 'name_src=Router 1';
replay(sbom, false);
calls = getappdata(0,'uamPublishCalls');
assert(numel(calls)==5, 'Unchanged aggregate must not republish on a later SBOM.');
assert(max(abs(calls{5}.args{1}-uamRisks))<1e-10, 'Later SBOM must preserve the UAM state.');

summary = struct('passed',true,'sbomRisk',sbomRisks(1), ...
    'uamRisk',uamRisks(1),'aggregateRisk',expectedAggregate, ...
    'capturedCalls',numel(calls),'networkCalls',0);
fid = fopen(fullfile(outputRoot,'result.json'),'w');
assert(fid>=0);
fwrite(fid,jsonencode(summary,'PrettyPrint',true),'char');
fclose(fid);
fprintf('PASS: SBOM/UAM publishing regression; actual risk %.6f -> %.6f; no network calls.\n', summary.sbomRisk, summary.uamRisk);

    function replay(tx, resetBefore)
        real_time_monitor('test_adi_transaction',tx,Risks,ACL,objects,inputs, ...
            intermediate,impacts,config,subjects,OVLP,NT,graphs,resetBefore);
    end
end

function writeCapture(filePath, kind)
[~,functionName] = fileparts(filePath);
lines = {
    sprintf('function result = %s(varargin)',functionName)
    'calls = getappdata(0, ''uamPublishCalls'');'
    sprintf('calls{end+1} = struct(''kind'',''%s'',''args'',{varargin});',kind)
    'setappdata(0, ''uamPublishCalls'', calls);'
    'result = [];'
    'end'};
fid = fopen(filePath,'w');
assert(fid>=0);
fprintf(fid,'%s\n',lines{:});
fclose(fid);
end

function restoreEnvironment(originalFolder, originalPath)
cd(originalFolder);
path(originalPath);
clear resultJSON aggregatedIndicator real_time_monitor
if isappdata(0,'uamPublishCalls'), rmappdata(0,'uamPublishCalls'); end
end
