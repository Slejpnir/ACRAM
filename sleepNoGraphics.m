function sleepNoGraphics(seconds)
%SLEEPNOGRAPHICS Wait without pumping MATLAB graphics callbacks.
    if nargin < 1 || isempty(seconds)
        seconds = 0;
    end
    seconds = max(0, double(seconds));
    if seconds == 0
        return;
    end

    try
        java.lang.Thread.sleep(int64(round(seconds * 1000)));
    catch
        if ispc
            system(sprintf('powershell -NoProfile -Command "Start-Sleep -Milliseconds %d"', round(seconds * 1000)));
        else
            system(sprintf('sleep %.3f', seconds));
        end
    end
end
