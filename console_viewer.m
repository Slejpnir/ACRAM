function console_viewer(action)
%CONSOLE_VIEWER Simple Windows console UI that mirrors diary output
%   console_viewer('start') creates a UI window with a text area and tails
%   the diary log, effectively rerouting console output to the window.
%   console_viewer('stop') stops tailing and closes the UI.

    persistent fig txt timerObj logPath lastPos cfgEdit

    if nargin < 1; action = 'start'; end

    switch lower(action)
        case 'start'
            if ~ispc
                return;
            end
            try
                if isempty(logPath) || ~ischar(logPath)
                    logPath = fullfile(pwd, 'runtime_console.log');
                end
                % Start diary to capture all subsequent console output
                try
                    diary off; % reset if needed
                catch
                end
                try
                    if exist(logPath, 'file')
                        delete(logPath);
                    end
                catch
                end
                diary(logPath);
                diary on;

                if isempty(fig) || ~isvalid(fig)
                    fig = uifigure('Name','ACRAM Console','Position',[100 100 1000 700]);
                    % expose fig in base to allow waitfor
                    try
                        assignin('base','ACRAM_CONSOLE_FIG', fig);
                    catch
                    end
                    % Controls row
                    uilabel(fig, 'Text','Config:', 'Position',[10 660 50 22]);
                    cfgEdit = uieditfield(fig, 'text', 'Position',[65 660 670 22]);
                    % Initialize config path from base workspace if present
                    try
                        if evalin('base','exist(''configFileName'',''var'')')
                            cfgEdit.Value = char(evalin('base','configFileName'));
                        end
                    catch
                    end
                    uibutton(fig, 'Text','Browse...', 'Position',[750 660 80 22], ...
                        'ButtonPushedFcn', @browseCfg);
                    uibutton(fig, 'Text','Run', 'Position',[840 660 70 22], ...
                        'ButtonPushedFcn', @runMain);
                    % Stop button to the right of Run
                    uibutton(fig, 'Text','Stop', 'Position',[920 660 70 22], ...
                        'ButtonPushedFcn', @stopRun);
                    % Console text area
                    txt = uitextarea(fig, 'Position',[10 10 980 640], 'Editable','off');
                    txt.FontName = 'Consolas';
                end
                lastPos = 0;
                % Create/update timer to tail the diary file
                if isempty(timerObj) || ~isvalid(timerObj)
                    timerObj = timer('ExecutionMode','fixedSpacing', 'Period', 1.0, ...
                        'TimerFcn', @tickTail, 'Name','ACRAMConsoleTail');
                end
                start(timerObj);
            catch
            end

        case 'stop'
            try
                diary off;
            catch
            end
            try
                if ~isempty(timerObj) && isvalid(timerObj)
                    stop(timerObj);
                    delete(timerObj);
                end
            catch
            end
            timerObj = [];
            try
                if ~isempty(fig) && isvalid(fig)
                    delete(fig);
                end
            catch
            end
            fig = [];
            txt = [];
            lastPos = 0;
        otherwise
            % no-op
    end

    function tickTail(~,~)
        try
            if isempty(logPath) || ~exist(logPath,'file') || isempty(txt) || ~isvalid(txt)
                return;
            end
            fid = fopen(logPath, 'r');
            if fid == -1
                return;
            end
            fseek(fid, 0, 'eof');
            fileSize = ftell(fid);
            if fileSize > lastPos
                fseek(fid, lastPos, 'bof');
                newData = fread(fid, fileSize - lastPos, '*char')';
                lastPos = ftell(fid);
                fclose(fid);
                % Append to UI text
                try
                    txt.Value = [txt.Value; string(newData)];
                    % Auto-scroll
                    drawnow limitrate;
                catch
                end
            else
                fclose(fid);
            end
        catch
        end
    end

    function browseCfg(~,~)
        try
            [f,p] = uigetfile({'*.json','Config JSON (*.json)'}, 'Select Config');
            if isequal(f,0)
                return;
            end
            fullp = fullfile(p,f);
            if ~isempty(cfgEdit) && isvalid(cfgEdit)
                cfgEdit.Value = fullp;
            end
            try
                assignin('base','configFileName', fullp);
            catch
            end
        catch
        end
    end

    function runMain(~,~)
        % Push config path into base and run main
        try
            cfgArg = '';
            if ~isempty(cfgEdit) && isvalid(cfgEdit) && strlength(string(cfgEdit.Value)) > 0
                cfgArg = char(cfgEdit.Value);
            end
        catch
            cfgArg = '';
        end
        try
            if ~isempty(cfgArg)
                EvaluateRisk_main_enhanced(cfgArg);
            else
                EvaluateRisk_main_enhanced();
            end
        catch ME
            try
                disp(getReport(ME));
            catch
            end
        end
    end

    function stopRun(~,~)
        % Attempt to stop real-time monitoring and background work
        try
            real_time_monitor('stop');
        catch
        end
        % Try to cancel parallel pool jobs if any
        try
            pool = gcp('nocreate');
            if ~isempty(pool)
                cancel(pool.FevalQueue.Jobs);
            end
        catch
        end
        % Provide visual feedback
        try
            if ~isempty(txt) && isvalid(txt)
                txt.Value = [txt.Value; "[INFO] Stop requested."];
            end
        catch
        end
    end
end
