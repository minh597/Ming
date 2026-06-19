#!/usr/bin/env lua
-- Achilles Obfuscator v1.1.1
local Watermark = require('libs.watermark')

local Obfuscators = {
    require('obfuscators.01_ast'),
    require('obfuscators.02_identifier_rename'),
    require('obfuscators.03_string_encryption'),
    require('obfuscators.04_constant_encryption'),
    require('obfuscators.05_mba'),
    require('obfuscators.06_opaque_predicates'),
    require('obfuscators.07_dead_code'),
    require('obfuscators.08_control_flow'),
    require('obfuscators.09_bogus_control_flow'),
    require('obfuscators.10_fake_states'),
    require('obfuscators.11_table_encryption'),
    require('obfuscators.12_runtime_decoder'),
    require('obfuscators.13_vm'),
    require('obfuscators.14_anti_dump'),
    require('obfuscators.15_anti_decompiler'),
    require('obfuscators.16_multi_pass'),
    require('obfuscators.17_minify'),
}

local ObfNames = {
    'AST', 'Rename', 'StringEnc', 'ConstEnc', 'MBA',
    'Opaque', 'DeadCode', 'CtrlFlow', 'Bogus', 'FakeState',
    'TableEnc', 'Runtime', 'VM', 'AntiDump', 'AntiDec',
    'MultiPass', 'Minify'
}

local VERSION = '1.1.1'

-- Usage
if #arg < 3 then
    print('Achilles Obfuscator v' .. VERSION)
    print('Usage: lua main.lua <input.lua> <output.lua> <mode>')
    print('Modes: weak | medium | maximum')
    return
end

local input, output, mode = arg[1], arg[2], arg[3]
if mode ~= 'weak' and mode ~= 'medium' and mode ~= 'maximum' then
    mode = 'maximum'
end

local presets = {
    weak = {1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
    medium = {1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0},
    maximum = {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
}

local function read_file(p)
    local f = io.open(p, 'r')
    if not f then return nil end
    local c = f:read('*all')
    f:close()
    return c
end

local function write_file(p, c)
    local f = io.open(p, 'w')
    if not f then return false end
    f:write(c)
    f:close()
    return true
end

print('===========================================')
print('    Achilles Obfuscator v' .. VERSION)
print('===========================================')
print('Input:  ' .. input)
print('Output: ' .. output)
print('Mode:   ' .. mode:upper())
print()

local source = read_file(input)
if not source then
    print('ERROR: Cannot read ' .. input)
    return
end
print('Source: ' .. #source .. ' bytes')

local code = source
local config = presets[mode]

for i = 1, 17 do
    if config[i] == 1 then
        io.write('  [+] ' .. ObfNames[i] .. '... ')
        io.flush()
        local new = Obfuscators[i].process(code, {enabled = true})
        if new and new ~= code then
            code = new
            print('+' .. (#new - #code + 1))
        else
            print('-')
        end
    end
end

code = Watermark.add(code)

if write_file(output, code) then
    print()
    print('===========================================')
    print('SUCCESS -> ' .. output .. ' (' .. #code .. ' bytes)')
    print('===========================================')
else
    print('ERROR: Cannot write ' .. output)
end
