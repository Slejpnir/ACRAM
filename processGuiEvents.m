function processGuiEvents()
%PROCESSGUIEVENTS Let MATLAB service GUI callbacks during long work.

    try
        drawnow limitrate;
    catch
    end
end
