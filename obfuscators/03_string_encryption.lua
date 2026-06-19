local SE = {}
function SE.process(c, o)
    if not o or not o.enabled then return c end
    math.randomseed(os.time())
    local k = math.random(1, 255)
    local dn = "_e" .. string.format("%04d", math.random(1,9999))
    local dec = "local " .. dn .. "=function(s)local r={}for i=1,#s do r[i]=string.char(string.byte(s,i)~" .. k .. ")end return table.concat(r)end"
    local cnt = 0
    c = c:gsub('"([^"]*)"', function(s)
        if #s >= 3 then
            cnt = cnt + 1
            local e = {}
            for i = 1, #s do
                e[i] = string.char(string.byte(s,i) ~ k)
            end
            local enc = table.concat(e)
            local h = {}
            for i = 1, #enc do
                h[i] = string.format("\\x%02x", string.byte(enc,i))
            end
            return dn .. '("' .. table.concat(h) .. '")'
        end
        return '"' .. s .. '"'
    end)
    c = c:gsub("'([^']*)'", function(s)
        if #s >= 3 then
            cnt = cnt + 1
            local e = {}
            for i = 1, #s do
                e[i] = string.char(string.byte(s,i) ~ k)
            end
            local enc = table.concat(e)
            local h = {}
            for i = 1, #enc do
                h[i] = string.format("\\x%02x", string.byte(enc,i))
            end
            return dn .. "('" .. table.concat(h) .. "')"
        end
        return "'" .. s .. "'"
    end)
    if cnt > 0 then
        c = dec .. "\n" .. c
    end
    return c
end
return SE