local Lexer = {}

local KEYWORDS = {
    ["and"]=1,["break"]=1,["do"]=1,["else"]=1,["elseif"]=1,
    ["end"]=1,["false"]=1,["for"]=1,["function"]=1,["goto"]=1,
    ["if"]=1,["in"]=1,["local"]=1,["nil"]=1,["not"]=1,["or"]=1,
    ["repeat"]=1,["return"]=1,["then"]=1,["true"]=1,["until"]=1,
    ["while"]=1,
}

function Lexer.tokenize(source)
    local tokens = {}
    local i = 1
    local line = 1

    while i <= #source do
        local ch = source:sub(i, i)

        if ch:match("%s") then
            local start = i
            while i <= #source and source:sub(i,i):match("%s") do
                if source:sub(i,i) == "\n" then line = line + 1 end
                i = i + 1
            end
            table.insert(tokens, {type="WHITESPACE", value=source:sub(start,i-1), line=line})

        elseif ch == "-" and source:sub(i,i+1) == "--" then
            if source:sub(i+2,i+3) == "[[" then
                local s = i; i = i + 4
                while i <= #source and source:sub(i,i+1) ~= "]]" do i=i+1 end
                i = i + 2
                table.insert(tokens, {type="COMMENT", value=source:sub(s,i-1), line=line})
            else
                local s = i
                while i <= #source and source:sub(i,i) ~= "\n" do i=i+1 end
                table.insert(tokens, {type="COMMENT", value=source:sub(s,i-1), line=line})
            end

        elseif ch == '"' or ch == "'" then
            local quote = ch
            local s = i; i = i + 1
            while i <= #source do
                if source:sub(i,i) == "\\" then i = i + 2
                elseif source:sub(i,i) == quote then i = i + 1; break
                else i = i + 1 end
            end
            table.insert(tokens, {type="STRING", value=source:sub(s,i-1), line=line})

        elseif source:sub(i,i+1) == "[[" then
            local s = i; i = i + 2
            while i <= #source and source:sub(i,i+1) ~= "]]" do i=i+1 end
            i = i + 2
            table.insert(tokens, {type="STRING", value=source:sub(s,i-1), line=line})

        elseif ch:match("[%a_]") then
            local s = i
            while i <= #source and source:sub(i,i):match("[%w_]") do i=i+1 end
            local word = source:sub(s, i-1)
            local ttype = KEYWORDS[word] and "KEYWORD" or "NAME"
            table.insert(tokens, {type=ttype, value=word, line=line})

        elseif ch:match("%d") or (ch == "." and source:sub(i+1,i+1):match("%d")) then
            local s = i
            while i <= #source and source:sub(i,i):match("[%w_%.xX]") do i=i+1 end
            table.insert(tokens, {type="NUMBER", value=source:sub(s,i-1), line=line})

        else
            local three = source:sub(i,i+2)
            local two   = source:sub(i,i+1)
            if three == "..." then
                table.insert(tokens, {type="OP", value=three, line=line}); i=i+3
            elseif two:match("^(==|~=|<=|>=|%.%.|//|<<|>>)") then
                table.insert(tokens, {type="OP", value=two, line=line}); i=i+2
            else
                table.insert(tokens, {type="OP", value=ch, line=line}); i=i+1
            end
        end
    end

    table.insert(tokens, {type="EOF", value="", line=line})
    return tokens
end

local ScopeAnalyzer = {}

local function new_scope(parent)
    return { parent=parent, children={}, vars={} }
end

