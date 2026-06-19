local ControlFlow = {}
local RandomUtils = require("libs.random_utils")
local TransformUtils = require("libs.transform_utils")

local BLOCK_OPEN  = { ["do"]=true, ["then"]=true, ["repeat"]=true, ["function"]=true }
local BLOCK_CLOSE = { ["end"]=true, ["until"]=true }

local function ast_split_blocks(code, config)
    local stmts   = {}
    local pending = {}
    local depth   = 0

    local function flush()
        if #pending > 0 then
            table.insert(stmts, table.concat(pending, "\n"))
            pending = {}
        end
    end

    for line in (code .. "\n"):gmatch("([^\n]*)\n") do
        local trimmed = line:match("^%s*(.-)%s*$")
        for token in trimmed:gmatch("%a+") do
            if BLOCK_OPEN[token]  then depth = depth + 1 end
            if BLOCK_CLOSE[token] then depth = math.max(0, depth - 1) end
        end
        table.insert(pending, line)
        local min_sz = config.block_size_min or 3
        local max_sz = config.block_size_max or 8
        if depth == 0 and #pending >= RandomUtils.random_int(min_sz, max_sz) then
            flush()
        end
    end
    flush()
    return stmts
end

local function build_cfg(blocks)
    local nodes = {}
    for i, blk in ipairs(blocks) do
        nodes[i] = { id = i, code = blk, succs = {}, preds = {}, fake = false }
    end
    for i = 1, #nodes - 1 do
        table.insert(nodes[i].succs, i + 1)
        table.insert(nodes[i + 1].preds, i)
    end
    local num_fake = math.max(1, math.floor(#nodes * 0.4))
    for _ = 1, num_fake do
        local fake_id = #nodes + 1
        local fake_code = TransformUtils.generate_dead_code and
                          TransformUtils.generate_dead_code() or
                          ("local _dead_" .. RandomUtils.random_variable_name(6) .. " = 0")
        local fnode = {
            id   = fake_id,
            code = fake_code,
            succs = {},
            preds = {},
            fake  = true,
        }
        local target = RandomUtils.random_int(1, #nodes)
        table.insert(fnode.succs, target)
        table.insert(nodes[target].preds, fake_id)
        table.insert(nodes, fnode)
    end
    return nodes
end

local function make_state_cipher(num_states)
    local keys   = {}
    local encoded = {}
    for i = 1, num_states do
        keys[i]    = RandomUtils.random_int(0x10, 0xFF)
        encoded[i] = bit32 and bit32.bxor(i, keys[i]) or (i ~ keys[i])
    end
    return {
        keys    = keys,
        encoded = encoded,
        decode_expr = function(enc_var, key_val)
            return string.format("(%s ~ %d)", enc_var, key_val)
        end,
        encode_expr = function(state_idx)
            return tostring(encoded[state_idx])
        end
    }
end

local OPAQUE_ALWAYS_TRUE = {
    function(v) return string.format("((%s * (%s + 1)) %% 2 == 0)", v, v) end,
    function(v) return string.format("((%s * %s) >= 0)", v, v) end,
    function(v, w) return string.format("((%s | %s) + (%s & %s) == %s + %s)", v,w,v,w,v,w) end,
}

local function opaque_true(a, b)
    local idx = RandomUtils.random_int(1, #OPAQUE_ALWAYS_TRUE)
    local fn  = OPAQUE_ALWAYS_TRUE[idx]
    return b and fn(a, b) or fn(a, a)
end

local function opaque_false(a, b)
    return "not (" .. opaque_true(a, b) .. ")"
end

local function build_dispatch_table(nodes, cipher, labels, state_var, key_var)
    local lines = {}
    local tbl   = "dtbl"
    local op_a  = "opa"
    local op_b  = "opb"

    table.insert(lines, string.format(
        "local %s, %s = %d, %d",
        op_a, op_b,
        RandomUtils.random_int(2, 100),
        RandomUtils.random_int(2, 100)
    ))

    table.insert(lines, string.format("local %s = {}", tbl))
    for _, node in ipairs(nodes) do
        local enc_state = cipher.encode_expr(node.id)
        if node.fake then
            table.insert(lines, string.format(
                "%s[%s] = function() if %s then goto %s end end",
                tbl, enc_state, opaque_false(op_a, op_b), labels[node.id]
            ))
        else
            table.insert(lines, string.format(
                "%s[%s] = function() goto %s end",
                tbl, enc_state, labels[node.id]
            ))
        end
    end

    local loop_label = "_loop_"
    table.insert(lines, string.format("::%s::", loop_label))
    table.insert(lines, string.format(
        "local %s_fn = %s[%s]",
        tbl, tbl,
        cipher.decode_expr(state_var, 0)
    ))
    table.insert(lines, string.format(
        "if %s_fn and %s then %s_fn() end",
        tbl, opaque_true(op_a, op_b), tbl
    ))

    return table.concat(lines, "\n"), tbl, loop_label, op_a, op_b
end

function ControlFlow.process(code, config)
    if not config or not config.enabled then return code end

    local blocks = ast_split_blocks(code, config)
    if #blocks <= 1 then return code end

    local nodes   = build_cfg(blocks)
    local n_nodes = #nodes

    local cipher    = make_state_cipher(n_nodes)
    local state_var = "st" .. tostring(math.floor(math.random() * 99999))
    local key_var   = "kv" .. tostring(math.floor(math.random() * 99999))

    local labels = {}
    for i = 1, n_nodes do
        labels[i] = "_l" .. tostring(i) .. "_"
    end

    local dispatch_code, tbl_name, loop_lbl, op_a, op_b =
        build_dispatch_table(nodes, cipher, labels, state_var, key_var)

    local out = {}

    table.insert(out, string.format(
        "local %s = %s",
        state_var, cipher.encode_expr(1)
    ))
    table.insert(out, "")

    local key_tbl = "keys"
    table.insert(out, string.format("local %s = {", key_tbl))
    for i = 1, n_nodes do
        table.insert(out, string.format("  [%s] = %d,", cipher.encode_expr(i), cipher.keys[i]))
    end
    table.insert(out, "}")

    local fixed_dispatch = dispatch_code:gsub(
        string.format("(%s ~ 0)", state_var),
        string.format("(%s ~ %s[%s])", state_var, key_tbl, state_var)
    )
    table.insert(out, fixed_dispatch)
    table.insert(out, "")

    for _, node in ipairs(nodes) do
        table.insert(out, string.format("::%s::", labels[node.id]))

        if node.fake then
            table.insert(out, string.format(
                "if %s then",
                opaque_false(op_a, op_b)
            ))
            table.insert(out, node.code)
            table.insert(out, "end")
        else
            table.insert(out, node.code)
        end

        local real_succ = nil
        for _, s in ipairs(node.succs) do
            if not nodes[s] or not nodes[s].fake then
                real_succ = s
                break
            end
        end

        if real_succ and real_succ <= n_nodes then
            if not node.fake and RandomUtils.random_bool() then
                local fake_bridge = nil
                for _, fn in ipairs(nodes) do
                    if fn.fake and fn.succs[1] == real_succ then
                        fake_bridge = fn
                        break
                    end
                end
                if fake_bridge then
                    table.insert(out, string.format(
                        "if %s then goto %s end",
                        opaque_false(op_a, op_b), labels[fake_bridge.id]
                    ))
                end
            end

            table.insert(out, string.format(
                "%s = %s",
                state_var, cipher.encode_expr(real_succ)
            ))
            table.insert(out, string.format("goto %s", loop_lbl))
        end

        table.insert(out, "")
    end

    return table.concat(out, "\n")
end

return ControlFlow
