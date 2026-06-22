function applyGraphPlotTheme(h, ax)
%APPLYGRAPHPLOTTHEME Recolor a GraphPlot's captions for the active theme.
%   applyGraphPlotTheme(h) takes the handle returned by plot(G,...) and
%   updates NodeLabelColor / EdgeLabelColor / EdgeColor (and the parent
%   axes' tick / title colors) so node captions remain readable on dark
%   figure backgrounds (e.g. MATLAB's dark theme). Without this, MATLAB's
%   default black NodeLabelColor renders black-on-black on dark figures.
%
%   applyGraphPlotTheme(h, ax) lets callers pass an explicit axes handle.
%
%   This helper does not change the figure or axes background; only the
%   text/edge colors are adjusted.

    if nargin < 1 || isempty(h)
        return;
    end
    if nargin < 2 || isempty(ax)
        try
            ax = ancestor(h, 'axes');
        catch
            ax = [];
        end
    end

    [bgColor, fgColor] = themeColors(ax);
    edgeColor = blendColor(fgColor, bgColor, 0.65);

    try
        h.NodeLabelColor = fgColor;
    catch
    end
    try
        h.EdgeLabelColor = fgColor;
    catch
    end
    try
        h.EdgeColor = edgeColor;
    catch
    end

    if ~isempty(ax) && isvalid(ax)
        try
            set(ax, 'XColor', fgColor, 'YColor', fgColor, 'ZColor', fgColor);
        catch
        end
        try
            ax.Title.Color = fgColor;
        catch
        end
        try
            ax.XLabel.Color = fgColor;
            ax.YLabel.Color = fgColor;
            ax.ZLabel.Color = fgColor;
        catch
        end
    end
end

function [bgColor, fgColor] = themeColors(ax)
    figColor = [0.94 0.94 0.94];
    try
        rawFigColor = get(groot, 'DefaultFigureColor');
        if isnumeric(rawFigColor) && numel(rawFigColor) == 3
            figColor = rawFigColor;
        end
    catch
    end
    try
        fig = ancestor(ax, 'figure');
        if ~isempty(fig) && isvalid(fig)
            figColor = get(fig, 'Color');
        end
    catch
    end

    bgColor = figColor;
    try
        if ~isempty(ax) && isvalid(ax)
            axColor = get(ax, 'Color');
            if isnumeric(axColor) && numel(axColor) == 3
                bgColor = axColor;
            end
        end
    catch
    end

    if colorBrightness(bgColor) < 0.5
        fgColor = [0.92 0.92 0.92];
    else
        fgColor = [0 0 0];
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
