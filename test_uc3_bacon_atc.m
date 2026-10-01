function summary = test_uc3_bacon_atc(outputRoot)
%TEST_UC3_BACON_ATC Exercise context routing and production risk calculation.
% Publishers are captured locally; no credentials, sockets or ADI writes occur.
root = fileparts(mfilename('fullpath'));
if nargin == 0, outputRoot = tempname(fullfile(root, 'dist')); end
if ~isfolder(outputRoot), mkdir(outputRoot); end
originalFolder = pwd;
originalPath = path;
cleanup = onCleanup(@() restoreEnvironment(originalFolder, originalPath)); %#ok<NASGU>
addpath(root);
writeCapture(fullfile(outputRoot, 'resultJSON.m'), 'component');
writeCapture(fullfile(outputRoot, 'aggregatedIndicator.m'), 'aggregate');
cd(outputRoot);
clear resultJSON aggregatedIndicator real_time_monitor
setappdata(0, 'uc3PublishCalls', {});

baconContext = 'c91f82042835e3265ca38a92bc3a49a80c23ab320066169308e18259f33a4168';
atcContext = '524e1931f88652a66acec6c0af1795a34d120bdce8cb058808093ea6d0bf953a';
atcRevision = 'd3ce45c86789793e43161697f1e89aff0439686db61bc60ce657cb89086d1e3a';
config = struct('gui','off','LOIMethod','indirect','env','telco3PCs', ...
    'sendRealtimeResultsToDataSpace',true,'exportRiskGraphs',false, ...
    'networkAnomalyTargetObjectName','Gateway','adiInputContextsOnly',true, ...
    'adiInputContexts',struct('bacon',baconContext,'atc',{{atcContext,atcRevision}}));

% The server must receive a context filter that does not require data.source.
sources = {'BACON','ATC Network Event','SBOM Tool'};
filters = adi_subscription_filters(config, sources);
wireFilters = jsondecode(jsonencode(filters));
inName = matlab.lang.makeValidName('$in');
orName = matlab.lang.makeValidName('$or');
assert(isequal(sort(string(wireFilters.context_id.(inName))), ...
    sort([string(baconContext);string(atcContext);string(atcRevision)])), ...
    'Restricted subscription must contain all existing BACON/ATC IDs.');
assert(~isfield(wireFilters,'data_source'), 'Restricted mode must not subscribe by source.');
mixed = config;
mixed.adiInputContextsOnly = false;
mixedFilters = jsondecode(jsonencode(adi_subscription_filters(mixed,sources)));
assert(isfield(mixedFilters,orName) && numel(mixedFilters.(orName))==2, ...
    'Mixed mode must OR legacy sources with context IDs.');
legacyFilters = jsonencode(adi_subscription_filters(struct(),sources));
assert(contains(legacyFilters,'"data.source"') && ~contains(legacyFilters,'"context_id"'), ...
    'Deployments without configured contexts must retain legacy subscription.');

subject = struct('RAL',1,'mPA',1,'ALD',1,'MPA',1,'EPH',1,'ALT',1, ...
    'MPL',1,'PCR',1,'SPE',1,'SAB','Low');
subjects = [subject subject];
object = struct('Name','Gateway','OVL','None','OAF','Constantly', ...
    'ISL','High','LOD','Low','LOI',0.5,'OVLP',1,'S','Negligible', ...
    'OAB','Low','IP','163.162.228.1');
objects = [object object];
objects(2).Name = 'Other PC';
objects(2).IP = '192.0.2.20';
ACL = repmat({'None'},2,2);
ACL{1,1} = struct('Permission','A','SCA','AAL-1');
ACL{2,1} = ACL{1,1};
ACL{1,2} = ACL{1,1};
impacts = [0.5;0.5];
NT = struct('NTA','WAN','NTS','VPN','SPI','High');
OVLP = struct('CVE','CVE-TEST-UC3','VALUE',8.8,'EM','Unreported', ...
    'AV','Network','AC','Low','PR','None','UI','Active', ...
    'VC','High','VA','High','VI','High','AR','None');
[Risks,intermediate,inputs,graphs] = calculate_risks(subjects,objects,OVLP,NT,ACL,config,@map_linguistic);

