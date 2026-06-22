function plotGraph(ax,riskGraph)
%PLOTGRAPH Summary of this function goes here
%   Detailed explanation goes here
    cla(ax,'reset');
    nodeLabels = nodeLabelsForGraph(riskGraph);
    h=plot(ax,riskGraph,'NodeLabel', nodeLabels);
    setLightGraphTheme(ax);
    % Derive label/edge colors from the active theme so captions stay
    % readable on both light and dark figure backgrounds. Hard-coding black
    % made node labels disappear on dark-mode figures.
    [bgColor, fgColor] = graphThemeColors(ax);
    edgeColor = blendColor(fgColor, bgColor, 0.65);
    try
        h.NodeLabelColor = fgColor;
        try
            h.EdgeLabelColor = fgColor;
        catch
        end
        h.EdgeColor = edgeColor;
        h.LineWidth = 1.2;
        h.NodeFontSize = 11;
    catch
    end

    colormapName = 'jet'; % Choose a colormap, e.g., 'jet', 'parula', 'hot', etc.
    colormapValues = colormap(ax,colormapName);
    numColors = size(colormapValues, 1);
    startIdx = round(numColors * 1/2); % Starting index (e.g., 1/3 of the colormap)
    endIdx = numColors; % Ending index (e.g., 2/3 of the colormap)
    customColormapValues = colormapValues(startIdx:endIdx, :);
    customNumColors = size(customColormapValues, 1);

    for i = 1:numnodes(riskGraph)
        nodeName = riskGraph.Nodes.Name{i};
        nodeValue = riskGraph.Nodes.Value(i);

        if nodeValue == -1
            % Use default color and size for missing nodes
            highlight(h, i, 'NodeColor', 'b', 'MarkerSize', 4);
            continue;
        end

        switch nodeName
            case {"UI","RAL","mPA", "ALD", "MPA", "EPH","ALT", "MPL","PCR", "SPE","AML","AC","AR","PR","NTA","NTS","SPI","AV"} %0 - bad, 1 - good
                colorIndice = round((1-nodeValue )* (customNumColors - 1)) + 1;
            case {"SAB-UI","SAB","PRM","PRM-PR","NT-AV","AML-AC","AML-AR","EM","AL","VI","VC","VA","OAF","ISL","OAF-VA","ISL-VC","AS","ACSRL","S","LOI","OAB","OAB-AR","OAB-AC","OAB-AR-AC"}
                colorIndice = round((nodeValue )* (customNumColors - 1)) + 1;%0- good, 1 - bad
            case {"PML","SCA"}
                colorIndice = round((1-nodeValue/10) * (customNumColors - 1)) + 1;% 0 - bad, 10 - good
            otherwise
                colorIndice = 1; % fallback
        end
        colorIndice = max(1, min(customNumColors, colorIndice));
        nodeColor = customColormapValues(colorIndice, :);
        highlight(h, i, 'NodeColor', nodeColor, 'MarkerSize', markerSizeForNode(nodeName, nodeValue));
    end
    colormap(ax,customColormapValues);
    clim(ax,[0.5 1]);
    safeGraphColorbar(ax);
    setLightGraphTheme(ax);
end

function nodeLabels = nodeLabelsForGraph(riskGraph)
    nodeLabels = strings(numnodes(riskGraph), 1);
    for i = 1:numnodes(riskGraph)
        nodeName = string(riskGraph.Nodes.Name{i});
        nodeValue = riskGraph.Nodes.Value(i);
        nodeLabels(i) = string(riskGraph.Nodes.FullName(i)) + " (" + ...
            formatNodeValue(nodeName, nodeValue) + ", " + ...
            linguisticValueForNode(nodeName, nodeValue) + ")";
    end
end

function valueText = formatNodeValue(nodeName, nodeValue)
    if isnan(nodeValue)
        valueText = "NaN";
        return;
    end
    if nodeValue < 0
        valueText = "missing";
        return;
    end

    if any(nodeName == ["PML", "SCA"])
        rawText = sprintf('%.1f', double(nodeValue));
    else
        rawText = sprintf('%.2f', double(nodeValue));
    end
    rawText = regexprep(rawText, '(\.\d*?)0+$', '$1');
    rawText = regexprep(rawText, '\.$', '');
    valueText = string(rawText);
end

function label = linguisticValueForNode(nodeName, nodeValue)
    if isnan(nodeValue) || nodeValue < 0
        label = "Missing";
        return;
    end

    switch nodeName
        case {"PML", "SCA"}
            normalizedValue = double(nodeValue) / 10;
        otherwise
            normalizedValue = double(nodeValue);
    end
    normalizedValue = max(0, min(1, normalizedValue));
    labels = ["Slight", "Possible", "Substantial", "High", "Very high"];
    labelIndex = min(numel(labels), floor(normalizedValue * numel(labels)) + 1);
    label = labels(labelIndex);
end

function markerSize = markerSizeForNode(nodeName, nodeValue)
    if isnan(nodeValue) || nodeValue < 0
        markerSize = 4;
        return;
    end

    switch string(nodeName)
        case {"PML", "SCA"}
            normalizedValue = nodeValue / 10;
        otherwise
            normalizedValue = nodeValue;
    end
    normalizedValue = max(0, min(1, double(normalizedValue)));
    markerSize = 5 + 17 * normalizedValue;
end

function setLightGraphTheme(ax)
    try
        [bgColor, fgColor] = graphThemeColors(ax);
        set(ax, 'Color', bgColor, 'XColor', fgColor, 'YColor', fgColor);
        ax.Title.Color = fgColor;
        try
            ax.Parent.Color = bgColor;
        catch
        end
    catch
    end
end

function [bgColor, fgColor] = graphThemeColors(ax)
    isHiddenExport = false;
    figColor = defaultColor('DefaultFigureColor', [0.94 0.94 0.94]);
    try
        fig = ancestor(ax, 'figure');
        if ~isempty(fig) && isvalid(fig)
            isHiddenExport = strcmpi(get(fig, 'Visible'), 'off');
            figColor = get(fig, 'Color');
        end
    catch
    end

    if isHiddenExport
        bgColor = [1 1 1];
        fgColor = [0 0 0];
        return;
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

function safeGraphColorbar(ax)
    try
        c = colorbar(ax);
        customLabels = {'Positive impact', 'Negative impact'};
        c.Ticks = linspace(0.5, 1, numel(customLabels));
        c.TickLabels = customLabels;
        [~, fgColor] = graphThemeColors(ax);
        c.Color = fgColor;
    catch ME
        fprintf('Risk graph colorbar skipped: %s\n', ME.message);
    end
end

function color = blendColor(a, b, weight)
    a = double(a(:)');
    b = double(b(:)');
    if numel(a) ~= 3 || numel(b) ~= 3
        color = a;
        return;
    end
    weight = max(0, min(1, double(weight)));
    color = weight * a + (1 - weight) * b;
    color = max(0, min(1, color));
end
