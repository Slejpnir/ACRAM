function OAF = getOAF(filename,objects)
%GETOAF Summary of this function goes here
%   Detailed explanation goes here
csvData = readtable(filename);
csvNames = csvData.('device');
csvAccessTimes = csvData.('Sum_of_time_spent_sec');
csvAccessTimesSum=sum(csvAccessTimes);

threshold1=0.3;
threshold2=0.2;
threshold3=0.1;
threshold4=0.05;

OAF=strings(length(objects),1);

    for i = 1:length(objects)
        % Find the index of the object in the CSV data
        idx = find(strcmp(csvNames, objects(i)));
        
        if ~isempty(idx)
            % Assign the corresponding access time
            part=csvAccessTimes(idx)/csvAccessTimesSum;
            if part> threshold1
                OAF(i) = "Constantly";
            elseif part> threshold2
                OAF(i) = "Often";
            elseif part> threshold3
                OAF(i) = "Average";
            elseif part> threshold4
                OAF(i) = "Rarely";
            else
                OAF(i) = "Ftf";
            end
        else
            % If no match found, you can choose to assign a default value or leave it empty
            OAF(i) = 'Not Found'; % or NaN, or some other default value
        end
    end

end

