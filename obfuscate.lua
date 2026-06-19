-- Achilles Obfuscator v1.1.1
local RandomUtils = require("libs.random_utils")
local Watermark = require("libs.watermark")

-- Load all obfuscators in order
local Obfuscators = {
    require("obfuscators.01_ast"),
    require("obfuscators.02_identifier_rename"),
    require("obfuscators.03_string_encryption"),
    require("obfuscators.04_constant_encryption"),
    require("obfuscators.05_mba"),
    require("obfuscators.06_opaque_predicates"),
    require("obfuscators.07_dead_code"),
    require("obfuscators.08_control_flow"),
    require("obfuscators.09_bogus_control_flow"),
    require("obfuscators.10_fake_states"),
    require("obfuscators.11_table_encryption"),
    require("obfuscators.12_runtime_decoder"),
    require("obfuscators.13_vm"),
    require("obfuscators.14_anti_dump"),
    require("obfuscators.15_anti_decompiler"),
    require("obfuscators.16_multi_pass"),
    require("obfuscators.17_minify"),
}

local ObfNames = {
    "AST Complete",
    "Identifier Rename",
    "String Encryption",
    "Constant Encryption",
    "MBA",
    "Opaque Predicate",
    "Dead Code",
    "Control Flow Flattening",
    "Bogus Control Flow",
    "Fake States",
    "Table Encryption",
    "Runtime Decoder",
    "VM (Stack/Register)",
    "Anti Dump",
    "Anti Decompiler",
    "Multi-pass Scheduler",
    "Minify",
}

-- Modes: weak, medium, maximum
local mode = arg and arg[1] or "medium"
if mode ~= "weak" and mode ~= "medium" and mode ~= "maximum" then
    mode = "medium"
end

local presets = {
    weak = {
        {enabled = true, config = {enabled = true}},    -- AST
        {enabled = false},                               -- Identifier Rename
        {enabled = true, config = {enabled = true}},   -- String Encryption
        {enabled = false},                              -- Constant Encryption
        {enabled = false},                              -- MBA
        {enabled = false},                              -- Opaque Predicate
        {enabled = false},                              -- Dead Code
        {enabled = false},                              -- Control Flow
        {enabled = false},                              -- Bogus Control Flow
        {enabled = false},                              -- Fake States
        {enabled = false},                              -- Table Encryption
        {enabled = false},                              -- Runtime Decoder
        {enabled = false},                              -- VM
        {enabled = false},                              -- Anti Dump
        {enabled = false},                              -- Anti Decompiler
        {enabled = false},                              -- Multi-pass
        {enabled = false},                              -- Minify
    },
    medium = {
        {enabled = true, config = {enabled = true}},       -- AST
        {enabled = true, config = {enabled = true, name_min = 4, name_max = 8}},  -- Identifier Rename
        {enabled = true, config = {enabled = true}},       -- String Encryption
        {enabled = true, config = {enabled = true}},       -- Constant Encryption
        {enabled = true, config = {enabled = true, max_ops = 10}}, -- MBA
        {enabled = false},                                  -- Opaque Predicate
        {enabled = false},                                  -- Dead Code
        {enabled = false},                                  -- Control Flow
        {enabled = false},                                  -- Bogus Control Flow
        {enabled = false},                                  -- Fake States
        {enabled = false},                                  -- Table Encryption
        {enabled = false},                                  -- Runtime Decoder
        {enabled = false},                                  -- VM
        {enabled = false},                                  -- Anti Dump
        {enabled = false},                                  -- Anti Decompiler
        {enabled = false},                                  -- Multi-pass
        {enabled = false},                                  -- Minify
    },
    maximum = {
        {enabled = true, config = {enabled = true}},       -- AST
        {enabled = true, config = {enabled = true, name_min = 6, name_max = 12}},  -- Identifier Rename
        {enabled = true, config = {enabled = true}},       -- String Encryption
        {enabled = true, config = {enabled = true}},       -- Constant Encryption
        {enabled = true, config = {enabled = true, max_ops = 30}}, -- MBA
        {enabled = true, config = {enabled = true, max_insert = 10, density = 0.15}},  -- Opaque Predicate
        {enabled = true, config = {enabled = true, max_insert = 10, density = 0.1}},   -- Dead Code
        {enabled = true, config = {enabled = true}},      -- Control Flow
        {enabled = true, config = {enabled = true, max_insert = 8, density = 0.1}},   -- Bogus Control Flow
        {enabled = true, config = {enabled = true, max_insert = 5, density = 0.08}}, -- Fake States
        {enabled = true, config = {enabled = true}},      -- Table Encryption
        {enabled = false},                                 -- Runtime Decoder (too risky)
        {enabled = false},                                 -- VM
        {enabled = true, config = {enabled = true}},       -- Anti Dump
        {enabled = true, config = {enabled = true, junk_count = 10}}, -- Anti Decompiler
        {enabled = true, config = {enabled = true}},      -- Multi-pass
        {enabled = true, config = {enabled = true}},      -- Minify
    },
}

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("        Achilles™ Obfuscator v1.1.1")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("Mode: " .. mode:upper())
print()

local source = read_file("src/encrypt.lua")
if not source then
    print("ERROR: Cannot read src/encrypt.lua")
    return
end

print("Input: src/encrypt.lua (" .. #source .. " bytes)")
print()

local code = source
local config = presets[mode]

for i, obf in ipairs(Obfuscators) do
    local cfg = config[i]
    if cfg and cfg.enabled then
        local name = ObfNames[i] or "Unknown"
        print("  [+] " .. name .. "...")
        local new_code = obf.process(code, cfg.config or {})
        if new_code and new_code ~= code then
            code = new_code
            print("      -> " .. #code .. " bytes")
        else
            print("      (no change)")
        end
    end
end

-- Add watermark
print()
print("  [+] Watermark...")
code = Watermark.add(code)

local success = write_file("obfuscated_encrypt.lua", code)
if success then
    print()
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("DONE! Output: obfuscated_encrypt.lua (" .. #code .. " bytes)")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
else
    print("ERROR: Cannot write obfuscated_encrypt.lua")
end
