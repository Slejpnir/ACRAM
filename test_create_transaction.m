function summary = test_create_transaction()
%TEST_CREATE_TRANSACTION Offline regression test of the real ADI write wrapper.
% The Python SDK boundary is replaced by a unique in-memory test package.
% No credentials, network requests, or production SDK modules are used.
% Run after configuring a supported Python runtime with pyenv, for example:
%   pyenv('Version','/usr/bin/python3','ExecutionMode','OutOfProcess');
%   test_create_transaction

root = fileparts(mfilename('fullpath'));
helperRoot = fullfile(root, 'tests');
if isdeployed && ~isfolder(helperRoot)
    helperRoot = fullfile(ctfroot, 'tests');
end
assert(isfile(fullfile(helperRoot, 'adi_transaction_stub.py')), ...
    'test_create_transaction:MissingFixture', 'Offline Python fixture is missing.');
pythonPath = py.sys.path;
insertedPath = int64(pythonPath.count(helperRoot)) == 0;
if insertedPath
    insert(pythonPath, int32(0), helperRoot);
end
helper = py.importlib.import_module('adi_transaction_stub');
cleanup = onCleanup(@() restoreFixture(helper, helperRoot, insertedPath)); %#ok<NASGU>
service = char(helper.install());
privateKey = 'TEST_PRIVATE_KEY_MUST_NOT_APPEAR_IN_ERRORS';
payload = containers.Map('KeyType', 'char', 'ValueType', 'any');
payload('subject') = "test-subject";
payload('nested') = containers.Map({'items'}, {{"first", 2}});
expectedId = repmat('0123456789abcdef', 1, 4);
caseCount = 0;

for mode = ["valid", "valid_upper", "padded_id"]
    helper.reset(char(mode));
    actual = send();
    assert(strcmp(actual, expectedId), 'Python string ID was not normalized correctly.');
    verifyCalls(1);
    caseCount = caseCount + 1;
end

for mode = ["401_error_success", "401_status_success"]
    helper.reset(char(mode));
    actual = send();
    assert(strcmp(actual, expectedId), 'Retry did not return the verified ID.');
    verifyCalls(2);
    caseCount = caseCount + 1;
end

for mode = ["401_error_persistent", "401_status_persistent"]
    expectError(mode, 'create_transaction:ADIAuthenticationFailed', 2);
end
for mode = ["400_error", "500_error", "4010_error"]
    expectError(mode, 'create_transaction:ADIRequestFailed', 1);
end
for mode = ["garbage", "json_error", "empty", "none", "list", ...
        "dict_id", "short_id", "long_id", "nonhex_id", "prefixed_id", ...
        "integer", "bytes"]
    expectError(mode, 'create_transaction:InvalidResponse', 1);
end

summary = struct('passed', true, 'cases', caseCount, 'networkCalls', 0, ...
    'singleSigningVerified', true, 'freshTokenRetryVerified', true);
fprintf('Offline ADI transaction tests passed: %d cases, 0 network requests.\n', caseCount);

    function transactionId = send()
        transactionId = create_transaction(payload, privateKey, ...
            'test-identity', 'http://adi-tests.invalid', service);
    end

    function verifyCalls(expectedPuts)
        state = jsondecode(char(helper.snapshot_json()));
        assert(state.sign_count == 1, 'Transaction must be signed exactly once.');
        assert(state.token_count == expectedPuts, 'Every attempt requires a fresh JWT.');
        assert(state.put_count == expectedPuts, 'Unexpected retry count.');
        expected = ["sign", repmat(["token", "put"], 1, expectedPuts)];
        assert(isequal(string(state.events(:))', expected), ...
            'Required order is signing, token generation, request, then optional fresh-token retry.');
    end

    function expectError(mode, expectedIdentifier, expectedPuts)
        helper.reset(char(mode));
        caught = [];
        try
            send();
        catch failure
            caught = failure;
        end
        assert(~isempty(caught), 'Fixture %s was incorrectly accepted as an ID.', mode);
        assert(strcmp(caught.identifier, expectedIdentifier), ...
            'Fixture %s produced %s; expected %s.', mode, caught.identifier, expectedIdentifier);
        for marker = ["TEST_PRIVATE_KEY", "TEST_RESPONSE_SECRET", "TEST_JWT_SECRET"]
            assert(~contains(caught.message, marker), ...
                'Error message disclosed test secret for fixture %s.', mode);
        end
        verifyCalls(expectedPuts);
        caseCount = caseCount + 1;
    end
end

function restoreFixture(helper, helperRoot, insertedPath)
helper.uninstall();
pythonPath = py.sys.path;
if insertedPath && int64(pythonPath.count(helperRoot)) > 0
    pythonPath.remove(helperRoot);
end
end
