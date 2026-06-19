#!/usr/bin/env lua
-- Achilles Obfuscator v1.1.1 - CLI Tool
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

local VERSION = "1.1.1"
local inputFile = "src/encrypt.lua"
local outputFile = "obfuscated.lua"
local mode = "medium"
local verbose = false
local passes = {}

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "-i" or a == "--input" then
        inputFile = arg[i+1]; i = i + 2
    elseif a == "-o" or a == "--output" then
        outputFile = arg[i+1]; i = i + 2
    elseif a == "-m" or a == "--mode" then
        mode = arg[i+1]; i = i + 2
    elseif a == "-p" or a == "--pass" then
        table.insert(passes, tonumber(arg[i+1])); i = i + 2
    elseif a == "-v" or a == "--verbose" then
        verbose = true; i = i + 1
    elseif a == "-h" or a == "--help" then
        print("Achilles Obfuscator v" .. VERSION)
        print("Usage: lua obfuscate.lua [OPTIONS]")
        print("-i <file>   Input file")
        print("-o <file>   Output file")
        print("-m <mode>   weak|medium|maximum")
        print("-p <n>      Run only pass n")
        print("-v          Verbose")
        print("-h          Help")
        return
    elseif a == "--version" then
        print("Achilles Obfuscator v" .. VERSION); return
    else
        print("Unknown: " .. a); return
    end
end

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
    local c = f:read("*all"); f:close(); return c
end

local function write_file(path, c)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(c); f:close(); return true
end

print("===========================================")
print("    Achilles Obfuscator v" .. VERSION)
print("===========================================")
print("Input:  " .. inputFile)
print("Output: " .. outputFile)
print("Mode:   " .. mode:upper())
print()

local source = read_file(inputFile)
if not source then print("ERROR: Cannot read " .. inputFile); return end
print("Source: " .. #source .. " bytes")
print()

local code = source
local config = presets[mode]

if #passes > 0 then
    config = {}
    for i = 1, 17 do config[i] = false end
    for _, p in ipairs(passes) do config[p] = true end
end

for i, obf in ipairs(Obfuscators) do
    if config[i] then
        local name = ObfNames[i]
        io.write("  [+] " .. name .. "...")
        io.flush()
        local new_code = obf.process(code, {enabled = true})
        if new_code and new_code ~= code then
            code = new_code
            print(" (+" .. (#new_code - #code + 1) .. ")")
        else
            print(" (-)")
        end
    end
end

code = Watermark.add(code)

if write_file(outputFile, code) then
    print()
    print("===========================================")
    print("SUCCESS! -> " .. outputFile .. " (" .. #code .. " bytes)")
    print("===========================================")
else
    print("ERROR: Cannot write " .. outputFile)
end
