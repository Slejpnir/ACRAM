function transaction = remove_empty_objects(transaction)
    if isstruct(transaction)
        fieldsList = fieldnames(transaction);
        for i = 1:numel(fieldsList)
            field = fieldsList{i};
            if isstruct(transaction.(field))
                transaction.(field) = remove_empty_objects(transaction.(field));
                if isempty(fieldnames(transaction.(field))) % Remove empty structs
                    transaction = rmfield(transaction, field);
                end
            elseif iscell(transaction.(field))
                for j = numel(transaction.(field)):-1:1
                    transaction.(field){j} = remove_empty_objects(transaction.(field){j});
                    if isempty(transaction.(field){j})
                        transaction.(field)(j) = [];
                    end
                end
                if isempty(transaction.(field))
                    transaction = rmfield(transaction, field);
                end
            end
        end
    elseif iscell(transaction)
        for j = numel(transaction):-1:1
            transaction{j} = remove_empty_objects(transaction{j});
            if isempty(transaction{j})
                transaction(j) = [];
            end
        end
    end
end