function ScopeAnalyzer.analyze(tokens)
    local root_scope = new_scope(nil)
    local current    = root_scope
    local scope_stack = { root_scope }
    local var_map    = {}

    local function push_scope()
        local s = new_scope(current)
        table.insert(current.children, s)
        current = s
        table.insert(scope_stack, s)
    end

    local function pop_scope()
        table.remove(scope_stack)
        current = scope_stack[#scope_stack] or root_scope
    end

    local function next_real_idx(from)
        local j = from + 1
        while j <= #tokens and (tokens[j].type == "WHITESPACE" or tokens[j].type == "COMMENT") do
            j = j + 1
        end
        return j
    end

    local function declare(name, token_idx)
        if not current.vars[name] then current.vars[name] = {} end
        table.insert(current.vars[name], token_idx)
        var_map[token_idx] = { scope=current, name=name }
    end

    local function reference(name, token_idx)
        local s = current
        while s do
            if s.vars[name] then
                var_map[token_idx] = { scope=s, name=name }
                table.insert(s.vars[name], token_idx)
                return
            end
            s = s.parent
        end
    end

    local i = 1
    while i <= #tokens do
        local tok = tokens[i]

        if tok.type == "KEYWORD" then

            if tok.value == "local" then
                local ni = next_real_idx(i)
                local n  = tokens[ni]
                if n and n.type == "KEYWORD" and n.value == "function" then
                    local nni = next_real_idx(ni)
                    if tokens[nni] and tokens[nni].type == "NAME" then
                        declare(tokens[nni].value, nni)
                        i = nni
                    end
                    push_scope()
                    local pi = next_real_idx(i)
                    pi = next_real_idx(pi)
                    while tokens[pi] and tokens[pi].type ~= "EOF" do
                        if tokens[pi].type == "NAME" then
                            declare(tokens[pi].value, pi)
                        elseif tokens[pi].value == ")" then break end
                        pi = next_real_idx(pi)
                        if tokens[pi] and tokens[pi].value == "," then
                            pi = next_real_idx(pi)
                        end
                    end
                    i = pi
                else
                    local ci = ni
                    while tokens[ci] and tokens[ci].type == "NAME" do
                        declare(tokens[ci].value, ci)
                        local comma_i = next_real_idx(ci)
                        if tokens[comma_i] and tokens[comma_i].value == "," then
                            ci = next_real_idx(comma_i)
                        else
                            i = ci; break
                        end
                    end
                end

            elseif tok.value == "function" then
                push_scope()
                local ni = next_real_idx(i)
                if tokens[ni] and tokens[ni].type == "NAME" then
                    local ci = next_real_idx(ni)
                    while tokens[ci] and (tokens[ci].value == "." or tokens[ci].value == ":") do
                        ci = next_real_idx(ci)
                        ci = next_real_idx(ci)
                    end
                    ni = ci
                end
                local pi = next_real_idx(ni)
                while tokens[pi] and tokens[pi].type ~= "EOF" do
                    if tokens[pi].type == "NAME" then
                        declare(tokens[pi].value, pi)
                    elseif tokens[pi].value == ")" then break end
                    pi = next_real_idx(pi)
                    if tokens[pi] and tokens[pi].value == "," then
                        pi = next_real_idx(pi)
                    end
                end
                i = pi

            elseif tok.value == "for" then
                push_scope()
                local ci = next_real_idx(i)
                while tokens[ci] and tokens[ci].type == "NAME" do
                    declare(tokens[ci].value, ci)
                    local nx = next_real_idx(ci)
                    if tokens[nx] and tokens[nx].value == "," then
                        ci = next_real_idx(nx)
                    else
                        i = ci; break
                    end
                end

            elseif tok.value == "do"
                or tok.value == "then"
                or tok.value == "repeat" then
                push_scope()

            elseif tok.value == "end" then
                pop_scope()

            elseif tok.value == "until" then
                pop_scope()
            end

        elseif tok.type == "NAME" then
            reference(tok.value, i)
        end

        i = i + 1
    end

    return root_scope, var_map
end

local RandomUtils = {}

local LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local DIGITS = "0123456789"
local ALL = LETTERS .. DIGITS

function RandomUtils.random_int(min, max)
    return math.random(min, max)
end

function RandomUtils.random_variable_name(len)
    len = len or 10
    local first_idx = math.random(1, #LETTERS)
    local first = LETTERS:sub(first_idx, first_idx)
    local rest = {}
    for i = 1, len - 1 do
        rest[i] = ALL:sub(math.random(1, #ALL), math.random(1, #ALL))
    end
    return first .. table.concat(rest)
end

function RandomUtils.random_unicode_string(min_len, max_len)
    local len = math.random(min_len, max_len)
    local pool = {
        "\xC3\xA0","\xC3\xA1","\xC3\xA2","\xC3\xA3",
        "\xC3\xA8","\xC3\xA9","\xC3\xAA","\xC3\xAB",
        "\xC3\xAC","\xC3\xAD","\xC3\xAF","\xC3\xB3",
        "\xC3\xB5","\xC3\xBA","\xC3\xBC","\xC5\x82",
    }
    local chars = { pool[math.random(1,#pool)] }
    for _ = 2, len do
        table.insert(chars, pool[math.random(1,#pool)])
    end
    return table.concat(chars)
end

local VariableMangling = {}

local function gen_name(config, used)
    local name
    local tries = 0
    repeat
        tries = tries + 1
        if tries > 1000 then error("Cannot generate enough names") end
        if config.use_unicode then
            name = RandomUtils.random_unicode_string(
                config.name_length_min or 4,
                config.name_length_max or 8)
        else
            name = RandomUtils.random_variable_name(
                RandomUtils.random_int(
                    config.name_length_min or 4,
                    config.name_length_max or 10))
        end
    until not used[name]
    used[name] = true
    return name
end

local function inject_fake_vars(tokens, config)
    local count = config.fake_var_count or 5
    local fakes = {}
    for _ = 1, count do
        local fname = RandomUtils.random_variable_name(8)
        local fval  = tostring(RandomUtils.random_int(0, 99999))
        for _, t in ipairs({
            {type="KEYWORD",    value="local"},
            {type="WHITESPACE", value=" "},
            {type="NAME",       value=fname},
            {type="WHITESPACE", value=" "},
            {type="OP",         value="="},
            {type="WHITESPACE", value=" "},
            {type="NUMBER",     value=fval},
            {type="WHITESPACE", value="\n"},
        }) do table.insert(fakes, t) end
    end
    for j = #fakes, 1, -1 do
        table.insert(tokens, 1, fakes[j])
    end
    return tokens
end

function VariableMangling.process(code, config)
    if not config or not config.enabled then return code end

    math.randomseed(config.seed or os.time())

    local tokens = Lexer.tokenize(code)
    local _, var_map = ScopeAnalyzer.analyze(tokens)

    local scope_rename  = {}
    local used_globally = {}

    for token_idx, info in pairs(var_map) do
        local scope = info.scope
        local name  = info.name
        if not scope_rename[scope] then
            scope_rename[scope] = {}
        end
        if not scope_rename[scope][name] then
            scope_rename[scope][name] = gen_name(config, used_globally)
        end
    end

    for idx, tok in ipairs(tokens) do
        if tok.type == "NAME" and var_map[idx] then
            local info     = var_map[idx]
            local new_name = scope_rename[info.scope] and scope_rename[info.scope][info.name]
            if new_name then tok.value = new_name end
        end
    end

    if config.inject_fakes then
        tokens = inject_fake_vars(tokens, config)
    end

    local parts = {}
    for _, tok in ipairs(tokens) do
        table.insert(parts, tok.value)
    end
    return table.concat(parts)
end

return VariableMangling