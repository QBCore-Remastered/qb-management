function deepcopy(orig, copies)
    copies = copies or {}

    local orig_type = type(orig)
    local copy

    if orig_type == 'table' then
        if copies[orig] then
            copy = copies[orig]
        else
            copy = {}
            copies[orig] = copy

            for orig_key, orig_value in next, orig, nil do
                copy[deepcopy(orig_key, copies)] = deepcopy(orig_value, copies)
            end

            setmetatable(copy, deepcopy(getmetatable(orig), copies))
        end
    else -- number, string, boolean, etc
        copy = orig
    end

    return copy
end

function comma_value(amount)
    local formatted = amount
    local numChanged

    repeat
        formatted, numChanged = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
    until numChanged == 0

    return formatted
end