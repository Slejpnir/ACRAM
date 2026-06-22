function test_framework(test_name, varargin)
%TEST_FRAMEWORK Simple project smoke-test framework.
%   Usage:
%     test_framework('run_all')
%     test_framework('test_function', function_name, test_cases)
%     test_framework('report')
%     test_framework('clear')

persistent test_results

if isempty(test_results)
    test_results = emptyResults();
end

switch lower(string(test_name))
    case "run_all"
        fprintf('Running all tests...\n');

        test_framework('test_function', 'map_linguistic', {
            {'ADJACENT_NETWORK', 0.12}, ...
            {'LOW', 0}, ...
            {'HIGH', 1}, ...
            {'PHYSICAL', 0.87}
        });

        obj1 = struct('OVL', 'Low', 'OAF', 'Constantly', 'ISL', 'High', 'S', 'Negligible');
        obj2 = struct('OVL', 'High', 'OAF', 'Rarely', 'ISL', 'High', 'S', 'Critical');
        test_framework('test_function', 'aggregatedRisk', {
            {[0.2 0.7; 0.3 0.1], [1; 1], [obj1 obj2], 0.7, 0.58}
        });

        test_config = struct('gui', 'on', 'realTime', 'off', 'realTimeMode', 'local', ...
            'env', 'test', 'LOIMethod', 'indirect', 'LOIinput', 'csv', ...
            'OVLPMethod', 'direct', 'mockOAB', 0.5, 'minimalImpactLevel', 0.1, ...
            'sbom', 'manual', 'OAFFilename', 'test.csv', 'SABFileName', 'test.csv', ...
            'subjects', [1, 2, 3], 'objects', [1, 2, 3]);
        test_framework('test_function', 'config_validator', {test_config});

        data_cache('clear');
        test_framework('test_function', 'data_cache', {
            {'store', 'test_key', [1, 2, 3]}, ...
            {'get', 'test_key', [1, 2, 3]}
        });

        test_framework('report');

    case "test_function"
        function_name = string(varargin{1});
        test_cases = varargin{2};

        fprintf('Testing %s...\n', function_name);

        for i = 1:numel(test_cases)
            test_case = test_cases{i};
            try
                switch function_name
                    case "map_linguistic"
                        result = map_linguistic(test_case{1});
                        expected = test_case{2};
                        assertEqualEnough(result, expected);
                        recordPass(i);

                    case "config_validator"
                        config_validator(test_case);
                        recordPass(i);

                    case "data_cache"
                        if strcmp(test_case{1}, 'store')
                            data_cache('store', test_case{2}, test_case{3});
                            recordPass(i);
                        elseif strcmp(test_case{1}, 'get')
                            result = data_cache('get', test_case{2});
                            expected = test_case{3};
                            assertEqualEnough(result, expected);
                            recordPass(i);
                        else
                            error('test_framework:UnknownDataCacheAction', ...
                                'Unknown data_cache test action: %s', test_case{1});
                        end

                    case "aggregatedRisk"
                        result = aggregatedRisk(test_case{1}, test_case{2}, ...
                            test_case{3}, test_case{4});
                        expected = test_case{5};
                        assertEqualEnough(result, expected);
                        recordPass(i);

                    otherwise
                        error('test_framework:UnknownFunction', ...
                            'Unknown function: %s', function_name);
                end
            catch ME
                test_results.failed = test_results.failed + 1;
                test_results.details{end+1} = struct('test', i, 'status', 'failed', ...
                    'message', ME.message);
                fprintf('  FAIL Test %d: %s\n', i, ME.message);
            end
        end

    case "report"
        total = test_results.passed + test_results.failed;
        if total > 0
            fprintf('\nTest Results:\n');
            fprintf('  Passed: %d\n', test_results.passed);
            fprintf('  Failed: %d\n', test_results.failed);
            fprintf('  Success Rate: %.1f%%\n', (test_results.passed / total) * 100);
        else
            fprintf('No tests have been run yet.\n');
        end

    case "clear"
        test_results = emptyResults();

    otherwise
        error('Unknown test framework action: %s', test_name);
end

    function recordPass(testIndex)
        test_results.passed = test_results.passed + 1;
        test_results.details{end+1} = struct('test', testIndex, 'status', 'passed', ...
            'message', '');
        fprintf('  PASS Test %d\n', testIndex);
    end
end

function results = emptyResults()
results = struct('passed', 0, 'failed', 0, 'details', {{}});
end

function assertEqualEnough(actual, expected)
if isnumeric(actual) && isnumeric(expected)
    if ~isequal(size(actual), size(expected)) || any(abs(actual - expected) > 1e-12, 'all')
        error('test_framework:AssertionFailed', ...
            'expected %s, got %s', mat2str(expected), mat2str(actual));
    end
elseif ~isequaln(actual, expected)
    error('test_framework:AssertionFailed', 'expected and actual differ');
end
end
