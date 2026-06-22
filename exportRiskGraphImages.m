function filePaths = exportRiskGraphImages(graphArray, usersNames, objectsNames, varargin)
%EXPORTRISKGRAPHIMAGES Export risk digraphs as PNG images.
%   exportRiskGraphImages(graphArray, usersNames, objectsNames, configOrDir)
%   writes every non-empty graph in graphArray.
%
%   exportRiskGraphImages(..., configOrDir, userIdx, objectIdx) writes only
%   the graph for the corresponding user/object pair.

filePaths = strings(0, 1);
if nargin < 3 || isempty(graphArray) || ~iscell(graphArray)
    return;
end

previousFigure = currentFigureOrEmpty();
figureCleanup = onCleanup(@() restoreCurrentFigure(previousFigure));

outputDir = "risk_graphs";
exportMethod = "auto";
if nargin >= 4 && ~isempty(varargin{1})
    if shouldSkipConfigExport(varargin{1})
        fprintf('Risk graph image export disabled. Set config.exportRiskGraphs = true to enable it.\n');
        return;
    end
    outputDir = resolveOutputDir(varargin{1});
    exportMethod = resolveExportMethod(varargin{1});
end

userIdx = [];
objectIdx = [];
if nargin >= 5 && ~isempty(varargin{2})
    userIdx = varargin{2};
end
if nargin >= 6 && ~isempty(varargin{3})
    objectIdx = varargin{3};
end
[nUsers, nObjects] = size(graphArray);
usersNames = normalizeNames(usersNames, nUsers, "User");
objectsNames = normalizeNames(objectsNames, nObjects, "Object");

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

if isempty(userIdx) || isempty(objectIdx)
    userList = 1:nUsers;
    objectList = 1:nObjects;
else
    userList = userIdx;
    objectList = objectIdx;
end

maxExports = numel(userList) * numel(objectList);
filePaths = strings(maxExports, 1);
exportCount = 0;
for u = userList
    if u < 1 || u > nUsers
        continue;
    end
    for o = objectList
        if o < 1 || o > nObjects
            continue;
        end
        riskGraph = graphArray{u, o};
        if isempty(riskGraph)
            continue;
        end
        try
            exportCount = exportCount + 1;
            filePaths(exportCount, 1) = exportOneGraph(riskGraph, usersNames(u), objectsNames(o), u, o, outputDir, exportMethod);
        catch ME
            fprintf('Risk graph image export skipped for user %d, object %d: %s\n', u, o, ME.message);
            exportCount = max(0, exportCount - 1);
        end
        processGuiEvents();
    end
end
filePaths = filePaths(1:exportCount);

if ~isempty(filePaths)
    fprintf('Risk graph images exported: %d file(s) to %s\n', numel(filePaths), char(outputDir));
end
end

function outputDir = resolveOutputDir(configOrDir)
    outputDir = "risk_graphs";
    try
        if isstruct(configOrDir)
            candidateFields = ["graphOutputDir", "riskGraphOutputDir", "graphPicturesDir"];
            for i = 1:numel(candidateFields)
                fieldName = char(candidateFields(i));
                if isfield(configOrDir, fieldName) && ~isempty(configOrDir.(fieldName))
                    outputDir = string(configOrDir.(fieldName));
                    return;
                end
            end
        else
            outputDir = string(configOrDir);
        end
    catch
        outputDir = "risk_graphs";
    end
end

function exportMethod = resolveExportMethod(configOrDir)
    exportMethod = "auto";
    try
        if ~isstruct(configOrDir)
            return;
        end
        candidateFields = ["riskGraphExportMethod", "graphExportMethod", "pngExportMethod"];
        for i = 1:numel(candidateFields)
            fieldName = char(candidateFields(i));
            if isfield(configOrDir, fieldName) && ~isempty(configOrDir.(fieldName))
                exportMethod = lower(strtrim(string(configOrDir.(fieldName))));
                return;
            end
        end
    catch
        exportMethod = "auto";
    end
