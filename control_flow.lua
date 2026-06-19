-- Advanced Control Flow Flattening Layer
-- Architecture: AST-aware block splitting → CFG graph → encrypted state machine
-- → dispatch table → opaque predicates → fake states + transitions
local ControlFlow = {}
local RandomUtils = require("random_utils")
local TransformUtils = require("transform_utils")

-- ============================================================
-- SECTION 1: AST-aware block splitter (statement-boundary safe)
-- ============================================================
-- Thay vì chia theo dòng, ta track độ sâu của block (do/end, if/end, 
-- function/end) để chỉ cắt tại điểm mà stack = 0 (statement boundary thật).

local BLOCK_OPEN  = { ["do"]=true, ["then"]=true, ["repeat"]=true, ["function"]=true }
local BLOCK_CLOSE = { ["end"]=true, ["until"]=true }

local function ast_split_blocks(code, config)
    local stmts   = {}   -- danh sách statement-groups (CFG nodes)
    local pending = {}   -- dòng đang gom
    local depth   = 0

    local function flush()
        if #pending > 0 then
            table.insert(stmts, table.concat(pending, "\n"))
            pending = {}
        end
    end

    for line in (code .. "\n"):gmatch("([^\n]*)\n") do
        local trimmed = line:match("^%s*(.-)%s*$")

        -- Đếm mở/đóng block bằng token đầu/cuối của dòng
        -- (đơn giản hóa; production nên dùng full lexer)
        for token in trimmed:gmatch("%a+") do
            if BLOCK_OPEN[token]  then depth = depth + 1 end
            if BLOCK_CLOSE[token] then depth = math.max(0, depth - 1) end
        end

        table.insert(pending, line)

        -- Chỉ cắt khi depth == 0 (đang ở top-level) và đủ kích thước
        local min_sz = config.block_size_min or 3
        local max_sz = config.block_size_max or 8
        if depth == 0 and #pending >= RandomUtils.random_int(min_sz, max_sz) then
            flush()
        end
    end
    flush()
    return stmts
end

-- ============================================================
-- SECTION 2: CFG Graph builder
-- ============================================================
-- Mỗi node = { id, code, succs={}, preds={} }
-- Edge mặc định: linear i → i+1
-- Sau đó chèn fake nodes + back-edges ngẫu nhiên

