function riskGuiLayout(fig)
%RISKGUILAYOUT Keep the risk table, selector, and plot inside the window.

    try
        if isempty(fig) || ~isvalid(fig)
            return;
        end

        previousUnits = get(fig, 'Units');
        set(fig, 'Units', 'pixels');
        figPos = get(fig, 'Position');
        set(fig, 'Units', previousUnits);

        figW = max(700, figPos(3));
        figH = max(520, figPos(4));

        margin = 16;
        gap = 10;
        bottomMargin = 26;
        aggregateH = 24;
        tableH = min(120, max(92, round(figH * 0.15)));
        listW = 140;
        plotLeftGap = 72;
        plotRightMargin = 72;
        plotBottom = max(110, bottomMargin + 86);
        thresholdBlockH = 74;

        aggregateY = figH - aggregateH - 6;
        tableY = aggregateY - tableH - 8;
        stopButtonW = 112;
        stopButtonH = 28;
        stopButtonX = figW - margin - stopButtonW;
        stopButtonY = aggregateY - 2;
        resetButtonW = 80;
        resetButtonX = stopButtonX - gap - resetButtonW;
        plotX = margin + listW + plotLeftGap;
        plotH = max(230, tableY - plotBottom - 44);
        plotW = max(360, figW - plotX - plotRightMargin);
        listY = bottomMargin + thresholdBlockH + gap;
        listH = max(120, tableY - listY - gap);

        ax = findRiskGuiObject(fig, 'RiskPlotAxes', 'axes');
        if ~isempty(ax)
            set(ax, 'Units', 'pixels', ...
                'Position', [plotX plotBottom plotW plotH], ...
                'ActivePositionProperty', 'position');
        end

        lb = findRiskGuiObject(fig, 'RiskPlotListbox', 'uicontrol');
        if ~isempty(lb)
            set(lb, 'Units', 'pixels', ...
                'Position', [margin listY listW listH]);
        end

        thresholdLabel = findRiskGuiObject(fig, 'RiskThresholdLabel', 'uicontrol');
        if ~isempty(thresholdLabel)
            set(thresholdLabel, 'Units', 'pixels', ...
                'Position', [margin bottomMargin + 48 76 18]);
        end

        thresholdEdit = findRiskGuiObject(fig, 'RiskThresholdEdit', 'uicontrol');
        if ~isempty(thresholdEdit)
            set(thresholdEdit, 'Units', 'pixels', ...
                'Position', [margin + 78 bottomMargin + 46 listW - 78 24]);
        end

        thresholdSlider = findRiskGuiObject(fig, 'RiskThresholdSlider', 'uicontrol');
        if ~isempty(thresholdSlider)
            set(thresholdSlider, 'Units', 'pixels', ...
                'Position', [margin bottomMargin + 22 listW 20]);
        end

        thresholdCount = findRiskGuiObject(fig, 'RiskThresholdCount', 'uicontrol');
        if ~isempty(thresholdCount)
            set(thresholdCount, 'Units', 'pixels', ...
                'Position', [margin bottomMargin listW 18]);
        end

        riskTable = findRiskGuiObject(fig, 'RiskTable', 'uitable');
        if ~isempty(riskTable)
            set(riskTable, 'Units', 'pixels', ...
                'Position', [margin tableY figW - (2 * margin) tableH]);
        end

        riskLabel = findRiskGuiObject(fig, 'RiskAggregateLabel', 'uicontrol');
        if ~isempty(riskLabel)
            set(riskLabel, 'Units', 'pixels', ...
                'Position', [margin aggregateY figW - (3 * margin) - stopButtonW - resetButtonW - gap aggregateH]);
        end

        resetButton = findRiskGuiObject(fig, 'RiskResetButton', 'uicontrol');
        if ~isempty(resetButton)
            set(resetButton, 'Units', 'pixels', ...
                'Position', [resetButtonX stopButtonY resetButtonW stopButtonH]);
        end

        stopButton = findRiskGuiObject(fig, 'RiskStopButton', 'uicontrol');
        if ~isempty(stopButton)
            set(stopButton, 'Units', 'pixels', ...
                'Position', [stopButtonX stopButtonY stopButtonW stopButtonH]);
        end

        if ~isempty(lb)
            try
                uistack(lb, 'top');
            catch
            end
        end
        riskGuiApplyThreshold(fig);
    catch ME
        fprintf('Risk GUI layout skipped: %s\n', ME.message);
    end
end

function obj = findRiskGuiObject(fig, tag, objectType)
    try
        obj = findobj(fig, 'Tag', tag);
        if ~isempty(obj)
            obj = obj(1);
            return;
        end
    catch
    end

    try
        obj = getappdata(fig, tag);
        if ~isempty(obj) && isvalid(obj)
            return;
        end
    catch
    end

    try
        switch objectType
            case 'axes'
                if strcmp(tag, 'RiskPlotAxes')
                    obj = getappdata(fig, 'RiskPlotAxes');
                else
                    obj = [];
                end
            case 'uicontrol'
                if strcmp(tag, 'RiskPlotListbox')
                    obj = getappdata(fig, 'RiskPlotListbox');
                else
                    obj = [];
                end
            otherwise
                obj = [];
        end
        if isempty(obj) || ~isvalid(obj)
            obj = [];
        end
    catch
        obj = [];
    end
end
