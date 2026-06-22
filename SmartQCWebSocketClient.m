classdef SmartQCWebSocketClient < handle
    % SmartQC WebSocket Client using Python WebSocket
    % This class uses Python's websocket library through MATLAB's Python interface
    
    properties (Access = private)
        pythonProcess   % Python process handle
        serverAddress   % Server address
        privateKey      % Private key for JWT
        publicKey       % Public key for JWT
        filters         % Query filters
        outputFile      % File for receiving Python output
        errorFile       % File for receiving Python stderr
        pidFile         % File to store Python PID
        isRunning       % Status flag
        transactionCallback % Callback for transactions
        authAttempts    % Number of authentication attempts
        maxAuthAttempts % Maximum allowed authentication attempts
        pythonPid       % Process ID of the spawned Python client (Windows)
        monitorTimer    % Timer that polls the Python output file (non-blocking)
        monitorLastPos  % Last byte offset read from the output file
    end
    
    methods
        function obj = SmartQCWebSocketClient(serverAddress, userId, privateKey, filters, transactionCallback)
            % Constructor
            % serverAddress: WebSocket server address (e.g., 'http://192.168.1.238:8080')
            % userId: User ID for JWT generation
            % privateKey: Private key for JWT generation
            % filters: Optional filters array
            % transactionCallback: Function handle to process transactions
            
            if nargin < 4
                filters = [];
            end
            if nargin < 5
                transactionCallback = @(tx) obj.defaultTransactionHandler(tx);
            end
            
            % If server/user/private are placeholders, try to load from ws_credentials.json
            try
                if (nargin < 1) || isempty(serverAddress) || contains(serverAddress, 'REPLACE')
                    adiInfo = resolve_adi_connection([]);
                    serverAddress = string(adiInfo.credentials.websocket_address);
                    if nargin < 2 || isempty(userId) || contains(userId, 'REPLACE')
                        userId = string(adiInfo.authId);
                    end
                    if nargin < 3 || isempty(privateKey) || contains(privateKey, 'REPLACE')
                        privateKey = string(adiInfo.privateKey);
                    end
                end
            catch ME
                error('SmartQCWebSocketClient:CredentialsUnavailable', ...
                    'Unable to load WebSocket credentials: %s', ME.message);
            end
            obj.serverAddress = serverAddress;
            obj.publicKey = userId;  % Store userId as publicKey for compatibility
            obj.privateKey = privateKey;
            obj.filters = filters;
            obj.transactionCallback = transactionCallback;
            obj.isRunning = false;
            obj.outputFile = 'smartqc_output.json';
            obj.authAttempts = 0;
            obj.maxAuthAttempts = 3;
            obj.pythonPid = [];
            obj.monitorTimer = [];
            obj.monitorLastPos = 0;
            
            % Create output file with write permissions
            try
                fid = fopen(obj.outputFile, 'w');
                if fid ~= -1
                    fclose(fid);
                end
            catch
                % If we can't create in current directory, try temp directory
                obj.outputFile = fullfile(tempdir, 'smartqc_output.json');
                fid = fopen(obj.outputFile, 'w');
                if fid ~= -1
                    fclose(fid);
                end
            end
            
            % Create error file with write permissions
            obj.errorFile = 'smartqc_error.log';
            try
                fid = fopen(obj.errorFile, 'w');
                if fid ~= -1
                    fclose(fid);
                end
            catch
                obj.errorFile = fullfile(tempdir, 'smartqc_error.log');
                fid = fopen(obj.errorFile, 'w');
                if fid ~= -1
                    fclose(fid);
                end
            end
            
            % Do not run a noisy constructor-time Python preflight here.
            % connectBackground performs the real liveness check after
            % launching the same command used by the WebSocket client.
        end
        
        function success = checkPythonSetup(~)
            % Silent compatibility check. The constructor intentionally does
            % not call this; connectBackground performs the real launch check.
            success = false;
            try
                candidates = "python";
                if ~ispc
                    candidates = ["python3", "python"];
                end

                pythonCmd = "";
                for k = 1:numel(candidates)
                    candidate = candidates(k);
                    [status, ~] = system(sprintf('%s --version', char(candidate)));
                    if status == 0
                        pythonCmd = candidate;
                        break;
                    end
                end
                if strlength(pythonCmd) == 0
                    return;
                end

                [status, ~] = system(sprintf('%s -c "from websocket import WebSocketApp"', char(pythonCmd)));
                success = (status == 0);
            catch
                success = false;
            end
        end
        
        function connect(obj)
            % Connect to WebSocket server using Python
            try
                % Create Python script
                pythonScript = obj.createPythonScript();
                
                % Write Python script to file
                scriptFile = 'smartqc_websocket.py';
                fid = fopen(scriptFile, 'w');
                fprintf(fid, '%s', pythonScript);
                fclose(fid);
                
                % Start Python process
                fprintf('Starting WebSocket connection to %s\n', obj.serverAddress);
                envSnapshot = obj.setPythonEnvironment();
                envCleanup = onCleanup(@() obj.restorePythonEnvironment(envSnapshot));
                
                if ispc
                    % Windows
                    cmd = sprintf('python %s', scriptFile);
                else
                    % Unix/Linux/Mac
                    cmd = sprintf('python3 %s', scriptFile);
                end
                
                % Start Python process in background
                obj.pythonProcess = [];
                obj.isRunning = true;
                
                % Execute Python script
                fprintf('Executing Python WebSocket client...\n');
                system(cmd);
                clear envCleanup
                
            catch ME
                fprintf('Failed to connect: %s\n', ME.message);
                obj.isRunning = false;
            end
        end
        
        function connectBackground(obj)
            % Connect in background and monitor output
            try
                % Prepare file paths first
                obj.outputFile = fullfile(pwd, 'smartqc_output.json');
                obj.errorFile = fullfile(pwd, 'smartqc_error.log');
                obj.pidFile = fullfile(pwd, 'smartqc_pid.txt');
                % Create Python script
                pythonScript = obj.createPythonScript();
                % Write Python script to file
                scriptFile = 'smartqc_websocket.py';
                scriptFileAbs = fullfile(pwd, scriptFile);
                fid = fopen(scriptFileAbs, 'w');
                fprintf(fid, '%s', pythonScript);
                fclose(fid);
                % Start Python process in background
                fprintf('Starting WebSocket connection in background...\n');
                envSnapshot = obj.setPythonEnvironment();
                envCleanup = onCleanup(@() obj.restorePythonEnvironment(envSnapshot));
                if ispc
                    % Windows: use PowerShell Start-Process to get PID and set working directory
                    workdir = pwd;
                    psCmd = sprintf(['powershell -NoProfile -Command "', ...
                        'Start-Process -FilePath ''python'' ', ...
                        '-ArgumentList ''-u'',''%s'' ', ...
                        '-WorkingDirectory ''%s'' ', ...
                        '-RedirectStandardOutput ''%s'' ', ...
                        '-RedirectStandardError ''%s'' ', ...
                        '-WindowStyle Hidden -PassThru | ForEach-Object { $_.Id }"'], ...
                        scriptFileAbs, workdir, obj.outputFile, obj.errorFile);
                    [~, out] = system(psCmd);
                    pidVal = str2double(strtrim(out));
                    if ~isnan(pidVal)
                        obj.pythonPid = pidVal;
                        fprintf('Python client PID: %d\n', obj.pythonPid);
                    else
                        obj.pythonPid = [];
                        fprintf('[WARN] Could not obtain Python PID. Output: %s\n', out);
                    end
                else
                    % Unix/Linux/Mac (best effort)
                    cmd = sprintf('sh -c "python3 -u \"%s\" >> \"%s\" 2>&1 & echo $!"', scriptFileAbs, obj.outputFile);
                    [~, out] = system(cmd);
                    obj.pythonPid = str2double(strtrim(out));
                end
                clear envCleanup
                sleepNoGraphics(1); % Wait for process to start without pumping graphics callbacks.
                obj.isRunning = true;
                % Liveness check; if dead, dump logs and run foreground for diagnostics
                if ispc
                    if isempty(obj.pythonPid) || isnan(obj.pythonPid)
                        alive = false;
                    else
                        [~, tlout] = system(sprintf('tasklist /FI "PID eq %d"', obj.pythonPid));
                        alive = contains(tlout, sprintf('%d', obj.pythonPid));
                    end
                    if ~alive
                        fprintf('[ERROR] Python client exited immediately. Last logs (if any):\n');
                        if exist(obj.outputFile, 'file')
                            try
                                type(obj.outputFile);
                            catch
                            end
                        end
                        if exist(obj.errorFile, 'file')
                            try
                                type(obj.errorFile);
                            catch
                            end
                        end
                        fprintf('Running in foreground for diagnostics...\n');
                        system(sprintf('python -u "%s"', scriptFileAbs));
                        obj.isRunning = false;
                        return;
                    end
                end
                % Start monitoring output via a MATLAB timer so this method
                % returns immediately. A blocking while-loop here would freeze
                % the caller (and the risk-levels GUI) for the entire WS
                % session. Caller (real_time_monitor) is responsible for
                % invoking obj.disconnect() when shutting down.
                obj.startMonitorTimer();
            catch ME
                fprintf('Failed to connect in background: %s\n', ME.message);
                obj.isRunning = false;
            end
        end

        function startMonitorTimer(obj)
            % Stop any previous monitor timer so we never have two pollers.
            try
                if ~isempty(obj.monitorTimer) && isvalid(obj.monitorTimer)
                    stop(obj.monitorTimer);
                    delete(obj.monitorTimer);
                end
            catch
            end
            obj.monitorTimer = [];
            obj.monitorLastPos = 0;

            obj.monitorTimer = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', 1.0, ...
                'StartDelay', 0.5, ...
                'BusyMode', 'drop', ...
                'Name', 'SmartQCMonitorPoll', ...
                'TimerFcn', @(~,~) obj.pollOutputOnce(), ...
                'ErrorFcn', @(t,evt) fprintf('SmartQC monitor timer error: %s\n', evt.Data.message));
            start(obj.monitorTimer);
            fprintf('SmartQC monitor running in background (timer-based, 1s period).\n');
        end

        function pollOutputOnce(obj)
            % One iteration of the WS output-file poll. Mirrors monitorOutput
            % but is invoked by a timer so it never blocks the main thread.
            if ~obj.isRunning
                return;
            end
            try
                if ~exist(obj.outputFile, 'file')
                    return;
                end
                info = dir(obj.outputFile);
                if info.bytes < obj.monitorLastPos
                    obj.monitorLastPos = 0;
                end
                fid = fopen(obj.outputFile, 'r');
                if fid == -1
                    return;
                end
                fseek(fid, obj.monitorLastPos, 'bof');
                content = fread(fid, '*char')';
                obj.monitorLastPos = ftell(fid);
                fclose(fid);
                if isempty(content)
                    return;
                end
                if contains(content, 'Max authentication attempts reached. Closing connection.')
                    fprintf('[ERROR] Max authentication attempts reached. Stopping monitor.\n');
                    obj.isRunning = false;
                    try
                        stop(obj.monitorTimer);
                    catch
                    end
                    return;
                end
                obj.processOutput(content);
            catch ME
                fprintf('SmartQC monitor poll error: %s\n', ME.message);
            end
        end
        
        function stoppedByMaxAuth = monitorOutput(obj)
            stoppedByMaxAuth = false;
            fprintf('Monitoring WebSocket output. Press Ctrl+C to stop.\n');
            % Track last read position to avoid reprocessing the whole file
            persistent lastPos
            if isempty(lastPos), lastPos = 0; end
            try
                while obj.isRunning
                    if exist(obj.outputFile, 'file')
                        info = dir(obj.outputFile);
                        % If file shrank (e.g., rotated/truncated), restart from 0
                        if info.bytes < lastPos
                            lastPos = 0;
                        end
                        fid = fopen(obj.outputFile, 'r');
                        if fid ~= -1
                            fseek(fid, lastPos, 'bof');
                            content = fread(fid, '*char')';
                            lastPos = ftell(fid);
                            fclose(fid);
                            if ~isempty(content)
                                if contains(content, 'Max authentication attempts reached. Closing connection.')
                                    fprintf('[ERROR] Max authentication attempts reached. Stopping monitor.\n');
                                    stoppedByMaxAuth = true;
                                    obj.isRunning = false;
                                    break;
                                end
                                obj.processOutput(content);
                            end
                        end
                    end
                    sleepNoGraphics(1); % Check every second without pumping graphics callbacks.
                end
            catch ME
                if strcmp(ME.identifier, 'MATLAB:interrupt') || contains(ME.message, 'Operation terminated by user')
                    fprintf('\nStopping WebSocket monitor...\n');
                    obj.isRunning = false;
                    return;
                end
                fprintf('Monitor stopped due to error: %s\n', ME.message);
                obj.isRunning = false;
            end
        end
        
        function processOutput(obj, content)
            % Process Python output
            persistent outputLineBuffer
            if isempty(outputLineBuffer)
                outputLineBuffer = '';
            end
            if ~isempty(outputLineBuffer)
                content = [outputLineBuffer content];
                outputLineBuffer = '';
            end
            lineParts = regexp(content, '\n', 'split');
            if ~endsWith(content, newline)
                outputLineBuffer = lineParts{end};
                lineParts = lineParts(1:end-1);
            end
            lines = lineParts;
            persistent prevLine
            if isempty(prevLine), prevLine = ''; end
            for i = 1:length(lines)
                line = strtrim(lines{i});
                if isempty(line)
                    continue;
                end
                % Suppress duplicate consecutive lines
                if strcmp(line, prevLine)
                    continue;
                end
                prevLine = line;
                % Parse transaction JSON from Transaction/WebSocket lines.
                % Some runtimes append extra text after the JSON object, so
                % decode only the first balanced JSON object in the line.
                jsonStr = obj.extractFirstJsonObject(line);
                if strlength(string(jsonStr)) > 0 && ...
                        (startsWith(line, 'Transaction:') || startsWith(line, 'WebSocket:') || ...
                        (contains(jsonStr, '"context_id"') && contains(jsonStr, '"data"')))
                    try
                        transaction = jsondecode(jsonStr);
                        obj.transactionCallback(transaction);
                    catch ME
                        fprintf('WebSocket transaction parse skipped: %s\n', ME.message);
                    end
                    continue;
                end
                % Print only non-transaction lines
                fprintf('WebSocket: %s\n', line);
            end
        end

        function jsonStr = extractFirstJsonObject(~, line)
            jsonStr = '';
            try
                s = char(line);
                starts = strfind(s, '{');
                if isempty(starts)
                    return;
                end
                jsonStart = starts(1);
                depth = 0;
                inString = false;
                escaped = false;
                for pos = jsonStart:numel(s)
                    ch = s(pos);
                    if inString
                        if escaped
                            escaped = false;
                        elseif ch == '\'
                            escaped = true;
                        elseif ch == '"'
                            inString = false;
                        end
                    else
                        if ch == '"'
                            inString = true;
                        elseif ch == '{'
                            depth = depth + 1;
                        elseif ch == '}'
                            depth = depth - 1;
                            if depth == 0
                                jsonStr = s(jsonStart:pos);
                                return;
                            end
                        end
                    end
                end
            catch
                jsonStr = '';
            end
        end
        
                 function pythonScript = createPythonScript(obj)
            % Create Python WebSocket script based on working test script
            
            % Convert filters to Python format
            filtersStr = obj.formatFilters();
            
            % Escape Windows backslashes for Python string literals
            outputFilePy = obj.outputFile;
            pidFilePy = obj.pidFile;
            try
                outputFilePy = strrep(outputFilePy, '\', '\\');
            catch
            end
            try
                pidFilePy = strrep(pidFilePy, '\', '\\');
            catch
            end
            
            % Create the Python script using the working test script as base
            pythonScript = sprintf([...
                '#!/usr/bin/env python3\n' ...
                'print("Script started")\n' ...
                '"""SmartQC WebSocket Client for MATLAB Integration"""\n' ...
                '\n' ...
                'import sys\n' ...
                'import json\n' ...
                'import time\n' ...
                'import os\n' ...
                'import importlib\n' ...
                '\n' ...
                '# Robust import of websocket-client\n' ...
                'try:\n' ...
                '    from websocket import WebSocketApp as WSApp\n' ...
                'except Exception:\n' ...
                '    try:\n' ...
                '        import websocket as _ws\n' ...
                '        WSApp = getattr(_ws, \"WebSocketApp\", None)\n' ...
                '        if WSApp is None:\n' ...
                '            import websocket_client as _wsc\n' ...
                '            WSApp = getattr(_wsc, \"WebSocketApp\", None)\n' ...
                '    except Exception:\n' ...
                '        WSApp = None\n' ...
                '\n' ...
                '# Configuration\n' ...
                'SERVER_URL = os.environ.get("SMARTQC_SERVER_URL", "%s")\n' ...
                'USER_ID = os.environ.get("SMARTQC_USER_ID", "%s")\n' ...
                'PRIVATE_KEY = os.environ.get("SMARTQC_PRIVATE_KEY", "")\n' ...
                'FILTERS = %s\n' ...
                'OUTPUT_FILE = "%s"\n' ...
                'PID_FILE = "%s"\n' ...
                '\n' ...
                '# Choose Python lib (smartqc vs contextchain) based on URL\n' ...
                'try:\n' ...
                '    LIB = "smartqc"\n' ...
                '    if "/contextchain/" in SERVER_URL:\n' ...
                '        LIB = "contextchain"\n' ...
                'except Exception:\n' ...
                '    LIB = "smartqc"\n' ...
                'JWT = importlib.import_module(LIB).JWT\n' ...
                '\n' ...
                'def log_message(message):\n' ...
                '    """Log message to output file and print to console"""\n' ...
                '    timestamp = time.strftime("%%Y-%%m-%%d %%H:%%M:%%S")\n' ...
                '    log_entry = f"[{timestamp}] {message}"\n' ...
                '    # no direct console print (MATLAB reads from OUTPUT_FILE)\n' ...
                '    try:\n' ...
                '        with open(OUTPUT_FILE, "a", encoding="utf-8") as f:\n' ...
                '            f.write(log_entry + "\\n")\n' ...
                '            f.flush()\n' ...
                '    except (PermissionError, OSError):\n' ...
                '        pass\n' ...
                '    except Exception as e:\n' ...
                '        print(f"Unexpected error writing to output file: {e}")\n' ...
                '\n' ...
                '# Write PID for MATLAB to manage process\n' ...
                'try:\n' ...
                '    with open(PID_FILE, "w", encoding="utf-8") as pf:\n' ...
                '        pf.write(str(os.getpid()))\n' ...
                'except Exception:\n' ...
                '    pass\n' ...
                'log_message("Python WebSocket client started")\n' ...
                '\n' ...
                '# Read max authentication attempts from environment variable\n' ...
                'try:\n' ...
                '    max_auth_attempts = int(os.environ.get("MAX_AUTH_ATTEMPTS", 3))\n' ...
                'except Exception:\n' ...
                '    max_auth_attempts = 3\n' ...
                'auth_attempts = 0\n' ...
                '\n' ...
                'def on_close(ws, close_status_code, close_msg):\n' ...
                '    log_message(f"Connection closed: status={close_status_code}, msg={close_msg}")\n' ...
                '\n' ...
                'def on_error(ws, error):\n' ...
                '    log_message(f"Error: {error}")\n' ...
                '\n' ...
                'def on_message(ws, message):\n' ...
                '    global auth_attempts\n' ...
                '    try:\n' ...
                '        msg = json.loads(message)\n' ...
                '        # log_message(f"Received message: {json.dumps(msg)}")\n' ...
                '        \n' ...
                '        mtype = msg.get("type")\n' ...
                '        if mtype == "Authorize":\n' ...
                '            log_message("Server requested authorization.")\n' ...
                '            payload = msg.get("payload", {})\n' ...
                '            log_message(f"Authorization message: {payload.get(''message'','''')}")\n' ...
                '            token = JWT.token(USER_ID, PRIVATE_KEY)\n' ...
                '            authorization = {\n' ...
                '                "type": "Authorization",\n' ...
                '                "payload": {\n' ...
                '                    "token": token,\n' ...
                '                    "filters": FILTERS\n' ...
                '                }\n' ...
                '            }\n' ...
                '            ws.send(json.dumps(authorization))\n' ...
                '            log_message("[SUCCESS] Authorization message sent successfully")\n' ...
                '        elif mtype == "Error":\n' ...
                '            log_message(f"Error: {msg.get(''payload'')}")\n' ...
                '            payload = msg.get("payload", "")\n' ...
                '            if isinstance(payload, str) and "Invalid JWT token" in payload:\n' ...
                '                auth_attempts += 1\n' ...
                '                if auth_attempts < max_auth_attempts:\n' ...
                '                    log_message(f"Retrying authentication in 3 seconds... (attempt {auth_attempts+1}/{max_auth_attempts})")\n' ...
                '                    time.sleep(3)\n' ...
                '                    token = JWT.token(USER_ID, PRIVATE_KEY)\n' ...
                '                    ws.send(json.dumps({"type":"Authorization","payload":{"token":token,"filters":FILTERS}}))\n' ...
                '                    log_message("Resent Authorization message.")\n' ...
                '                else:\n' ...
                '                    log_message("Max authentication attempts reached. Closing connection.")\n' ...
                '                    ws.close()\n' ...
                '        elif mtype == "KeepAlive":\n' ...
                '            # keepalive observed\n' ...
                '            pass\n' ...
                '        elif mtype == "Success":\n' ...
                '            log_message("[SUCCESS] Authorized")\n' ...
                '        elif mtype == "Transaction":\n' ...
                '            # emit the transaction JSON on a single line for MATLAB to parse\n' ...
                '            # write transaction line only to file; MATLAB will read it\n' ...
                '            try:\n' ...
                '                with open(OUTPUT_FILE, "a", encoding="utf-8") as f:\n' ...
                '                    f.write("Transaction:")\n' ...
                '                    f.write(json.dumps(msg["payload"]))\n' ...
                '                    f.write("\\n")\n' ...
                '                    f.flush()\n' ...
                '            except Exception:\n' ...
                '                pass\n' ...
                '        else:\n' ...
                '            # unknown message\n' ...
                '            pass\n' ...
                '    except Exception as e:\n' ...
                '        log_message(f"Error processing message: {e}")\n' ...
                '        log_message(f"Raw message: {message}")\n' ...
                '\n' ...
                'def on_open(ws):\n' ...
                '    log_message(f"Connected to {ws.url}")\n' ...
                '\n' ...
                'def main():\n' ...
                '    """Main function"""\n' ...
                '    try:\n' ...
                '        if "/ws" in SERVER_URL:\n' ...
                '            ws_url = SERVER_URL\n' ...
                '        elif SERVER_URL.startswith("http://"):\n' ...
                '            ws_url = SERVER_URL.replace("http://", "ws://") + "/smartqc/ws"\n' ...
                '        elif SERVER_URL.startswith("https://"):\n' ...
                '            ws_url = SERVER_URL.replace("https://", "wss://") + "/smartqc/ws"\n' ...
                '        else:\n' ...
                '            ws_url = f"ws://{SERVER_URL}/smartqc/ws"\n' ...
                '        log_message(f"Connecting to {ws_url}")\n' ...
                '        if WSApp is None:\n' ...
                '            log_message("websocket-client not available. Please install with: pip install websocket-client")\n' ...
                '            return\n' ...
                '        ws = WSApp(\n' ...
                '            ws_url,\n' ...
                '            on_open=on_open,\n' ...
                '            on_message=on_message,\n' ...
                '            on_close=on_close,\n' ...
                '            on_error=on_error\n' ...
                '        )\n' ...
                '        try:\n' ...
                '            ws.run_forever(ping_interval=0)\n' ...
                '        finally:\n' ...
                '            # ensure PID file is removed on exit\n' ...
                '            try:\n' ...
                '                os.remove(PID_FILE)\n' ...
                '            except Exception:\n' ...
                '                pass\n' ...
                '    except KeyboardInterrupt:\n' ...
                '        log_message("Interrupted by user")\n' ...
                '    except Exception as e:\n' ...
                '        log_message(f"Fatal error: {e}")\n' ...
                '        import sys\n' ...
                '        sys.exit(1)\n' ...
                '\n' ...
                'if __name__ == "__main__":\n' ...
                '    try:\n' ...
                '        main()\n' ...
                '    except Exception as e:\n' ...
                '        log_message(f"Startup error: {e}")\n' ...
                '        import sys\n' ...
                '        sys.exit(1)\n' ...
                ], ...
                obj.serverAddress, obj.publicKey, filtersStr, outputFilePy, pidFilePy);
        end

        function envSnapshot = setPythonEnvironment(obj)
            envSnapshot = struct( ...
                'server', getenv('SMARTQC_SERVER_URL'), ...
                'user', getenv('SMARTQC_USER_ID'), ...
                'privateKey', getenv('SMARTQC_PRIVATE_KEY'));
            setenv('SMARTQC_SERVER_URL', char(string(obj.serverAddress)));
            setenv('SMARTQC_USER_ID', char(string(obj.publicKey)));
            setenv('SMARTQC_PRIVATE_KEY', char(string(obj.privateKey)));
        end

        function restorePythonEnvironment(~, envSnapshot)
            setenv('SMARTQC_SERVER_URL', envSnapshot.server);
            setenv('SMARTQC_USER_ID', envSnapshot.user);
            setenv('SMARTQC_PRIVATE_KEY', envSnapshot.privateKey);
        end
        
        function filtersStr = formatFilters(obj)
            % Format filters for Python
            if isempty(obj.filters)
                filtersStr = '[]';
            else
                filtersStr = jsonencode(obj.filters);
            end
        end
                        
        function disconnect(obj)
            % Disconnect from WebSocket
            obj.isRunning = false;

            % Stop background monitor timer (if any).
            try
                if ~isempty(obj.monitorTimer) && isvalid(obj.monitorTimer)
                    stop(obj.monitorTimer);
                    delete(obj.monitorTimer);
                end
            catch
            end
            obj.monitorTimer = [];

            % Kill the Python process. Try the in-memory PID first; only
            % fall back to the PID stored in the pid file if it is a
            % *different* PID we have not already killed (avoids the
            % "ERROR: The process not found" line printed by taskkill on
            % the second attempt).
            killedPids = [];
            if ispc && ~isempty(obj.pythonPid) && isnumeric(obj.pythonPid) && ~isnan(obj.pythonPid)
                killedPids(end+1) = obj.pythonPid;
                SmartQCWebSocketClient.quietTaskkill(obj.pythonPid);
                obj.pythonPid = [];
            end

            try
                if ~isempty(obj.pidFile) && exist(obj.pidFile, 'file')
                    fid = fopen(obj.pidFile, 'r');
                    if fid ~= -1
                        pidStr = strtrim(fread(fid, '*char')');
                        fclose(fid);
                        pidNum = str2double(pidStr);
                        if ispc && ~isnan(pidNum) && ~ismember(pidNum, killedPids)
                            SmartQCWebSocketClient.quietTaskkill(pidNum);
                        end
                    end
                    SmartQCWebSocketClient.quietDelete(obj.pidFile);
                end
            catch
            end

            % Clean up scratch files. The Python WS process may have just
            % been killed; on Windows the OS sometimes still holds the
            % file lock for a fraction of a second, so quietDelete retries
            % a few times and falls back to "del" before giving up
            % silently. This avoids the
            %   "Warning: File not found or permission denied"
            % messages that otherwise leak through delete()'s warning.
            SmartQCWebSocketClient.quietDelete('smartqc_websocket.py');
            SmartQCWebSocketClient.quietDelete(obj.outputFile);
            SmartQCWebSocketClient.quietDelete(obj.errorFile);

            fprintf('Disconnected from WebSocket server\n');
        end
        
        function status = getStatus(obj)
            % Get connection status
            status = struct();
            status.running = obj.isRunning;
            status.server = obj.serverAddress;
            status.filters = obj.filters;
        end
        
        function defaultTransactionHandler(~, transaction)
            % Default transaction handler
            fprintf('\n=== New Transaction ===\n');
            fprintf('ID: %s\n', transaction.id);
            if isfield(transaction, 'data')
                fprintf('Data: %s\n', jsonencode(transaction.data));
            end
            fprintf('=======================\n');
        end
    end

    methods (Static, Access = private)
        function quietTaskkill(pid)
            % Kill a Windows PID without spamming the MATLAB command window
            % with taskkill's stdout/stderr ("SUCCESS: ..." / "ERROR: The
            % process ... not found"). Errors from system() itself are
            % swallowed because the only meaningful failure (already gone)
            % is something we don't care about here.
            if isempty(pid) || ~isnumeric(pid) || isnan(pid)
                return;
            end
            try
                if ispc
                    [status, ~] = system(sprintf( ...
                        'taskkill /F /PID %d >NUL 2>&1', pid));
                else
                    [status, ~] = system(sprintf('kill -9 %d >/dev/null 2>&1', pid));
                end
                if status ~= 0
                    % Process already gone, or never existed - that's fine.
                end
            catch
            end
        end

        function quietDelete(filePath)
            % Best-effort delete that does not warn. MATLAB's built-in
            % delete() emits the warning "File not found or permission
            % denied" (which try/catch cannot suppress, only errors).
            % On Windows the Python WS process we just killed may still
            % hold a moment-long file lock, so we briefly retry and then
            % fall back to "del /Q /F" before giving up silently.
            if isempty(filePath)
                return;
            end
            try
                if isstring(filePath)
                    filePath = char(filePath);
                end
            catch
                return;
            end
            if ~ischar(filePath) || ~exist(filePath, 'file')
                return;
            end

            warningState = warning('off', 'all');
            warningCleanup = onCleanup(@() warning(warningState));

            for attempt = 1:3
                try
                    delete(filePath);
                catch
                end
                if ~exist(filePath, 'file')
                    return;
                end
                if attempt < 3
                    try
                        java.lang.Thread.sleep(100);
                    catch
                    end
                end
            end

            if exist(filePath, 'file') && ispc
                try
                    system(sprintf('del /Q /F "%s" >NUL 2>&1', filePath));
                catch
                end
            end
        end
    end
end