% User-provided BACON shape, including a hyphenated details key and IP array.
baconJson = ['{"asset_id":"bacon-asset","id":"bacon-on",' ...
    '"context_id":"' baconContext '","data":{"source":"BACON",' ...
    '"severity":"ON","value":1,"subject":"Flow anomaly detection event",' ...
    '"involved_ports":[61779,8088],"packets_exchanged":19,' ...
    '"supplementary-details":{"root_cause":"src_ip_type",' ...
    '"traffic_participants":["163.162.228.6","163.162.228.251"]}}}'];
bacon = jsondecode(baconJson);
replay(bacon,true);
calls = getappdata(0,'uc3PublishCalls');
assert(numel(calls)==2, 'BACON must publish a changed component and aggregate.');
checkPair(calls(end-1:end), "bacon-on");
baconRisks = calls{1}.args{1};
assert(max(abs(baconRisks-Risks(:,1)))>1e-6, 'BACON must change actual model risk.');
assert(contains(string(calls{1}.args{11}), 'BACONNAD -> Gateway'));
replay(bacon,false);
assert(numel(getappdata(0,'uc3PublishCalls'))==2, 'Duplicate BACON must not republish.');

% ATC rMon has no source field and uses comma-separated participants/ports.
atc = struct('asset_id','atc-asset','id','atc-on','context_id',atcContext, ...
    'data',struct('severity','ON','value',1,'root_cause','traffic_anomaly', ...
    'traffic_participants','163.162.228.6, 163.162.228.251', ...
    'involved_ports','61779,8088','packets_exchanged',19));
[source,accepted] = adi_transaction_source(atc,config);
assert(accepted && source=="ATC Network Event", 'Source-less ATC must not become BACON/NAD.');
atcOutput = replay(atc,false);
calls = getappdata(0,'uc3PublishCalls');
assert(contains(atcOutput,'integrated anomaly level for Gateway: 0.750'), ...
    'ATC and BACON must occupy independent indicator slots.');
% This fixture reaches the same fuzzy risk plateau with one and two active
% network tools. A recalculation must not invent an increased risk or send
% duplicate risk transactions merely because another tool became active.
assert(numel(calls)==2 && contains(atcOutput,'No risk change for Gateway'), ...
    'An unchanged calculated risk must not be republished.');
combinedRisks = baconRisks;

% OFF clears only the relevant source; BACON OFF leaves active ATC evidence.
bacon.id = 'bacon-off';
bacon.data.severity = 'OFF';
bacon.data.value = 0;
baconOffOutput = replay(bacon,false);
calls = getappdata(0,'uc3PublishCalls');
assert(contains(baconOffOutput,'integrated anomaly level for Gateway: 0.500'), ...
    'BACON OFF must leave the independent ATC indicator active.');
assert(numel(calls)==2, 'BACON OFF must not clear active ATC risk or republish unchanged risk.');
atcOnlyRisks = baconRisks;
atc.id = 'atc-off';
atc.context_id = atcRevision;
atc.data.severity = 'OFF';
atc.data.value = 0;
replay(atc,false);
calls = getappdata(0,'uc3PublishCalls');
assert(numel(calls)==4, 'ATC OFF through the revision ID must publish cleared risk.');
checkPair(calls(end-1:end), strings(0,1));
clearedRisks = calls{3}.args{1};
assert(max(abs(clearedRisks-combinedRisks))>1e-6);

% Source-less ATC alone also publishes a real risk change and ATC provenance.
atc.id = 'atc-only-on';
atc.data.severity = 'ON';
atc.data.value = 1;
replay(atc,false);
calls = getappdata(0,'uc3PublishCalls');
assert(numel(calls)==6, 'Source-less ATC alone must publish changed risk.');
checkPair(calls(end-1:end), "atc-only-on");
assert(isequal(string(calls{5}.args{11}),"ATCNAD -> Gateway"));

% A schema definition and unrelated context must never be treated as events.
contextDefinition = struct('id',atcRevision,'asset_id',atcContext,'data', ...
    struct('context_data',struct('severity',struct('type','string')), ...
    'context_metadata',struct()));
