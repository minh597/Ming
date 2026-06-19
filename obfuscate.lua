-- Achilles Obfuscator v1.1.1
local Watermark = require("libs.watermark")

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
    "AST Complete", "Identifier Rename", "String Encryption",
    "Constant Encryption", "MBA", "Opaque Predicates",
    "Dead Code", "Control Flow", "Bogus Control Flow",
    "Fake States", "Table Encryption", "Runtime Decoder",
    "VM", "Anti Dump", "Anti Decompiler",
    "Multi-pass", "Minify"
}

local mode = arg and arg[1] or "medium"
if mode ~= "weak" and mode ~= "medium" and mode ~= "maximum" then
    mode = "medium"
end

local presets = {
    weak = {true,true,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false},
    medium = {true,true,true,true,true,false,false,false,false,false,false,false,false,false,false,false,false},
    maximum = {true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true,true},
}

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local c = f:read("*all")
    f:close()
    return c
end

local function write_file(path, c)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(c)
    f:close()
    return true
end

print("===========================================")
print("    Achilles Obfuscator v1.1.1")
print("===========================================")
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
    if config[i] then
        local name = ObfNames[i] or "Unknown"
        print("  [+] " .. name .. "...")
        local new_code = obf.process(code, {enabled = true})
        if new_code and new_code ~= code then
            code = new_code
            print("      -> " .. #code .. " bytes")
        else
            print("      (no change)")
        end
    end
end

code = Watermark.add(code)

local success = write_file("obfuscated_encrypt.lua", code)
if success then
    print()
    print("===========================================")
    print("DONE! Output: obfuscated_encrypt.lua (" .. #code .. " bytes)")
    print("===========================================")
end