end

function skip = shouldSkipConfigExport(configOrDir)
    skip = false;
    if ~isstruct(configOrDir)
        return;
    end

    candidateFields = ["exportRiskGraphs", "exportRiskGraphImages", "saveRiskGraphImages"];
    for i = 1:numel(candidateFields)
        fieldName = char(candidateFields(i));
        if isfield(configOrDir, fieldName)
            skip = ~parseLogical(configOrDir.(fieldName));
            return;
        end
    end
end

function value = parseLogical(rawValue)
    try
        if islogical(rawValue) || isnumeric(rawValue)
            value = logical(rawValue);
            return;
        end
        textValue = lower(strtrim(string(rawValue)));
        value = any(textValue == ["true", "on", "yes", "1"]);
    catch
        value = false;
    end
end

function names = normalizeNames(names, nItems, prefix)
    if isempty(names)
        names = prefix + " " + string(1:nItems);
    end
    names = string(names);
    names = names(:);
    if numel(names) < nItems
        for i = numel(names)+1:nItems
            names(i, 1) = prefix + " " + string(i);
        end
    end
end

function filePath = exportOneGraph(riskGraph, userName, objectName, userIdx, objectIdx, outputDir, exportMethod)
    method = effectiveExportMethod(exportMethod);
    ext = exportFileExtension(method);
    fileName = sprintf('risk_graph_user_%03d_object_%03d_%s_%s%s', ...
        userIdx, objectIdx, safeFilePart(userName), safeFilePart(objectName), ext);
    filePath = fullfile(outputDir, fileName);
    tempFilePath = [tempname(char(outputDir)), char(ext)];

    if method == "svg"
        try
            writeGraphSvg(riskGraph, userName, objectName, tempFilePath);
            assertValidGraphSvg(tempFilePath);
            filePath = replaceExportedFile(tempFilePath, filePath);
        catch exportError
            deleteTempFile(tempFilePath);
            rethrow(exportError);
        end
        return;
    end

    warningState = warning('off', 'all');
    warningCleanup = onCleanup(@() warning(warningState));
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 2400 1800], ...
        'InvertHardcopy', 'off', 'HandleVisibility', 'off');
    figCleanup = onCleanup(@() closeFigureIfValid(fig));
    ax = axes(fig, 'Units', 'normalized', 'Position', [0.04 0.23 0.88 0.69]);
    plotGraph(ax, riskGraph);
    title(ax, titleForGraph(riskGraph, userName, objectName), 'Interpreter', 'none');
    addGraphRecommendations(fig, riskGraph);

    try
        exportFigurePng(fig, tempFilePath, method);
        assertValidGraphPng(tempFilePath);
        filePath = replaceExportedFile(tempFilePath, filePath);
    catch exportError
        deleteTempFile(tempFilePath);
        rethrow(exportError);
    end
    clear figCleanup
    clear warningCleanup
end

function exportFigurePng(fig, filePath, exportMethod)
    switch exportMethod
        case "print"
            printFigurePng(fig, filePath);
        case "exportgraphics"
            exportgraphics(fig, filePath, 'Resolution', 150);
        otherwise
            error('exportRiskGraphImages:UnknownExportMethod', ...
                'Unknown risk graph export method "%s". Use "auto", "print", or "exportgraphics".', ...
                char(method));
    end
end

function method = effectiveExportMethod(exportMethod)
    method = normalizeExportMethod(exportMethod);
    if method == "auto"
        method = defaultExportMethodForPlatform();
    end
end

function method = normalizeExportMethod(exportMethod)
    method = lower(strtrim(string(exportMethod)));
    if strlength(method) == 0
        method = "auto";
    end
    if any(method == ["linux", "headless", "native", "native-svg"])
        method = "svg";
    elseif any(method == ["default", "graphics"])
        method = "auto";
    end