[~,accepted] = adi_transaction_source(contextDefinition,config);
assert(~accepted, 'ATC context definitions must not be routed as anomaly observations.');
replay(contextDefinition,false);
unrelated = atc;
unrelated.id = 'unrelated';
unrelated.context_id = repmat('a',1,64);
unrelated.data.source = 'BACON';
unrelated.data.severity = 'ON';
replay(unrelated,false);
assert(numel(getappdata(0,'uc3PublishCalls'))==6, 'Restricted mode must ignore unrelated contexts.');

% Matching participant IP takes precedence over the explicit Gateway fallback.
atc.id = 'atc-direct-ip';
atc.context_id = atcContext;
atc.data.severity = 'ON';
atc.data.value = 1;
atc.data.traffic_participants = '192.0.2.20, 198.51.100.4';
replay(atc,true);
calls = getappdata(0,'uc3PublishCalls');
assert(numel(calls)==8 && strcmp(calls{7}.args{2},'Other PC'), ...
    'A matching configured IP must target that object instead of the Gateway fallback.');
assert(max(abs(calls{8}.args{2}{:,2}-Risks(:,1)))<1e-10, 'Direct PC telemetry must preserve Gateway risk.');

legacyAtc = rmfield(atc,'context_id');
[source,accepted] = adi_transaction_source(legacyAtc,struct());
assert(accepted && source=="NAD", 'Unconfigured deployments must retain legacy source inference.');
summary = struct('passed',true,'networkCalls',0,'capturedCalls',numel(calls), ...
    'baconRisk',baconRisks(1),'combinedRisk',combinedRisks(1), ...
    'atcOnlyRisk',atcOnlyRisks(1),'clearedRisk',clearedRisks(1));
fid = fopen(fullfile(outputRoot,'result.json'),'w');
assert(fid>=0);
fwrite(fid,jsonencode(summary,'PrettyPrint',true),'char');
fclose(fid);
fprintf('PASS: UC3 BACON/ATC context routing and risk publication; no network calls.\n');

    function output = replay(tx,resetBefore)
        output = evalc('real_time_monitor(''test_adi_transaction'',tx,Risks,ACL,objects,inputs,intermediate,impacts,config,subjects,OVLP,NT,graphs,resetBefore);');
        fprintf('%s',output);
        assert(~contains(output,'ADI processing error:') && ~contains(output,'Risk recompute failed'), ...
            'The production transaction callback must complete without errors.');
    end

    function checkPair(pair,expectedInputs)
        assert(strcmp(pair{1}.kind,'component') && strcmp(pair{2}.kind,'aggregate'));
        assert(strcmp(pair{1}.args{2},'Gateway'), 'Unmatched flow IPs must use the configured Gateway.');
        assert(~pair{1}.args{5} && ~pair{2}.args{3}, 'Offline test must disable actual publishing.');
        assert(isequal(sort(string(pair{1}.args{6}(:))),sort(expectedInputs(:))), ...
            'Published input references must represent the independently active sources.');
        expectedRisks = Risks;
        expectedRisks(:,1) = pair{1}.args{1};
        expectedAggregate = aggregatedRisk(expectedRisks,impacts,objects,0.7);
        assert(abs(pair{2}.args{1}-expectedAggregate)<1e-10);
        assert(max(abs(pair{2}.args{2}{:,2:end}-expectedRisks),[],'all')<1e-10, ...
            'Aggregate must contain the complete current risk matrix.');
    end
end

function writeCapture(filePath,kind)
[~,functionName] = fileparts(filePath);
lines = {sprintf('function result = %s(varargin)',functionName), ...
    'calls = getappdata(0, ''uc3PublishCalls'');', ...
    sprintf('calls{end+1} = struct(''kind'',''%s'',''args'',{varargin});',kind), ...
    'setappdata(0, ''uc3PublishCalls'', calls);','result = [];','end'};
fid = fopen(filePath,'w');
assert(fid>=0);
fprintf(fid,'%s\n',lines{:});
fclose(fid);
end

function restoreEnvironment(originalFolder,originalPath)
cd(originalFolder);
path(originalPath);
clear resultJSON aggregatedIndicator real_time_monitor
if isappdata(0,'uc3PublishCalls'), rmappdata(0,'uc3PublishCalls'); end
end
