function updatePlot(lb,~,ax,Risks,usersNames,objectsNames,riskThreshold)
    persistent printedPath
    if isempty(printedPath)
        fprintf('Risk GUI updatePlot path: %s\n', mfilename('fullpath'));
        printedPath = true;
    end

    % Get the selected value from the listbox
    val = getSelectedValue(lb);
    
    % Fully reset the axes (incl. stale HG behavior caches) before drawing
    % the next plot. The reset preserves Units/Position so the layout from
    % plotGUI.m survives.
    safeColorbarOff(ax);
    resetPlotAxes(ax);
    setThemedAxes(ax);
    if nargin < 7 || isempty(riskThreshold)
        riskThreshold = 0;
    end
    filterDisabled = isnumeric(riskThreshold) && isscalar(riskThreshold) && isnan(riskThreshold);

    usersNames = string(usersNames(:));
    objectsNames = string(objectsNames(:));
    nUsers=length(usersNames);
    nObjects=length(objectsNames);
    % Generate x data
    if val=="All"
        if isempty(Risks) || nUsers == 0
            showNoUsersMessage(ax, riskThreshold);
            return;
        end
        plotRiskBars3D(ax, Risks, usersNames, objectsNames);
        colormap(ax, turbo);
        clim(ax,[0 1]);
        safeColorbar(ax, [0 0.2 0.4 0.6 0.8], {'Slight', 'Possible', 'Substantial', 'High', 'Very high'});
    else
        view(ax, 2);
        userMask = usersNames == val;
        if ~any(userMask)
            objectMask = objectsNames == val; % object is selected
            y=Risks(:,objectMask);
            if filterDisabled
                objectUserMask = true(size(y));
            else
                objectUserMask = y > riskThreshold;
            end
            if ~any(objectUserMask) && nUsers == 1
                objectUserMask = true(size(y));
            end
            y = y(objectUserMask);
            usersForPlot = usersNames(objectUserMask);
            nUsersForPlot = numel(usersForPlot);
            x=1:nUsersForPlot;
            selected=0;
            if isempty(y)
                showNoUsersMessage(ax, riskThreshold, val);
                return;
            end
            %xticklabels(ax,'auto');
        else
            y=Risks(userMask,:); % user is selected
            x=1:nObjects;
            selected=1;
        end
        bar(ax, x, y);
        setThemedAxes(ax);
        ylabel(ax,'Risk level');
        ylim(ax, [0 1]);
        grid(ax, 'on');
        box(ax, 'on');
        safeColorbarOff(ax);
        title(ax,strcat("Risk for " , val));
        try
            set(ax, 'FontSize', 9);
            ax.Title.FontSize = 12;
            ax.XLabel.FontSize = 11;
            ax.YLabel.FontSize = 11;
        catch
        end
        if selected==0
            xlim(ax,[0.5 max(1.5, nUsersForPlot + 0.5)]);
            xticks(ax,1:nUsersForPlot);
            xticklabels(ax,usersForPlot);
            xlabel(ax,'Users');
        elseif selected==1
            xticks(ax,1:nObjects);
            xticklabels(ax,objectsNames);
            xtickangle(ax,90)
            xlabel(ax,'Objects');
        end
    end
    % Plot data based on the selected value
end

function showNoUsersMessage(ax, riskThreshold, selectedName)
    if nargin < 3
        selectedName = "";
    end
    view(ax, 2);
    axis(ax, 'off');
    setThemedAxes(ax);
    if isnumeric(riskThreshold) && isscalar(riskThreshold) && isnan(riskThreshold)
        msg = 'No users to show';
    elseif strlength(string(selectedName)) > 0
        msg = sprintf('No users above %.2f for %s', riskThreshold, char(string(selectedName)));
    else
        msg = sprintf('No users above %.2f', riskThreshold);
    end
    text(ax, 0.5, 0.5, msg, ...
        'Units', 'normalized', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontWeight', 'bold', ...
        'Color', axisForeground(ax));
end