end

function method = defaultExportMethodForPlatform()
    method = "exportgraphics";
    try
        if isunix && ~ismac
            method = "svg";
        end
    catch
    end
end

function ext = exportFileExtension(method)
    if method == "svg"
        ext = ".svg";
    else
        ext = ".png";
    end
end

function printFigurePng(fig, filePath)
    try
        set(fig, 'PaperPositionMode', 'auto');
        drawnow limitrate nocallbacks
    catch
    end
    print(fig, char(filePath), '-dpng', '-r150', '-image');
end

function writeGraphSvg(riskGraph, userName, objectName, filePath)
    [x, y, canvasWidth, canvasHeight] = svgGraphLayout(riskGraph);
    [srcIdx, dstIdx] = graphEdgeIndexes(riskGraph);
    nodeNames = graphNodeNames(riskGraph);
    nodeValues = graphNodeValues(riskGraph);
    nodeWidth = 220;
    nodeHeight = 64;

    fid = fopen(filePath, 'w', 'n', 'UTF-8');
    if fid == -1
        error('exportRiskGraphImages:SvgOpenFailed', 'Unable to open %s for SVG export.', filePath);
    end
    cleanup = onCleanup(@() fclose(fid));

    fprintf(fid, '<?xml version="1.0" encoding="UTF-8"?>\n');
    fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n', ...
        canvasWidth, canvasHeight, canvasWidth, canvasHeight);
    fprintf(fid, '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#64748b"/></marker></defs>\n');
    fprintf(fid, '<rect width="100%%" height="100%%" fill="#ffffff"/>\n');
    fprintf(fid, '<text x="%d" y="38" text-anchor="middle" font-family="Arial, Helvetica, sans-serif" font-size="24" font-weight="700" fill="#111827">%s</text>\n', ...
        round(canvasWidth / 2), char(svgEscape(titleForGraph(riskGraph, userName, objectName))));

    for e = 1:numel(srcIdx)
        s = srcIdx(e);
        d = dstIdx(e);
        if s < 1 || d < 1 || s > numel(x) || d > numel(x)
            continue;
        end
        fprintf(fid, '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#64748b" stroke-width="2" marker-end="url(#arrow)" opacity="0.75"/>\n', ...
            x(s), y(s), x(d), y(d));
    end

    for i = 1:numnodes(riskGraph)
        fillColor = svgNodeColor(nodeNames(i), nodeValues(i));
        strokeColor = svgNodeStroke(nodeValues(i));
        left = x(i) - nodeWidth / 2;
        top = y(i) - nodeHeight / 2;
        fprintf(fid, '<rect x="%.1f" y="%.1f" width="%d" height="%d" rx="10" fill="%s" stroke="%s" stroke-width="2"/>\n', ...
            left, top, nodeWidth, nodeHeight, char(fillColor), char(strokeColor));
        labelLines = wrapSvgText(svgNodeLabel(riskGraph, i), 28, 3);
        startY = y(i) - (numel(labelLines) - 1) * 9;
        fprintf(fid, '<text x="%.1f" y="%.1f" text-anchor="middle" font-family="Arial, Helvetica, sans-serif" font-size="13" font-weight="700" fill="#111827">\n', ...
            x(i), startY);
        for lineIdx = 1:numel(labelLines)
            if lineIdx == 1
                dy = 0;
            else
                dy = 18;
            end
            fprintf(fid, '<tspan x="%.1f" dy="%d">%s</tspan>\n', x(i), dy, char(svgEscape(labelLines(lineIdx))));
        end
        fprintf(fid, '</text>\n');
    end

    recommendationLines = wrapRecommendationText(recommendationForGraph(riskGraph), 130, 7);
    recTop = canvasHeight - 118;
    fprintf(fid, '<rect x="40" y="%d" width="%d" height="86" rx="8" fill="#f8fafc" stroke="#cbd5e1"/>\n', ...
        recTop, canvasWidth - 80);
    fprintf(fid, '<text x="60" y="%d" font-family="Arial, Helvetica, sans-serif" font-size="15" font-weight="700" fill="#111827">\n', recTop + 24);
    for i = 1:numel(recommendationLines)
        if i == 1
            dy = 0;
        else
            dy = 18;
        end
        fprintf(fid, '<tspan x="60" dy="%d">%s</tspan>\n', dy, char(svgEscape(recommendationLines(i))));
    end
    fprintf(fid, '</text>\n');
    fprintf(fid, '</svg>\n');
    clear cleanup
