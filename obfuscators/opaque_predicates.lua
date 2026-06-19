local OpaquePredicates = {}

local RandomUtils   = require("libs.random_utils")
local TransformUtils = require("libs.transform_utils")

local function rvar(len)   return RandomUtils.random_variable_name(len or 6) end
local function rint(a, b)  return RandomUtils.random_int(a, b) end
local function rfloat()    return RandomUtils.random_float() end
local function rbool()     return RandomUtils.random_bool() end

local function indent(code, n)
    local pad = string.rep(" ", n or 4)
    return (code:gsub("([^\n]+)", pad .. "%1"))
end

local TRUE_PREDICATES = {
    function()
        local n = rint(1,999)
        return string.format("((%d * 0) == 0)", n)
    end,
    function()
        local n = rint(1,999)
        return string.format("(((%d + 1) - %d) == 1)", n, n)
    end,
    function()
        local n = rint(2,50)
        return string.format("(%d ^ 2 == %d)", n, n*n)
    end,
    function()
        local a = rint(2,10); local b = rint(2,10)
        return string.format("(%d %% %d == %d)", a, b, a % b)
    end,
    function()
        local n = rint(1,100)
        return string.format("((%d * 2) ~= (%d * 2 + 1))", n, n)
    end,
    function()
        local n = rint(0,100)
        return string.format("(math.floor(%d.0) == %d)", n, n)
    end,
    function()
        local n = rint(1,100)
        return string.format("(math.abs(-%d) == %d)", n, n)
    end,
    function()
        local n = rint(1,100)
        return string.format("(math.max(%d, %d) == %d)", n, n-1, n)
    end,
    function()
        local n = rint(1, 0xFFFF)
        return string.format("((%d & 0) == 0)", n)
    end,
    function()
        local n = rint(1, 0xFFFF)
        return string.format("((%d | %d) == %d)", n, n, n)
    end,
    function()
        local n = rint(1, 0xFFFF)
        return string.format("((%d ~ %d) == 0)", n, n)
    end,
    function()
        local n = rint(0, 15)
        return string.format("((1 << %d) == %d)", n, 1 << n)
    end,
    function()
        local n = rint(1, 0xFF)
        return string.format("((~%d & 0xFF) == %d)", n, (~n) & 0xFF)
    end,
    function()
        local a = rint(1, 255); local b = rint(1, 255)
        return string.format("((%d & %d) | (%d & %d) == (%d | %d) & (%d | %d))",
            a, b, a, (~b & 0xFF),
            a, b, a, (~b & 0xFF))
    end,
    function()
        local exp = rint(1, 14); local n = 1 << exp
        return string.format("((%d & %d) == 0)", n, n-1)
    end,
    function()
        local x = rint(1, 0xFF); local y = rint(1, 0xFF)
        local lhs  = x + y
        local rhs  = (x & y) * 2 + (x ~ y)
        return string.format("(%d == %d)", lhs, rhs)
    end,
    function()
        local x = rint(10, 200); local y = rint(1, x-1)
        return string.format("((%d - %d) == %d)", x, y, x - y)
    end,
    function()
        local a = rint(1, 0xFF); local b = rint(1, 0xFF)
        return string.format("((%d | %d) == (%d & %d) + (%d ~ %d))",
            a, b, a, b, a, b)
    end,
    function()
        local a = rint(1, 0x7F); local b = rint(1, 0x7F)
        return string.format("((%d & %d) == ((%d + %d) - (%d | %d)))",
            a, b, a, b, a, b)
    end,
    function()
        local s = rvar(rint(3,8))
        return string.format("(#%q == %d)", s, #s)
    end,
    function() return "type('') == 'string'" end,
    function() return "string.len('xy') == 2" end,
    function()
        local s = rvar(rint(4,10))
        return string.format("(string.sub(%q, 1, 1) == %q)", s, s:sub(1,1))
    end,
    function()
        local s = rvar(rint(4,10))
        return string.format("(string.upper(string.lower(%q)) == string.upper(%q))", s, s)
    end,
    function() return "string.rep('a', 0) == ''" end,
    function() return "(string.byte('A') == 65)" end,
    function() return "(string.char(48) == '0')" end,
    function() return "type({}) == 'table'" end,
    function() return "#{1,2,3} == 3" end,
    function()
        local n = rint(2, 8)
        local t = {}; for i=1,n do t[i]=tostring(i) end
        return string.format("(#{%s} == %d)", table.concat(t, ","), n)
    end,
    function()
        local v = rvar(); local k = rvar(4); local n = rint(1,99)
        return string.format(
            "(function() local %s = {%s=%d}; return %s.%s == %d end)()",
            v, k, n, v, k, n)
    end,
    function()
        local v = rvar()
        return string.format(
            "(function() local %s = setmetatable({},{__len=function() return 7 end}); return #%s == 7 end)()",
            v, v)
    end,
    function()
        local u = rvar(); local n = rint(10,99)
        return string.format(
            "(function() local %s=%d; return (function() return %s end)() == %d end)()",
            u, n, u, n)
    end,
    function()
        local f = rvar(); local n = rint(1,99)
        return string.format(
            "(function() local %s=function(x) return x+%d end; return %s(%d) == %d end)()",
            f, 0, f, n, n)
    end,
    function()
        local n = rint(1, 99)
        return string.format(
            "(coroutine.status(coroutine.create(function() coroutine.yield(%d) end)) == 'suspended')",
            n)
    end,
    function()
        return "(select(1, pcall(function() return true end)) == true)"
    end,
    function()
        local n = rint(1,99)
        return string.format(
            "(select(2, pcall(function() return %d end)) == %d)", n, n)
    end,
    function()
        local a,b,c = rvar(),rvar(),rvar()
        local n1 = rint(1,50); local n2 = rint(1,50)
        return string.format(
            "(function() local %s=%d; local %s=%d; local %s=%s+%s; return %s==%d end)()",
            a, n1, b, n2, c, a, b, c, n1+n2)
    end,
    function()
        local a,b,c,d = rvar(),rvar(),rvar(),rvar()
        local n = rint(1,30)
        return string.format(
            "(function() local %s=%d; local %s=%s*2; local %s=%s--%s+1; local %s=%s; return %s==%d end)()",
            a,n, b,a, c,b,b, d,a, d,n)
    end,
}

local FALSE_PREDICATES = {
    function() return "(1 == 0)" end,
    function()
        local n = rint(1,999)
        return string.format("(%d == %d)", n, n+1)
    end,
    function()
        local n = rint(1,100)
        return string.format("(%d ^ 2 == %d)", n, n*n+1)
    end,
    function()
        local a,b = rint(1,100), rint(1,100)
        return string.format("((%d + %d) == %d)", a, b, a+b+1)
    end,
    function()
        local n = rint(2,50)
        return string.format("(math.floor(%d.9) == %d)", n, n+1)
    end,
    function() return "(math.huge < 0)" end,
    function()
        local n = rint(1,100)
        return string.format("(math.min(%d, %d) == %d)", n, n+1, n+1)
    end,
    function()
        local n = rint(1, 0xFFFF)
        return string.format("((%d & %d) == %d)", n, n+1, n)
    end,
    function()
        local n = rint(1, 0xFF)
        return string.format("((%d | 0) == %d)", n, n+1)
    end,
    function()
        local n = rint(1, 0xFF)
        return string.format("((~%d & 0xFF) == %d)", n, n)
    end,
    function()
        local n = rint(1, 15)
        return string.format("((1 << %d) == %d)", n, (1 << n) + 1)
    end,
    function()
        local a = rint(1,0x7F); local b = rint(1,0x7F)
        if a == b then b = b + 1 end
        return string.format("((%d | %d) == (%d & %d))", a, b, a, b)
    end,
    function()
        local x = rint(1,0xFF); local y = rint(1,0xFF)
        if x == y then y = y + 1 end
        return string.format("((%d ~ %d) == 0)", x, y)
    end,
    function() return "type('') == 'number'" end,
    function()
        local s = rvar(rint(3,8))
        return string.format("(#%q == %d)", s, #s + 1)
    end,
    function() return "(string.byte('A') == 97)" end,
    function() return "(string.len('') == 1)" end,
    function()
        local s = rvar(4)
        return string.format("(string.upper(%q) == string.lower(%q))", s, s)
    end,
    function() return "type({}) == 'string'" end,
    function() return "({} == nil)" end,
    function() return "#{} == 1" end,
    function()
        local n = rint(2,8)
        local t = {}; for i=1,n do t[i]=tostring(i) end
        return string.format("(#{%s} == %d)", table.concat(t, ","), n+1)
    end,
    function()
        local u = rvar(); local n = rint(10,99)
        return string.format(
            "(function() local %s=%d; return (function() return %s end)() == %d end)()",
            u, n, u, n+1)
    end,
    function()
        return "(select(1, pcall(function() error('x') end)) == false) == false"
    end,
    function()
        return "(coroutine.status(coroutine.create(function() end)) == 'running')"
    end,
    function()
        local a,b = rvar(), rvar()
        local n1 = rint(1,50); local n2 = rint(1,50)
        return string.format(
            "(function() local %s=%d; local %s=%d; return %s+%s==%d end)()",
            a,n1, b,n2, a, b, n1+n2+1)
    end,
}

local function dead_assignment()
    local v = rvar(); local n = rint(1,999)
    return string.format("local %s = %d * %d + %d",
        v, rint(1,99), rint(1,99), n)
end

local function dead_loop()
    local v = rvar(); local n = rint(2,8); local acc = rvar()
    return string.format(
        "local %s = 0\nfor _i = 1, %d do\n    %s = %s + _i\nend",
        acc, n, acc, acc)
end

local function dead_state_machine()
    local state = rvar(); local out = rvar()
    local n = rint(2,4)
    local lines = {string.format("local %s = 1\nlocal %s = 0", state, out)}
    for i = 1, n do
        lines[#lines+1] = string.format(
            "if %s == %d then\n    %s = %d\n    %s = %s + %d",
            state, i, state, i+1, out, out, rint(1,50))
        lines[#lines+1] = "end"
    end
    return table.concat(lines, "\n")
end

local function dead_table_ops()
    local t = rvar(); local k = rvar(4); local v = rvar(4)
    local n = rint(1,99)
    return string.format(
        "local %s = {}\n%s[%q] = %d\n%s[%q] = nil",
        t, t, k, n, t, k)
end

local function dead_closure()
    local f = rvar(); local u = rvar(); local n = rint(1,99)
    return string.format(
        "local %s\ndo\n    local %s = %d\n    %s = function(x) return x + %s end\nend\n%s(0)",
        f, u, n, f, u, f)
end

local function dead_coroutine()
    local co = rvar(); local n = rint(1,99)
    return string.format(
        "local %s = coroutine.create(function()\n    coroutine.yield(%d)\nend)\ncoroutine.resume(%s)",
        co, n, co)
end

local function dead_pcall_block()
    local ok = rvar(); local res = rvar(); local n = rint(1,99)
    return string.format(
        "local %s, %s = pcall(function()\n    return %d\nend)\n_ = %s and %s",
        ok, res, n, ok, res)
end

local DEAD_GENERATORS = {
    dead_assignment,
    dead_loop,
    dead_state_machine,
    dead_table_ops,
    dead_closure,
    dead_coroutine,
    dead_pcall_block,
}

local function generate_dead_code(config)
    local count = rint(1, config.dead_complexity or 3)
    local parts = {}
    for _ = 1, count do
        local gen = DEAD_GENERATORS[rint(1, #DEAD_GENERATORS)]
        parts[#parts+1] = gen()
    end
    return table.concat(parts, "\n")
end

local function pick_predicate(always_true)
    if always_true then
        return TRUE_PREDICATES[rint(1, #TRUE_PREDICATES)]()
    else
        return FALSE_PREDICATES[rint(1, #FALSE_PREDICATES)]()
    end
end

local function build_nested(live_code, config, depth)
    depth = depth or 1
    local max_depth = config.nest_depth or rint(2, 5)

    local always_true = rbool()
    local pred        = pick_predicate(always_true)
    local dead        = generate_dead_code(config)

    local inner_live
    if depth < max_depth then
        inner_live = build_nested(live_code, config, depth + 1)
    else
        inner_live = live_code
    end

    local true_branch, false_branch
    if always_true then
        true_branch  = indent(inner_live, 4)
        false_branch = indent(dead, 4)
    else
        true_branch  = indent(dead, 4)
        false_branch = indent(inner_live, 4)
    end

    return string.format("if %s then\n%s\nelse\n%s\nend",
        pred, true_branch, false_branch)
end

local function build_cfg_chain(lines, config)
    local chain_len = rint(2, 4)
    local ctx_var = rvar()
    local ctx_val = rint(0, 255)

    local result = {}
    result[#result+1] = string.format("local %s = %d", ctx_var, ctx_val)

    for i = 1, chain_len do
        local line   = lines[i] or "-- (padding)"
        local always_true = rbool()
        local pred
        if i % 2 == 0 then
            pred = string.format("((%s & %d) == %d)", ctx_var, ctx_val, ctx_val & ctx_val)
        else
            pred = pick_predicate(always_true)
        end
        local dead = generate_dead_code(config)

        local live_branch, dead_branch
        if always_true then
            live_branch = indent(line, 4)
            dead_branch = indent(dead, 4)
        else
            live_branch = indent(dead, 4)
            dead_branch = indent(line, 4)
        end

        result[#result+1] = string.format("if %s then\n%s\nelse\n%s\nend",
            pred, live_branch, dead_branch)

        local delta = rint(0, 15)
        result[#result+1] = string.format("%s = %s ~ %d", ctx_var, ctx_var, delta)
        ctx_val = ctx_val ~ delta
    end

    return table.concat(result, "\n")
end

local function wrap_block(obfuscated_code)
    return string.format("do\n%s\nend", indent(obfuscated_code, 4))
end

local function wrap_function(obfuscated_code)
    local fname = rvar()
    return string.format(
        "local function %s()\n%s\nend\n%s()",
        fname, indent(obfuscated_code, 4), fname)
end

local function wrap_iife(obfuscated_code)
    return string.format("(function()\n%s\nend)()", indent(obfuscated_code, 4))
end

local WRAP_MODES = { wrap_block, wrap_function, wrap_iife }

local function wrap(code, mode)
    if mode == "block"    then return wrap_block(code) end
    if mode == "function" then return wrap_function(code) end
    if mode == "iife"     then return wrap_iife(code) end
    return WRAP_MODES[rint(1, #WRAP_MODES)](code)
end

function OpaquePredicates.process(code, config)
    if not config or not config.enabled then return code end

    local density       = config.density        or 0.35
    local nest          = config.nested         ~= false
    local wrap_mode     = config.wrap_mode      or "random"
    local use_cfg_chain = config.cfg_chain      ~= false
    local cfg_prob      = config.cfg_chain_prob or 0.25

    local lines = {}
    for line in (code .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end

    local out = {}
    local i   = 1

    while i <= #lines do
        local line = lines[i]

        if rfloat() < density and line:match("%S") then
            local style_roll = rfloat()

            if use_cfg_chain and style_roll < cfg_prob then
                local chunk = {}
                local j = i
                while j <= #lines and #chunk < 3 do
                    if lines[j]:match("%S") then chunk[#chunk+1] = lines[j] end
                    j = j + 1
                end
                local chain = build_cfg_chain(chunk, config)
                out[#out+1] = wrap(chain, wrap_mode)
                i = j

            elseif nest and style_roll < (cfg_prob + 0.45) then
                local nested = build_nested(line, config)
                out[#out+1] = wrap(nested, wrap_mode)
                i = i + 1

            else
                local always_true = rbool()
                local pred  = pick_predicate(always_true)
                local dead  = generate_dead_code(config)

                local true_branch, false_branch
                if always_true then
                    true_branch  = indent(line, 4)
                    false_branch = indent(dead,  4)
                else
                    true_branch  = indent(dead,  4)
                    false_branch = indent(line,  4)
                end

                local injected = string.format("if %s then\n%s\nelse\n%s\nend",
                    pred, true_branch, false_branch)
                out[#out+1] = wrap(injected, wrap_mode)
                i = i + 1
            end

        else
            out[#out+1] = line
            i = i + 1
        end
    end

    return table.concat(out, "\n")
end

function OpaquePredicates.pick_true_predicate()
    return TRUE_PREDICATES[rint(1, #TRUE_PREDICATES)]()
end

function OpaquePredicates.pick_false_predicate()
    return FALSE_PREDICATES[rint(1, #FALSE_PREDICATES)]()
end

function OpaquePredicates.generate_dead_code(config)
    return generate_dead_code(config or {})
end

return OpaquePredicates
