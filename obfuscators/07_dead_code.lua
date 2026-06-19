local DC = {}
function DC.process(c, o)
    if not o or not o.enabled then return c end
    math.randomseed(os.time())
    local junk = {"local _=0", "local __=1", "do end", "if false then end"}
    c = c:gsub(";", function()
        return "; " .. junk[math.random(1,#junk)]
    end)
    return c
end
return DC