function resetPlotAxes(ax)
    % Capture the layout we intentionally pinned in plotGUI.m so we can
    % restore it after cla(...,'reset'). cla 'reset' is required (rather
    % than just delete(allchild(ax))) because switching between bar()
    % (2-D) and bar3() (3-D) on the same axes leaves stale HG "behavior"
    % objects cached internally; the next bar3 call then dies with
    % "Invalid or deleted object" in hggetbehavior.
    savedUnits = '';
    savedPos = [];
    try
        savedUnits = get(ax, 'Units');
        savedPos = get(ax, 'Position');
    catch
    end
    try
        cla(ax, 'reset');
    catch
        % Fallback: at least drop the children if cla 'reset' failed.
        try
            delete(allchild(ax));
        catch
        end
    end
    try
        if ~isempty(savedUnits)
            set(ax, 'Units', savedUnits);
        end
        if ~isempty(savedPos)
            % Pin Position (plotGUI.m intentionally reserves a generous
            % bottom margin for rotated tick labels). Setting OuterPosition
            % afterwards would clobber this, so only restore Position.
            set(ax, 'Position', savedPos);
        end
    catch
    end
    set(ax, ...
        'Visible', 'on', ...
        'NextPlot', 'replacechildren', ...
        'XLimMode', 'auto', ...
        'YLimMode', 'auto', ...
        'ZLimMode', 'auto', ...
        'CLimMode', 'auto', ...
        'XTickMode', 'auto', ...
        'YTickMode', 'auto', ...
        'ZTickMode', 'auto', ...
        'XTickLabelMode', 'auto', ...
        'YTickLabelMode', 'auto', ...
        'ZTickLabelMode', 'auto', ...
        'XDir', 'normal', ...
        'YDir', 'normal', ...
        'ZDir', 'normal');
    title(ax, '');
    xlabel(ax, '');
    ylabel(ax, '');
    zlabel(ax, '');
end

function plotRiskBars3D(ax, Risks, usersNames, objectsNames)
    bars = safeBar3(ax, Risks, 0.75);
    for k = 1:numel(bars)
        zData = get(bars(k), 'ZData');
        set(bars(k), ...
            'CData', zData, ...
            'FaceColor', 'flat', ...
            'EdgeColor', axisForeground(ax), ...
            'LineWidth', 0.4);
    end

    axis(ax, 'tight');
    view(ax, [-42 28]);
    zlim(ax, [0 1]);
    zticks(ax, 0:0.2:1);
    title(ax, 'Risk 3D bars');
    xlabel(ax, 'Objects');
    ylabel(ax, 'Users');
    zlabel(ax, 'Risk level');
    xticks(ax, 1:numel(objectsNames));
    xticklabels(ax, objectsNames);
    xtickangle(ax, 45);
    yticks(ax, 1:numel(usersNames));
    yticklabels(ax, usersNames);
    setThemedAxes(ax);
    grid(ax, 'on');
    box(ax, 'on');
    % Slightly smaller tick font so long object names (e.g.
    % "Smart Plugs 192.168.1.105", "Telemetry2 (On Server-2)") fit the
    % reserved bottom margin without clipping.
    try
        set(ax, 'FontSize', 9);
        ax.Title.FontSize = 11;
        ax.XLabel.FontSize = 11;
        ax.YLabel.FontSize = 11;
        ax.ZLabel.FontSize = 11;
    catch
    end

    [bgColor, fgColor] = axisThemeColors(ax);
    % Pick a translucent background that matches the figure theme so the
    % per-bar value labels stay legible against either the dark 3D back
    % wall or a colored bar face.
    labelBg = [bgColor 0.55];
    for r = 1:size(Risks, 1)
        for c = 1:size(Risks, 2)
            value = Risks(r, c);
            if value > 0
                text(ax, c, r, min(value + 0.04, 1), sprintf('%.2f', value), ...
                    'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'bottom', ...
                    'Color', fgColor, ...
                    'FontSize', 10, ...
                    'FontWeight', 'bold', ...
                    'BackgroundColor', labelBg, ...
                    'Margin', 1, ...
                    'Clipping', 'on');
            end
        end
    end
end

