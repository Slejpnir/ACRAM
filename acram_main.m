function acram_main()
%ACRAM_MAIN Windows entrypoint that opens a console UI and runs the app
    % Start the UI only; user will press Run to execute the main logic
    try
        console_viewer('start');
    catch
    end
    % Block until the console UI is closed to keep the app alive
    try
        fig = [];
        try
            fig = evalin('base','ACRAM_CONSOLE_FIG');
        catch
        end
        if ~isempty(fig) && ishghandle(fig)
            waitfor(fig);
        else
            % fallback idle loop
            while true
                pause(0.5);
                try
                    fig = evalin('base','ACRAM_CONSOLE_FIG');
                catch
                    fig = [];
                end
                if isempty(fig) || ~ishghandle(fig)
                    break;
                end
            end
        end
    catch
    end
end