end

function [x, y, canvasWidth, canvasHeight] = svgGraphLayout(riskGraph)
    n = numnodes(riskGraph);
    levels = graphNodeLevels(riskGraph);
    nLevels = max(1, max(levels));
    maxPerLevel = 1;
    for level = 1:nLevels
        maxPerLevel = max(maxPerLevel, nnz(levels == level));
    end

    leftMargin = 150;
    topMargin = 115;
    columnSpacing = 285;
    rowSpacing = 112;
    canvasWidth = max(1200, leftMargin * 2 + max(0, nLevels - 1) * columnSpacing);
    canvasHeight = max(820, topMargin + maxPerLevel * rowSpacing + 165);
    x = zeros(n, 1);
    y = zeros(n, 1);
    for level = 1:nLevels
        idx = find(levels == level);
        if isempty(idx)
            continue;
        end
        xValue = leftMargin + (level - 1) * columnSpacing;
        if nLevels == 1
            xValue = canvasWidth / 2;
        end
        groupHeight = (numel(idx) - 1) * rowSpacing;
        firstY = topMargin + max(0, (maxPerLevel - 1) * rowSpacing - groupHeight) / 2;
        for k = 1:numel(idx)
            x(idx(k)) = xValue;
            y(idx(k)) = firstY + (k - 1) * rowSpacing;
        end
    end
end

function levels = graphNodeLevels(riskGraph)
    n = numnodes(riskGraph);
    levels = ones(n, 1);
    [srcIdx, dstIdx] = graphEdgeIndexes(riskGraph);
    if isempty(srcIdx)
        return;
    end
    children = cell(n, 1);
    indegree = zeros(n, 1);
    for e = 1:numel(srcIdx)
        s = srcIdx(e);
        d = dstIdx(e);
        if s < 1 || d < 1 || s > n || d > n
            continue;
        end
        children{s}(end+1) = d;
        indegree(d) = indegree(d) + 1;
    end
    queue = find(indegree == 0)';
    if isempty(queue)
        queue = 1:n;
    end
    indegreeWork = indegree;
    visitedCount = 0;
    head = 1;
    while head <= numel(queue)
        u = queue(head);
        head = head + 1;
        visitedCount = visitedCount + 1;
        for childIdx = 1:numel(children{u})
            v = children{u}(childIdx);
            levels(v) = max(levels(v), levels(u) + 1);
            indegreeWork(v) = indegreeWork(v) - 1;
            if indegreeWork(v) <= 0
                queue(end+1) = v; %#ok<AGROW>
            end
        end
        if visitedCount > n * max(1, numel(srcIdx))
            break;
        end
    end
    levels = min(levels, max(1, n));
end

function [srcIdx, dstIdx] = graphEdgeIndexes(riskGraph)
    srcIdx = zeros(0, 1);
    dstIdx = zeros(0, 1);
    try
        endNodes = riskGraph.Edges.EndNodes;
        if isnumeric(endNodes)
            srcIdx = endNodes(:, 1);
            dstIdx = endNodes(:, 2);
            return;
        end
        endNodes = string(endNodes);
        nodeNames = graphNodeNames(riskGraph);
        for e = 1:size(endNodes, 1)
            s = find(nodeNames == endNodes(e, 1), 1);
            d = find(nodeNames == endNodes(e, 2), 1);
            if ~isempty(s) && ~isempty(d)
                srcIdx(end+1, 1) = s; %#ok<AGROW>
                dstIdx(end+1, 1) = d; %#ok<AGROW>
            end
        end
    catch
        srcIdx = zeros(0, 1);
        dstIdx = zeros(0, 1);
    end
