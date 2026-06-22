function problemsList = getProblemsList(graph,threshold)
%GETPROBLEMSLIST Summary of this function goes here
%   Detailed explanation goes here
problemsList=[];
%firstLayer=[];
%for i=1:numnodes(graph)
%    parents=predecessors(graph,i);
%    if isempty(parents)
%        firstLayer=[firstLayer i];
%    end
%end
function D = graphDepthPeel(G)
% graphDepthPeel  Compute DAG depth by removing zero-indegree layers.

    if ~isa(G,'digraph')
        error('Input must be a digraph.');
    end

    D = 0;
    H = G;  % make a copy
    while numnodes(H)>0
        % find and remove all current roots
        roots = find(indegree(H)==0);
        if isempty(roots)
            error('Graph has a cycle; cannot compute depth.');
        end
        H = rmnode(H, roots);
        D = D + 1;
    end
end

depth=graphDepthPeel(graph);


firstLayer = find(indegree(graph) == 0);
allPaths=cell(length(firstLayer),1);
function path=traverse(index,node, path)
    path = [path; node];
    children = successors(graph, node);
    if isempty(children)
        % If there are no children, it's a leaf node, so print the path
        %pathNames = G.Nodes.Name(path);
        %fprintf('Path from root to leaf: %s\n', strjoin(pathNames, ' -> '));

        pad    = -1 * ones(depth - numel(path),1);% padding to reach D
        fullP  = [path; pad];
        %disp("path");
        %disp(size(fullP));
        %disp("all");
        %disp(size(allPaths{index}));
        allPaths{index}=[allPaths{index} fullP];
    else
        % If there are children, continue traversal
        for j = 1:length(children)
            traverse(index,children(j), path);
        end
    end
end

for i = 1:length(firstLayer)
    if graph.Nodes.Controllable(i)==1
        traverse(i,firstLayer(i), []);
    end
    %tmp=allPaths{i}(allPaths{i}>0);
    %nodesConsidered=graph.Nodes.InvertedValue(allPaths{i}(allPaths{i}>0));
    aboveThreshold= any(graph.Nodes.InvertedValue(allPaths{i}(allPaths{i}>0)) > threshold);
    if aboveThreshold && graph.Nodes.InvertedValue(firstLayer(i))>0 && graph.Nodes.Controllable(firstLayer(i))==1
        problemsList=[problemsList;graph.Nodes.FullName(firstLayer(i))];
    end
end

end

