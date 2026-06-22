function varargout = job_manager(action, varargin)
%JOB_MANAGER Centralized job management: init, add, update, status, reset.
%   Usage:
%     job_manager('init')
%     jobId = job_manager('add', status)
%     job_manager('update', jobId, status)
%     status = job_manager('status', jobId)
%     job_manager('reset')

persistent jobsDict newJobId
csvFile = 'jobs.csv';

switch lower(action)
    case 'init'
        if exist(csvFile, 'file')
            tmp = fileread(csvFile);
            if ~isempty(tmp)
                jobs = readtable(csvFile);
                jobsID = jobs.id;
                jobsStatus = jobs.status;
                if ~isempty(jobsID)
                    jobsDict = containers.Map(jobsID, jobsStatus);
                    newJobId = max(jobsID) + 1;
                else
                    jobsDict = containers.Map('KeyType', 'int64', 'ValueType', 'int32');
                    newJobId = 1;
                end
            else
                fid = fopen(csvFile, 'a');
                fprintf(fid, 'id,status\n');
                fclose(fid);
                jobsDict = containers.Map('KeyType', 'int64', 'ValueType', 'int32');
                newJobId = 1;
            end
        else
            fid = fopen(csvFile, 'a');
            fprintf(fid, 'id,status\n');
            fclose(fid);
            jobsDict = containers.Map('KeyType', 'int64', 'ValueType', 'int32');
            newJobId = 1;
        end
        if nargout > 0
            varargout{1} = newJobId;
        end
    case 'add'
        if isempty(jobsDict) || isempty(newJobId)
            job_manager('init');
        end
        status = varargin{1};
        jobsDict(newJobId) = status;
        fid = fopen(csvFile, 'a');
        fprintf(fid, '%d,%d\n', newJobId, status);
        fclose(fid);
        varargout{1} = newJobId;
        newJobId = newJobId + 1;
    case 'update'
        jobId = varargin{1};
        status = varargin{2};
        if isKey(jobsDict, jobId)
            jobsDict(jobId) = status;
            % Update CSV (append new status)
            fid = fopen(csvFile, 'a');
            fprintf(fid, '%d,%d\n', jobId, status);
            fclose(fid);
        end
    case 'status'
        jobId = varargin{1};
        if isKey(jobsDict, jobId)
            varargout{1} = jobsDict(jobId);
        else
            varargout{1} = -1; % Not found
        end
    case 'reset'
        jobsDict = containers.Map('KeyType', 'int64', 'ValueType', 'int32');
        newJobId = 1;
        if exist(csvFile, 'file')
            delete(csvFile);
        end
        fid = fopen(csvFile, 'a');
        fprintf(fid, 'id,status\n');
        fclose(fid);
    otherwise
        error('Unknown action for job_manager: %s', action);
end
end 