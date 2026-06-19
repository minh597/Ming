local RandomUtils = require("libs.random_utils")
local VariableMangling = require("obfuscators.variable_mangling")
local NumberEncoding = require("obfuscators.number_encoding")
local StringEncryption = require("obfuscators.string_encryption")
local TableObfuscation = require("obfuscators.table_obfuscation")
local OpaquePredicates = require("obfuscators.opaque_predicates")
local DeadCode = require("obfuscators.dead_code")
local ControlFlow = require("obfuscators.control_flow")

local config = {
    var_mangle = {
        enabled = false,
        use_unicode = false,
        name_length_min = 2,
        name_length_max = 4,
    },
    number_encode = {
        enabled = false,
    },
    string_encrypt = { enabled = true },
    table_obfuscate = {
        enabled = false,
    },
    opaque_predicates = {
        enabled = false,
    },
    dead_code = {
        enabled = false,
    },
    control_flow = {
        enabled = false,
        block_size_min = 3,
        block_size_max = 5,
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

local encrypt_source = read_file("src/encrypt.lua")
if not encrypt_source then
    print("ERROR: Cannot read src/encrypt.lua")
    return
end

print("MASTER OBFUSCATOR PIPELINE")
print("Input: encrypt.lua (" .. #encrypt_source .. " bytes)")
print()

local code = encrypt_source

local layers = {
    {"Variable Mangling",      VariableMangling.process,  config.var_mangle},
    {"Control Flow Flattening",ControlFlow.process,       config.control_flow},
    {"Number Encoding",        NumberEncoding.process,    config.number_encode},
    {"String Encryption",      StringEncryption.process,  config.string_encrypt},
    {"Table Obfuscation",      TableObfuscation.process,  config.table_obfuscate},
    {"Dead Code Injection",    DeadCode.process,          config.dead_code},
    {"Opaque Predicates",      OpaquePredicates.process,  config.opaque_predicates},
}

for _, layer in ipairs(layers) do
    local name, func, cfg = layer[1], layer[2], layer[3]
    print("  Applying: " .. name .. "...")
    code = func(code, cfg)
    print("    -> " .. #code .. " bytes")
end

local success = write_file("obfuscated_encrypt.lua", code)
if success then
    print()
    print("DONE! Output: obfuscated_encrypt.lua (" .. #code .. " bytes)")
else
    print("ERROR: Cannot write obfuscated_encrypt.lua")
end