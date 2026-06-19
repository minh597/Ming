local NumberEncoding = {}
local RandomUtils = require("libs.random_utils")
local TransformUtils = require("libs.transform_utils")

function NumberEncoding.process(code, config)
    if not config or not config.enabled then return code end
    
    local result = {}
    
    for line in code:gmatch("[^\n]+") do
        local processed = line:gsub("(%D)(%d+)(%D)", function(prefix, num, suffix)
            if should_encode(num, config) then
                return prefix .. encode_number(tonumber(num), config) .. suffix
            end
            return prefix .. num .. suffix
        end)
        
        processed = processed:gsub("^(%d+)(%D)", function(num, suffix)
            if should_encode(num, config) then
                return encode_number(tonumber(num), config) .. suffix
            end
            return num .. suffix
        end)
        
        processed = processed:gsub("(%D)(%d+)$", function(prefix, num)
            if should_encode(num, config) then
                return prefix .. encode_number(tonumber(num), config)
            end
            return prefix .. num
        end)
        
        table.insert(result, processed)
    end
    
    return table.concat(result, "\n")
end

function should_encode(num_str, config)
    local n = tonumber(num_str)
    if not n then return false end
    if math.abs(n) <= 1 then return false end
    if n == math.floor(n) and config.encode_integers then
        return RandomUtils.random_bool()
    end
    if n ~= math.floor(n) and config.encode_floats then
        return RandomUtils.random_bool()
    end
    return false
end

function encode_number(n, config)
    local depth = config.max_expression_depth or 4
    return TransformUtils.create_number_expression_deep(math.floor(n), depth)
end

return NumberEncoding