end

function nodeNames = graphNodeNames(riskGraph)
    try
        nodeNames = string(riskGraph.Nodes.Name);
    catch
        nodeNames = "Node " + string((1:numnodes(riskGraph))');
    end
    nodeNames = nodeNames(:);
end

function values = graphNodeValues(riskGraph)
    try
        values = double(riskGraph.Nodes.Value);
    catch
        values = zeros(numnodes(riskGraph), 1);
    end
    values = values(:);
end

function label = svgNodeLabel(riskGraph, idx)
    nodeNames = graphNodeNames(riskGraph);
    nodeValues = graphNodeValues(riskGraph);
    fullName = nodeNames(idx);
    try
        if ismember('FullName', string(riskGraph.Nodes.Properties.VariableNames))
            fullNames = string(riskGraph.Nodes.FullName);
            fullName = fullNames(idx);
        end
    catch
    end
    label = fullName + " (" + formatSvgNodeValue(nodeNames(idx), nodeValues(idx)) + ", " + ...
        linguisticValueForSvgNode(nodeNames(idx), nodeValues(idx)) + ")";
end

function color = svgNodeColor(nodeName, nodeValue)
    if isnan(nodeValue) || nodeValue < 0
        color = "#bfdbfe";
        return;
    end
    severity = normalizedSvgSeverity(nodeName, nodeValue);
    if severity <= 0.5
        t = severity / 0.5;
        rgb = round((1 - t) * [187 247 208] + t * [254 240 138]);
    else
        t = (severity - 0.5) / 0.5;
        rgb = round((1 - t) * [254 240 138] + t * [252 165 165]);
    end
    color = rgbToHex(rgb);
end

function color = svgNodeStroke(nodeValue)
    if isnan(nodeValue) || nodeValue < 0
        color = "#2563eb";
    else
        color = "#475569";
    end
end

function severity = normalizedSvgSeverity(nodeName, nodeValue)
    name = string(nodeName);
    if any(name == ["PML", "SCA"])
        value = double(nodeValue) / 10;
        severity = 1 - value;
    elseif any(name == ["UI", "RAL", "mPA", "ALD", "MPA", "EPH", "ALT", "MPL", "PCR", "SPE", "AML", "AC", "AR", "PR", "NTA", "NTS", "SPI", "AV"])
        severity = 1 - double(nodeValue);
    else
        severity = double(nodeValue);
    end
    severity = max(0, min(1, severity));
end

function valueText = formatSvgNodeValue(nodeName, nodeValue)
    if isnan(nodeValue)
        valueText = "NaN";
        return;
    end
    if nodeValue < 0
        valueText = "missing";
        return;
    end
    if any(string(nodeName) == ["PML", "SCA"])
        rawText = sprintf('%.1f', double(nodeValue));
    else
        rawText = sprintf('%.2f', double(nodeValue));
    end
    rawText = regexprep(rawText, '(\.\d*?)0+$', '$1');
    rawText = regexprep(rawText, '\.$', '');
    valueText = string(rawText);
end

function label = linguisticValueForSvgNode(nodeName, nodeValue)
    if isnan(nodeValue) || nodeValue < 0
        label = "Missing";
        return;
    end
    if any(string(nodeName) == ["PML", "SCA"])
        normalizedValue = double(nodeValue) / 10;
    else
        normalizedValue = double(nodeValue);
    end
    normalizedValue = max(0, min(1, normalizedValue));
    labels = ["Slight", "Possible", "Substantial", "High", "Very high"];
    labelIndex = min(numel(labels), floor(normalizedValue * numel(labels)) + 1);
    label = labels(labelIndex);
end

function lines = wrapRecommendationText(textValue, maxChars, maxLines)
    rawLines = splitlines(string(textValue));
    lines = strings(0, 1);
    for i = 1:numel(rawLines)
        lines = [lines; wrapSvgText(rawLines(i), maxChars, maxLines)]; %#ok<AGROW>
        if numel(lines) >= maxLines
            lines = lines(1:maxLines);
            return;
        end
    end
end

function lines = wrapSvgText(textValue, maxChars, maxLines)
    words = split(strtrim(string(textValue)));
    lines = strings(0, 1);
    currentLine = "";
    for i = 1:numel(words)
        word = string(words(i));
        if strlength(word) == 0
            continue;
        end
        if strlength(currentLine) == 0
            candidate = word;
        else
            candidate = currentLine + " " + word;
        end
        if strlength(candidate) > maxChars && strlength(currentLine) > 0
            lines(end+1, 1) = currentLine; %#ok<AGROW>
            currentLine = word;
        else
            currentLine = candidate;
        end
        if numel(lines) >= maxLines
            lines = lines(1:maxLines);
            return;
        end
    end
    if strlength(currentLine) > 0 && numel(lines) < maxLines
        lines(end+1, 1) = currentLine;
    end
    if isempty(lines)
        lines = "";
    end
end

function textValue = svgEscape(textValue)
    textValue = string(textValue);
    textValue = strrep(textValue, "&", "&amp;");
    textValue = strrep(textValue, "<", "&lt;");
    textValue = strrep(textValue, ">", "&gt;");
    textValue = strrep(textValue, '"', "&quot;");
    textValue = strrep(textValue, "'", "&apos;");
end

function hex = rgbToHex(rgb)
    rgb = max(0, min(255, round(rgb)));
    hex = sprintf('#%02X%02X%02X', rgb(1), rgb(2), rgb(3));
    hex = string(hex);
end

function addGraphRecommendations(fig, riskGraph)
    recommendationText = recommendationForGraph(riskGraph);
    try
        annotation(fig, 'textbox', [0.04 0.025 0.88 0.17], ...
            'String', char(recommendationText), ...
            'Interpreter', 'none', ...
            'EdgeColor', [0.78 0.78 0.78], ...
            'BackgroundColor', [0.98 0.98 0.98], ...
            'Color', [0 0 0], ...
            'FontSize', 16, ...
            'FontWeight', 'bold', ...
            'VerticalAlignment', 'middle', ...
            'FitBoxToText', 'off');
    catch ME
        fprintf('Risk graph recommendation skipped: %s\n', ME.message);
    end
end

function recommendationText = recommendationForGraph(riskGraph)
    recommendationText = "Recommendations: continue monitoring; no controllable factor exceeded the follow-up threshold.";
    try
        threshold = 0.7;
        problems = getProblemsList(riskGraph, threshold);
        if isempty(problems)
            return;
        end
        problems = unique(string(problems), 'stable');
        recommendationText = "Recommendations:" + newline + "- " + strjoin(problems, newline + "- ");
    catch
    end
end

function finalPath = replaceExportedFile(tempFilePath, filePath)
    maxAttempts = 6;
    retryDelaySeconds = 0.25;
    lastError = [];

    for attempt = 1:maxAttempts
        try
            movefile(tempFilePath, filePath, 'f');
            finalPath = filePath;
            return;
        catch ME
            lastError = ME;
            if attempt < maxAttempts
                sleepForRetry(retryDelaySeconds);
            end
        end
    end

    fallbackPath = uniqueFallbackPath(filePath);
    try
        movefile(tempFilePath, fallbackPath, 'f');
        fprintf('Risk graph image target is locked; wrote %s instead of replacing %s (%s)\n', ...
            char(fallbackPath), char(filePath), lastError.message);
        finalPath = fallbackPath;
    catch fallbackError
        error('exportRiskGraphImages:ReplaceFailed', ...
            'Could not replace %s (%s), and fallback write failed: %s', ...
            char(filePath), lastError.message, fallbackError.message);
    end
end

function deleteTempFile(tempFilePath)
    try
        if exist(tempFilePath, 'file')
            delete(tempFilePath);
        end
    catch
    end
end

function fallbackPath = uniqueFallbackPath(filePath)
    [folder, baseName, ext] = fileparts(char(filePath));
    timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
    fallbackPath = fullfile(folder, sprintf('%s_locked_%s%s', baseName, timestamp, ext));

    suffix = 1;
    while exist(fallbackPath, 'file')
        fallbackPath = fullfile(folder, sprintf('%s_locked_%s_%02d%s', baseName, timestamp, suffix, ext));
        suffix = suffix + 1;
    end
end

function sleepForRetry(seconds)
    try
        sleepNoGraphics(seconds);
    catch
        try
            java.lang.Thread.sleep(round(seconds * 1000));
        catch
        end
    end
end

function fig = currentFigureOrEmpty()
    fig = [];
    try
        fig = get(groot, 'CurrentFigure');
    catch
    end
end

function restoreCurrentFigure(fig)
    try
        if ~isempty(fig) && isvalid(fig)
            set(groot, 'CurrentFigure', fig);
        end
    catch
    end
end

function assertValidGraphPng(filePath)
    info = dir(filePath);
    if isempty(info)
        error('exportRiskGraphImages:MissingPng', 'PNG export did not create %s.', filePath);
    end

    minBytes = 50000;
    if info.bytes < minBytes
        error('exportRiskGraphImages:SuspiciousPng', ...
            'PNG export for %s is only %d bytes; refusing to replace graph with likely color-block image.', ...
            filePath, info.bytes);
    end
end

function assertValidGraphSvg(filePath)
    info = dir(filePath);
    if isempty(info)
        error('exportRiskGraphImages:MissingSvg', 'SVG export did not create %s.', filePath);
    end

    minBytes = 1000;
    if info.bytes < minBytes
        error('exportRiskGraphImages:SuspiciousSvg', ...
            'SVG export for %s is only %d bytes; refusing to replace graph with an incomplete file.', ...
            filePath, info.bytes);
    end
    try
        textValue = string(fileread(filePath));
        if ~contains(textValue, "<svg")
            error('exportRiskGraphImages:InvalidSvg', 'SVG export for %s did not contain an <svg> element.', filePath);
        end
    catch ME
        if startsWith(string(ME.identifier), "exportRiskGraphImages:")
            rethrow(ME);
        end
        error('exportRiskGraphImages:InvalidSvg', 'Unable to validate SVG export %s: %s', filePath, ME.message);
    end
end

function titleText = titleForGraph(riskGraph, userName, objectName)
    riskText = "";
    try
        idx = find(string(riskGraph.Nodes.Name) == "ACSRL", 1);
        if ~isempty(idx)
            riskText = " (risk " + string(round(riskGraph.Nodes.Value(idx), 3)) + ")";
        end
    catch
    end
    titleText = "Risk graph: " + string(userName) + " -> " + string(objectName) + riskText;
end

function value = safeFilePart(value)
    value = char(string(value));
    value = regexprep(value, '[<>:"/\\|?*]', '_');
    value = regexprep(value, '\s+', '_');
    value = regexprep(value, '_+', '_');
    value = regexprep(value, '^_+|_+$', '');
    if isempty(value)
        value = 'unnamed';
    end
    maxLen = 80;
    if strlength(string(value)) > maxLen
        value = extractBefore(string(value), maxLen + 1);
        value = char(value);
    end
end

function closeFigureIfValid(fig)
    try
        if ~isempty(fig) && isvalid(fig)
            close(fig);
        end
    catch
    end
end
