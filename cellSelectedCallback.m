function cellSelectedCallback(src, event, graph,usersNames,objectsNames,userIdx,objectIdx)
%CELLSELECTEDCALLBACK Summary of this function goes here
%   Detailed explanation goes here
    if nargin < 6 || isempty(userIdx)
        userIdx = event.Indices(1);
    end
    if nargin < 7 || isempty(objectIdx)
        objectIdx = event.Indices(2);
    end
    if isempty(event.Indices) || size(event.Indices, 2) < 2
        return;
    end

    figName=append('Factors affecting risk for ',usersNames(userIdx),' and ',objectsNames(objectIdx));
    % Force a white figure background so the risk graph (which uses warm
    % colormap node fills and dark edges/labels in light mode) renders the
    % same way as the exported PNGs. Without this, the figure inherits
    % MATLAB's default theme which can be dark, leaving captions hard to
    % read against the background.
    fig1 = figure('Name',figName,'Position', [100 100 1200 800], ...
        'NumberTitle', 'off', 'Color', 'w');
    ax = axes('Parent', fig1, 'Units', 'pixels', 'Position', [20 95 1100 670], ...
        'Color', 'w', 'XColor', [0 0 0], 'YColor', [0 0 0]);
    plotGraph(ax,graph);
    threshold=0.7;
    ProblemsList=getProblemsList(graph,threshold);
    details = [getGenRecommendation(src.Data(event.Indices(1),event.Indices(2))); "Main problems:"; "-" + ProblemsList];
    uicontrol(fig1, 'Style', 'edit', 'Max', 2, 'Min', 0, ...
        'String', cellstr(details), 'Position', [20 15 1100 65], ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', [1 1 1], 'ForegroundColor', [0 0 0]);

end
