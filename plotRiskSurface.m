function [outputArg1,outputArg2] = plotRiskSurface(risks,users,objects)
nUsers=length(users);
nObjects=length(objects);
x=1:nUsers;
y=1:nObjects;
[X, Y] = meshgrid(x, y);
surf(X, Y, risks');
xlabel('Users');
ylabel('Objects');
zlabel('Risks');
title('Risk surface');
xticks(x);
xticklabels(users);

yticks(y);
yticklabels(objects);

c = colorbar;
c.Ticks = [0 0.2 0.4 0.6 0.8];
c.TickLabels = {'Slight', 'Possible', 'Substantial', 'High', 'Very high'};
c.Label.String="Risk levels";
end