local function build_cfg(blocks)
    local nodes = {}
    for i, blk in ipairs(blocks) do
        nodes[i] = { id = i, code = blk, succs = {}, preds = {}, fake = false }
    end

    -- Linear edges
    for i = 1, #nodes - 1 do
        table.insert(nodes[i].succs, i + 1)
        table.insert(nodes[i + 1].preds, i)
    end

    -- Thêm fake nodes (dead code, không bao giờ thực thi do opaque predicate)
    local num_fake = math.max(1, math.floor(#nodes * 0.4))  -- ~40% fake
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
        -- Fake node trỏ về một node thật ngẫu nhiên (tạo vẻ phức tạp)
        local target = RandomUtils.random_int(1, #nodes)
        table.insert(fnode.succs, target)
        table.insert(nodes[target].preds, fake_id)
        table.insert(nodes, fnode)
    end

    return nodes
end

-- ============================================================
-- SECTION 3: State encryption  (state = state XOR rolling_key)
-- ============================================================
-- Mỗi state ID được mã hóa bằng key ngẫu nhiên tại compile-time.
-- Runtime decrypt: raw_state = encoded XOR key

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
        -- Tạo Lua expression để decode tại runtime
        decode_expr = function(enc_var, key_val)
            -- Lua 5.3+ dùng ~, Lua 5.1/5.2 dùng bit32/bit
            return string.format("(%s ~ %d)", enc_var, key_val)
        end,
        encode_expr = function(state_idx)
            return tostring(encoded[state_idx])
        end
    }
end

-- ============================================================
-- SECTION 4: Opaque predicates factory
-- ============================================================
-- Trả về (expr_always_true, expr_always_false) dưới dạng Lua string.
-- Production: dùng nhiều dạng hơn (polynomial, aliasing, extern calls).

local OPAQUE_ALWAYS_TRUE = {
    -- n*(n+1) luôn chẵn
    function(v) return string.format("((%s * (%s + 1)) %% 2 == 0)", v, v) end,
    -- x^2 >= 0
    function(v) return string.format("((%s * %s) >= 0)", v, v) end,
    -- (a|b) + (a&b) == a+b  (bitwise identity)
    function(v, w) return string.format("((%s | %s) + (%s & %s) == %s + %s)", v,w,v,w,v,w) end,
}

local function opaque_true(a, b)
    local idx = RandomUtils.random_int(1, #OPAQUE_ALWAYS_TRUE)
    local fn  = OPAQUE_ALWAYS_TRUE[idx]
    return b and fn(a, b) or fn(a, a)
end

local function opaque_false(a, b)
    -- NOT(always_true) = always_false
    return "not (" .. opaque_true(a, b) .. ")"
end

-- ============================================================
-- SECTION 5: Dispatch table builder
-- ============================================================
-- Thay vì if/elseif chain (dễ bị decompiler nhận ra pattern),
-- ta dùng bảng hàm: dispatch[state]() và mã hóa key của bảng.

local function build_dispatch_table(nodes, cipher, labels, state_var, key_var)
    local lines = {}
    local tbl   = RandomUtils.random_variable_name(10)  -- tên bảng dispatch
    local op_a  = RandomUtils.random_variable_name(5)
    local op_b  = RandomUtils.random_variable_name(5)

    -- Khai báo biến opaque predicate
    table.insert(lines, string.format(
        "local %s, %s = %d, %d",
        op_a, op_b,
        RandomUtils.random_int(2, 100),
        RandomUtils.random_int(2, 100)
    ))

    -- Khởi tạo bảng dispatch với key đã encode
    table.insert(lines, string.format("local %s = {}", tbl))
    for _, node in ipairs(nodes) do
        local enc_state = cipher.encode_expr(node.id)
        -- Mỗi entry là closure trỏ đến label của block
        -- Fake nodes dùng opaque_false làm guard → không bao giờ chạy
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

    -- Dispatcher loop: decode state → lookup → call
    local loop_label = RandomUtils.random_variable_name(12)
    table.insert(lines, string.format("::%s::", loop_label))
    table.insert(lines, string.format(
        "local %s_fn = %s[%s]",
        tbl, tbl,
        cipher.decode_expr(state_var, 0)   -- key=0 đặt chỗ; xem phần emit
    ))
    table.insert(lines, string.format(
        "if %s_fn and %s then %s_fn() end",
        tbl, opaque_true(op_a, op_b), tbl
    ))

    return table.concat(lines, "\n"), tbl, loop_label, op_a, op_b
end

-- ============================================================
-- SECTION 6: Emit flattened code  (assembler cuối cùng)
-- ============================================================

function ControlFlow.process(code, config)
    if not config or not config.enabled then return code end

    -- 1. Chia block tại statement boundary thật
    local blocks = ast_split_blocks(code, config)
    if #blocks <= 1 then return code end

    -- 2. Xây CFG (real + fake nodes)
    local nodes   = build_cfg(blocks)
    local n_nodes = #nodes

    -- 3. State cipher
    local cipher    = make_state_cipher(n_nodes)
    local state_var = RandomUtils.random_variable_name(8)   -- biến giữ encrypted state
    local key_var   = RandomUtils.random_variable_name(6)   -- key hiện tại

    -- 4. Gán label cho mỗi node
    local labels = {}
    for i = 1, n_nodes do
        labels[i] = RandomUtils.random_variable_name(12)
    end

    -- 5. Sinh dispatch table & dispatcher loop code
    local dispatch_code, tbl_name, loop_lbl, op_a, op_b =
        build_dispatch_table(nodes, cipher, labels, state_var, key_var)

    -- 6. Lắp ráp toàn bộ
    local out = {}

    -- Khởi tạo state = encoded(1)  (node đầu tiên)
    table.insert(out, string.format(
        "local %s = %s  -- initial encrypted state",
        state_var, cipher.encode_expr(1)
    ))
    table.insert(out, "")

    -- Dispatch table + loop
    -- Patch decode_expr: thay 0 bằng key thực của state hiện tại
    -- Vì key thay đổi theo state, ta dùng lookup key_table tại runtime
    local key_tbl = RandomUtils.random_variable_name(8)
    table.insert(out, string.format("local %s = {", key_tbl))
    for i = 1, n_nodes do
        table.insert(out, string.format("  [%s] = %d,", cipher.encode_expr(i), cipher.keys[i]))
    end
    table.insert(out, "}")

    -- Fix dispatch code: thay decode_expr placeholder
    local fixed_dispatch = dispatch_code:gsub(
        string.format("(%s ~ 0)", state_var),
        string.format("(%s ~ %s[%s])", state_var, key_tbl, state_var)
    )
    table.insert(out, fixed_dispatch)
    table.insert(out, "")

    -- Emit mỗi node: label → code → update state → goto dispatcher
    for _, node in ipairs(nodes) do
        table.insert(out, string.format("::%s::", labels[node.id]))

        if node.fake then
            -- Fake node: guard bằng opaque_false, không bao giờ chạy
            table.insert(out, string.format(
                "if %s then -- dead branch", opaque_false(op_a, op_b)
            ))
            table.insert(out, node.code)
            table.insert(out, "end")
        else
            table.insert(out, node.code)
        end

        -- Xác định successor thật
        local real_succ = nil
        for _, s in ipairs(node.succs) do
            if not nodes[s] or not nodes[s].fake then
                real_succ = s
                break
            end
        end

        if real_succ and real_succ <= n_nodes then
            -- Chèn fake transition thỉnh thoảng (goto fake node, rồi fake node tự goto đúng)
            if not node.fake and RandomUtils.random_bool() then
                -- tìm fake node trỏ về real_succ
                local fake_bridge = nil
                for _, fn in ipairs(nodes) do
                    if fn.fake and fn.succs[1] == real_succ then
                        fake_bridge = fn
                        break
                    end
                end
                if fake_bridge then
                    -- opaque_false guard → luôn đi đúng đường
                    table.insert(out, string.format(
                        "if %s then goto %s end",
                        opaque_false(op_a, op_b), labels[fake_bridge.id]
                    ))
                end
            end

            -- Cập nhật encrypted state → goto dispatcher
            table.insert(out, string.format(
                "%s = %s  -- next: node %d",
                state_var, cipher.encode_expr(real_succ), real_succ
            ))
            table.insert(out, string.format("goto %s", loop_lbl))
        end

        table.insert(out, "")
    end

    return table.concat(out, "\n")
end

return ControlFlow
