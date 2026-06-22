function [G,pageRanks,objectsNames,adjMatrix] = parseXML_ID(filePath,gui)
    %PARSEXML Summary of this function goes here
    %   Detailed explanation goes here
    % Load the XML file
    xmlData = xmlread(filePath);
    
    % Initialize empty lists for object coordinates and connections
    objects = [];
    lines = [];
    % Parse XML for objects and their coordinates
    objectsNode = xmlData.getElementsByTagName('selement'); % Assuming 'object' tags
    for i = 0:objectsNode.getLength-1
        object = objectsNode.item(i);
        id = str2double(object.getElementsByTagName('selementid').item(0).getTextContent());
        name=string(object.getElementsByTagName('label').item(0).getTextContent());
        objects = [objects; id]; % Store coordinates
        objectsNames(i+1)=name;
    end
    
    % Parse XML for lines and their start and end points
    linesNode = xmlData.getElementsByTagName('link'); % Assuming 'line' tags
    for i = 0:linesNode.getLength-1
        line = linesNode.item(i);
        id1 = str2double(line.getElementsByTagName('selementid1').item(0).getTextContent());
        id2 = str2double(line.getElementsByTagName('selementid2').item(0).getTextContent());
        lines = [lines; id1, id2]; % Store line coordinates
    end
    
    % Function to find the closest object
    function idx = findClosestObject(objects, point)
        distances = sqrt(sum((objects - point).^2, 2)); % Euclidean distance
        [~, idx] = min(distances); % Find the object with minimum distance
    end
    
    % Create the adjacency matrix
    n = size(objects, 1);
    adjMatrix = zeros(n); % Initialize n x n adjacency matrix
    
    % Compare line coordinates to object coordinates to build the adjacency matrix
    for i = 1:size(lines, 1)
        % Find closest object to the start point of the line
        startIdx = find(objects(:,1)==lines(i,1));
        % Find closest object to the end point of the line
        endIdx = find(objects(:,1)==lines(i,2));
        
        if startIdx ~= endIdx % Avoid self-loops
            adjMatrix(startIdx, endIdx) = 1; % Set connection from start to end
            adjMatrix(endIdx, startIdx) = 1; % If the connection is bidirectional
        end
    end
    G = graph(adjMatrix);
    pageRanks = centrality(G, 'pagerank');
    if gui=="on"
        h = plot(G,'NodeLabel', objectsNames);
        applyGraphPlotTheme(h);
    end
end

