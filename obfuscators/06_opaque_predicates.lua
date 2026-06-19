local OP = {}
function OP.process(c, o)
    if not o or not o.enabled then return c end
    math.randomseed(os.time())
    local function gn()
        local n1, n2, n3 = math.random(1,1000), math.random(1,1000), math.random(1,2000)
        return "if " .. n1 .. "+" .. n2 .. "==" .. n3 .. " then end\n"
    end
    c = c:gsub("(function%s+[a-zA-Z_][a-zA-Z0-9_]*%s*%([^%)]*%))", function(f)
        return gn() .. f
    end)
    return c
end
return OP