function setThemedAxes(ax)
    try
        [bgColor, fgColor, gridColor] = axisThemeColors(ax);
        set(ax, 'Color', bgColor, 'XColor', fgColor, 'YColor', fgColor, 'ZColor', fgColor);
        ax.Title.Color = fgColor;
        ax.XLabel.Color = fgColor;
        ax.YLabel.Color = fgColor;
        ax.ZLabel.Color = fgColor;
        ax.GridColor = gridColor;
    catch
    end
end

function [bgColor, fgColor, gridColor] = axisThemeColors(ax)
    figColor = defaultColor('DefaultFigureColor', [0.94 0.94 0.94]);
    try
        fig = ancestor(ax, 'figure');
        if ~isempty(fig) && isvalid(fig)
            figColor = get(fig, 'Color');
        end
    catch
    end

    bgColor = defaultColor('DefaultAxesColor', figColor);
    if ischar(bgColor) || isstring(bgColor) || numel(bgColor) ~= 3
        bgColor = figColor;
    end

    if colorBrightness(figColor) < 0.5 && colorBrightness(bgColor) > 0.8
        bgColor = figColor;
    end

    fgColor = defaultColor('DefaultAxesXColor', contrastColor(bgColor));
    if ischar(fgColor) || isstring(fgColor) || numel(fgColor) ~= 3
        fgColor = contrastColor(bgColor);
    end

    if colorBrightness(bgColor) < 0.5 && colorBrightness(fgColor) < 0.5
        fgColor = [0.92 0.92 0.92];
    elseif colorBrightness(bgColor) >= 0.5 && colorBrightness(fgColor) >= 0.5
        fgColor = [0 0 0];
    end

    if colorBrightness(bgColor) < 0.5
        gridColor = min(bgColor + 0.22, 1);
    else
        gridColor = max(bgColor - 0.22, 0);
    end
end

function color = axisForeground(ax)
    [~, color] = axisThemeColors(ax);
end

function color = defaultColor(name, fallback)
    color = fallback;
    try
        rawColor = get(groot, name);
        if isnumeric(rawColor) && numel(rawColor) == 3
            color = rawColor;
        end
    catch
    end
end

function value = colorBrightness(color)
    color = double(color(:)');
    if numel(color) ~= 3
        value = 1;
        return;
    end
    value = (0.299 * color(1)) + (0.587 * color(2)) + (0.114 * color(3));
end

function color = contrastColor(bgColor)
    if colorBrightness(bgColor) < 0.5
        color = [0.92 0.92 0.92];
    else
        color = [0 0 0];
    end
end

function val = getSelectedValue(lb)
    try
        rawValue = lb.Value;
        if isstring(rawValue) || ischar(rawValue)
            val = string(rawValue);
            return;
        end
    catch
    end

    try
        items = string(get(lb, 'String'));
        idx = get(lb, 'Value');
        idx = max(1, min(numel(items), idx(1)));
        val = items(idx);
    catch
        val = "All";
    end
end

function safeColorbar(ax, ticks, tickLabels)
    try
        c = colorbar(ax);
        c.Ticks = ticks;
        c.TickLabels = tickLabels;
        c.Color = axisForeground(ax);
    catch ME
        fprintf('Risk GUI colorbar skipped: %s\n', ME.message);
        safeColorbarOff(ax);
    end
end

function safeColorbarOff(ax)
    try
        colorbar(ax, 'off');
    catch
    end
end

function bars = safeBar3(ax, Risks, width)
    % Wrapper around bar3 that recovers from the intermittent
    % "Invalid or deleted object" error thrown out of hggetbehavior when
    % MATLAB's HG behavior cache for this reused axes references a deleted
    % object (typically left over from a previous bar()/bar3() switch).
    % On failure we fully reset the axes (preserving its Position) and
    % retry once. resetPlotAxes / setThemedAxes are re-applied so the
    % theme survives the reset.
    try
        bars = bar3(ax, Risks, width);
        return;
    catch ME
        if ~contains(ME.message, 'Invalid or deleted object') ...
                && ~contains(ME.identifier, 'invalidObject')
            rethrow(ME);
        end
    end
    try
        resetPlotAxes(ax);
        setThemedAxes(ax);
        bars = bar3(ax, Risks, width);
    catch ME2
        rethrow(ME2);
    end
end
