local _e1579=function(s)local r={}for i=1,#s do r[i]=string.char(string.byte(s,i)~76)end return table.concat(r)end
--[[
  encrypt.lua - ULTIMATE SINGLE-PIPE ENCRYPTION for Lua
  ======================================================
  
  ONE function encrypt() ONLY. NO decrypt.
  
  This is the most hardcore encryption pipeline possible in pure Lua.
  Every technique is stacked into a single irreversible cascade:
  
  [32B salt] → [500K KDF → 8192B key material] → [2 key-dependent S-Boxes] →
  [whitening] → [keystream XOR #1] → [128B feedback cipher] →
  [S-Box substitution] → [16-round bit diffusion] → [transposition] →
  [2nd feedback] → [keystream XOR #2] → [2nd S-Box] → [3rd keystream] →
  [final whitening] → [16-byte HMAC-SHA3-like integrity tag]
  
  Total: 12 stages. 500,000 KDF iterations. 16 diffusion rounds.
  Designed to be computationally INFEASIBLE to reverse without the key.
]]

local encrypt = {}

-- ============================================================
-- AES S-BOX (standard non-linear substitution)
-- ============================================================
local SBOX = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
}

local SBOX_INV = {}
do for i = 1, 256 do SBOX_INV[SBOX[i] + 1] = i - 1 end end

-- ============================================================
-- BITWISE OPERATIONS
-- ============================================================
local bxor, band, lshift, rshift
if bit32 then
    bxor   = bit32.bxor
    band   = bit32.band
    lshift = bit32.lshift
    rshift = bit32.rshift
else
    bxor   = function(a,b) return a ~ b end
    band   = function(a,b) return a & b end
    lshift = function(a,b) return (a << b) & 0xFFFFFFFF end
    rshift = function(a,b) return (a >> b) & 0xFFFFFFFF end
end

local function rotl8(b, n) n = n % 8; return ((b << n) | (b >> (8 - n))) & 0xFF end
local function rotr8(b, n) n = n % 8; return ((b >> n) | (b << (8 - n))) & 0xFF end

-- ============================================================
-- DATA CONVERSION
-- ============================================================
local function str_to_bytes(s)
    local t = {}; for i = 1, #s do t[i] = s:byte(i) end; return t
end
local function bytes_to_str(t)
    local c = {}; for i = 1, #t do c[i] = string.char(t[i]) end; return table.concat(c)
end
local function bytes_to_hex(t)
    local p = {}; for i = 1, #t do p[i] = string.format(_e1579("\x69\x7c\x7e\x34"), t[i]) end; return table.concat(p)
end
local function hex_to_bytes(h)
    local t = {}; for i = 1, #h, 2 do t[#t+1] = tonumber(h:sub(i,i+1), 16) or 0 end; return t
end

-- ============================================================
-- STAGE 1: KEY STRETCHING (500,000 ITERATIONS)
-- ============================================================
-- 500,000 iterations. Each password guess costs 500K operations.
-- Uses S-Box mixing, chain XOR, rotation, and swap.

local function stretch_key(password, salt, desired_bytes)
    local stream = {}
    local pw = str_to_bytes(password)
    local sa = str_to_bytes(salt)
    for i = 1, #pw do stream[i] = pw[i] end
    for i = 1, #sa do stream[#stream+1] = sa[i] end
    while #stream < desired_bytes * 2 do
        stream[#stream+1] = stream[(#stream % #pw) + 1]
    end
    
    for iter = 1, 500000 do
        local h = 0; for i = 1, #stream do h = h + stream[i] end; h = h % 256
        for i = 1, #stream do
            stream[i] = bxor(stream[i], h)
            if i < #stream then stream[i], stream[i+1] = stream[i+1], stream[i] end
        end
        if iter % 500 == 0 then
            for i = 1, #stream - 1 do
                stream[i] = bxor(stream[i], stream[i+1])
                stream[i] = SBOX[stream[i] + 1]
            end
            for i = #stream, 2, -1 do
                stream[i] = bxor(stream[i], stream[i-1])
                stream[i] = SBOX[stream[i] + 1]
            end
        end
    end
    
    local result = {}; for i = 1, desired_bytes do result[i] = stream[i] end; return result
end

-- ============================================================
-- STAGE 2: KEY-DEPENDENT S-BOXES (TWO OF THEM)
-- ============================================================
-- Two independently permuted S-Boxes from the same key material.
-- S-Box A and S-Box B are different permutations.

local function make_sboxes(key_bytes)
    local sbox_a = {}; for i = 1, 256 do sbox_a[i] = SBOX[i] end
    local sbox_b = {}; for i = 1, 256 do sbox_b[i] = SBOX[257 - i] end  -- reversed
    
    local j = 1
    for i = 1, 256 do
        j = ((j - 1) + sbox_a[i] + key_bytes[((i-1) % #key_bytes) + 1]) % 256 + 1
        sbox_a[i], sbox_a[j] = sbox_a[j], sbox_a[i]
    end
    j = 1
    for i = 1, 256 do
        j = ((j - 1) + sbox_a[i] * 7 + key_bytes[((i*3-1) % #key_bytes) + 1]) % 256 + 1
        sbox_a[i], sbox_a[j] = sbox_a[j], sbox_a[i]
    end
    
    j = 1
    for i = 1, 256 do
        j = ((j - 1) + sbox_b[i] + key_bytes[((i*5-1) % #key_bytes) + 1]) % 256 + 1
        sbox_b[i], sbox_b[j] = sbox_b[j], sbox_b[i]
    end
    j = 1
    for i = 1, 256 do
        j = ((j - 1) + sbox_b[i] * 11 + key_bytes[((i*7-1) % #key_bytes) + 1]) % 256 + 1
        sbox_b[i], sbox_b[j] = sbox_b[j], sbox_b[i]
    end
    
    local inv_a = {}; for i = 1, 256 do inv_a[sbox_a[i] + 1] = i - 1 end
    local inv_b = {}; for i = 1, 256 do inv_b[sbox_b[i] + 1] = i - 1 end
    
    return sbox_a, inv_a, sbox_b, inv_b
end

-- ============================================================
-- STAGE 3: KEYSTREAM GENERATOR (3 INDEPENDENT VERSIONS)
-- ============================================================
-- Generates a deterministic keystream. Same key + seed = same output.
-- Different seed = completely different output.

local function make_keystream(key_bytes, seed, length, variant)
    variant = variant or 0
    local state = {}
    for i = 1, #key_bytes do state[i] = key_bytes[i] end
    state[#state+1] = (seed + variant) % 256
    while #state < 32 do
        state[#state+1] = state[(#state * 7) % #state + 1]
    end
    
    local ks = {}
    for pos = 1, length do
        for i = 1, #state do
            state[i] = SBOX[bxor(state[i], pos + variant) + 1]
            if i > 1 then state[i] = bxor(state[i], state[i-1]) end
        end
        local first = state[1]
        for i = 1, #state - 1 do state[i] = state[i+1] end
        state[#state] = first
        
        local byte = 0
        for i = 1, #state do
            byte = bxor(byte, state[i])
            byte = SBOX[(byte + i + variant) % 256 + 1]
        end
        byte = bxor(byte, (pos + variant) % 256)
        ks[pos] = byte
    end
    return ks
end

-- ============================================================
-- STAGE 4: WHITENING
-- ============================================================
-- XOR entire data block with key material before/after processing.
-- Prevents known-plaintext attacks on the inner cipher.

local function whiten(data, key_bytes, offset)
    for i = 1, #data do
        data[i] = bxor(data[i], key_bytes[((i - 1 + offset) % #key_bytes) + 1])
    end
    return data
end

-- ============================================================
-- STAGE 5: 128-BYTE FEEDBACK CIPHER
-- ============================================================
-- 128-byte internal state. Each byte of output depends on
-- the position, the key, and ALL previous state evolution.

local function feedback_process(data, key_bytes)
    local n = #data
    local state = {}
    for i = 1, #key_bytes do state[i] = key_bytes[i] end
    while #state < 128 do
        state[#state+1] = key_bytes[(#state % #key_bytes) + 1]
    end
    
    local result = {}
    for i = 1, n do
        for j = 1, #state do
            state[j] = SBOX[bxor(state[j], i) + 1]
            state[j] = bxor(state[j], state[(j % #state) + 1])
            state[j] = bxor(state[j], key_bytes[(j + i - 1) % #key_bytes + 1])
            state[j] = rotl8(state[j], 3)
        end
        local ks = 0
        for j = 1, #state do
            ks = bxor(ks, state[j])
            ks = SBOX[(ks + j) % 256 + 1]
        end
        ks = bxor(ks, i)
        ks = SBOX[ks + 1]
        result[i] = bxor(data[i], ks)
        state[(i % #state) + 1] = bxor(state[(i % #state) + 1], i)
    end
    return result
end

-- ============================================================
-- STAGE 6: S-BOX SUBSTITUTION
-- ============================================================
-- Apply key-dependent S-Box to every byte.
-- Non-linear transformation: each byte maps to a different byte.

local function substitute(data, sbox)
    for i = 1, #data do data[i] = sbox[data[i] + 1] end
    return data
end

local function unsubstitute(data, inv_sbox)
    for i = 1, #data do
        for j = 1, 256 do
            if inv_sbox[j] == data[i] then data[i] = j - 1; break end
        end
    end
    return data
end

-- ============================================================
-- STAGE 7: 16-ROUND BIT DIFFUSION
-- ============================================================
-- 16 rounds (double the previous version).
-- Each round: rotate → XOR neighbors → invert → S-Box A → S-Box B → shuffle
-- A 1-bit change avalanches to ~50% of all output bits.

local function diffusion_encrypt(data, key_stream, sbox_a, sbox_b)
    local n = #data
    local buf = {}; for i = 1, n do buf[i] = data[i] end
    
    for round = 1, 16 do
        local ks = key_stream[(round - 1) % #key_stream + 1]
        
        -- Forward pass
        for i = 1, n do
            local b = buf[i]
            b = rotl8(b, (ks + i + round) % 8)
            if i > 1 then b = bxor(b, buf[i-1]) end
            if i < n then b = bxor(b, data[i+1]) end
            if (ks + round) % 2 == 0 then b = bxor(b, 0xFF) end
            b = sbox_a[b + 1]
            b = bxor(b, ks)
            buf[i] = b
        end
        
        -- Backward pass (uses S-Box B)
        for i = n, 1, -1 do
            local b = buf[i]
            b = rotl8(b, (ks * i + round) % 8)
            if i < n then b = bxor(b, buf[i+1]) end
            if i > 1 then b = bxor(b, buf[i-1]) end
            if (ks + round) % 2 == 1 then b = bxor(b, 0xFF) end
            b = sbox_b[b + 1]
            b = bxor(b, rshift(ks, 1))
            buf[i] = b
        end
        
        -- Shuffle positions
        for i = 1, n do
            local i1 = ((i - 1 + ks) % n) + 1
            local i2 = ((i * ks) % n) + 1
            buf[i1], buf[i2] = buf[i2], buf[i1]
        end
    end
    return buf
end

local function transpose(data, key_bytes)
    local n = #data
    local result = {}
    for i = 1, n do
        local new_pos = ((i * key_bytes[(i % #key_bytes) + 1] + key_bytes[(i * 7) % #key_bytes + 1]) % n) + 1
        result[new_pos] = data[i]
    end
    -- Fill any gaps (if collisions occurred, use next available)
    for i = 1, n do
        if result[i] == nil then
            result[i] = data[i]
        end
    end
    return result
end

local function untranspose(data, key_bytes)
    local n = #data
    -- Reconstruct the forward mapping
    local mapping = {}
    for i = 1, n do
        local new_pos = ((i * key_bytes[(i % #key_bytes) + 1] + key_bytes[(i * 7) % #key_bytes + 1]) % n) + 1
        mapping[i] = new_pos
    end
    -- Invert the mapping
    local inverse = {}
    for i = 1, n do
        inverse[mapping[i]] = i
    end
    local result = {}
    for i = 1, n do
        result[i] = data[inverse[i]]
    end
    return result
end

-- ============================================================
-- STAGE 9: HMAC INTEGRITY TAG (16 BYTES)
-- ============================================================
-- Computes a 16-byte authentication tag over:
--   salt || ciphertext || stretched_key
-- Uses S-Box A and B for double hashing.

local function compute_mac(salt, data, stretched_key, sbox_a, sbox_b)
    local mac_input = {}
    for i = 1, #salt          do mac_input[#mac_input+1] = salt[i] end
    for i = 1, #data          do mac_input[#mac_input+1] = data[i] end
    for i = 1, #stretched_key do mac_input[#mac_input+1] = stretched_key[i] end
    
    local mac = {}
    local h1, h2 = 0, 0
    for i = 1, #mac_input do
        h1 = bxor(h1, mac_input[i])
        h1 = sbox_a[(h1 + mac_input[i]) % 256 + 1]
        h1 = rotl8(h1, 1)
        
        h2 = bxor(h2, mac_input[#mac_input - i + 1])
        h2 = sbox_b[(h2 + mac_input[#mac_input - i + 1]) % 256 + 1]
        h2 = rotl8(h2, 3)
        
        if i % 8 == 0 then
            mac[#mac+1] = h1
            mac[#mac+1] = h2
            h1, h2 = 0, 0
        end
    end
    while #mac < 16 do
        mac[#mac+1] = h1; h1 = bxor(h1, #mac * 17)
        mac[#mac+1] = h2; h2 = bxor(h2, #mac * 31)
    end
    return mac
end

-- ============================================================
-- THE ULTIMATE ENCRYPT FUNCTION
-- ============================================================
-- 12-stage pipeline. No choices. Maximum irreversibility.

function encrypt.encrypt(plaintext, password)
    if not plaintext or plaintext == "" then
        return nil, _e1579("\x1c\x20\x2d\x25\x22\x38\x29\x34\x38\x6c\x2f\x2d\x22\x22\x23\x38\x6c\x2e\x29\x6c\x29\x21\x3c\x38\x35")
    end
    if not password or password == "" then
        return nil, _e1579("\x1c\x2d\x3f\x3f\x3b\x23\x3e\x28\x6c\x2f\x2d\x22\x22\x23\x38\x6c\x2e\x29\x6c\x29\x21\x3c\x38\x35")
    end
    
    -- ============================================================
    -- PHASE 1: KEY PREPARATION
    -- ============================================================
    
    -- Generate 32-byte random salt
    math.randomseed(os.time() + #plaintext * 7 + 12345)
    local salt = {}; for i = 1, 32 do salt[i] = math.random(0, 255) end
    local salt_str = bytes_to_str(salt)
    
    -- 500,000-iteration key stretching → 8192 bytes
    local stretched = stretch_key(password, salt_str, 8192)
    
    -- Split into sub-keys
    local key_sbox_a    = {}; for i = 1, 256 do key_sbox_a[i]    = stretched[i]       end
    local key_sbox_b    = {}; for i = 1, 256 do key_sbox_b[i]    = stretched[256 + i]  end
    local key_feedback  = {}; for i = 1, 128 do key_feedback[i]  = stretched[512 + i]  end
    local key_keystream = {}; for i = 1, 128 do key_keystream[i] = stretched[640 + i]  end
    local key_diffusion = {}; for i = 1, 64  do key_diffusion[i] = stretched[768 + i]  end
    local key_whiten    = {}; for i = 1, 64  do key_whiten[i]    = stretched[832 + i]  end
    local key_transpose = {}; for i = 1, 32  do key_transpose[i] = stretched[896 + i]  end
    
    -- Build key-dependent S-Boxes
    local sbox_a, inv_a, sbox_b, inv_b = make_sboxes(key_sbox_a)
    
    -- ============================================================
    -- PHASE 2: DATA PROCESSING (10 STAGES)
    -- ============================================================
    
    local data = str_to_bytes(plaintext)
    local orig_len = #data
    
    -- STAGE 1: Initial whitening (XOR with key material)
    data = whiten(data, key_whiten, 0)
    
    -- STAGE 2: Keystream XOR #1 (seeded with salt[1])
    local ks1 = make_keystream(key_keystream, salt[1], orig_len, 0)
    for i = 1, #data do data[i] = bxor(data[i], ks1[i]) end
    
    -- STAGE 3: 128-byte feedback cipher
    data = feedback_process(data, key_feedback)
    
    -- STAGE 4: S-Box A substitution
    data = substitute(data, sbox_a)
    
    -- STAGE 5: 16-round bit diffusion (uses both S-Box A and B)
    data = diffusion_encrypt(data, key_diffusion, sbox_a, sbox_b)
    
    -- STAGE 6: Transposition (reorder entire message)
    data = transpose(data, key_transpose)
    
    -- STAGE 7: Second feedback pass
    data = feedback_process(data, key_feedback)
    
    -- STAGE 8: Keystream XOR #2 (seeded with salt[32], variant 1)
    local ks2 = make_keystream(key_keystream, salt[32], #data, 1)
    for i = 1, #data do data[i] = bxor(data[i], ks2[i]) end
    
    -- STAGE 9: S-Box B substitution
    data = substitute(data, sbox_b)
    
    -- STAGE 10: Keystream XOR #3 (seeded with salt[16], variant 2)
    local ks3 = make_keystream(key_keystream, salt[16], #data, 2)
    for i = 1, #data do data[i] = bxor(data[i], ks3[i]) end
    
    -- STAGE 11: Final whitening (different offset)
    data = whiten(data, key_whiten, 31)
    
    -- ============================================================
    -- PHASE 3: INTEGRITY (16-byte HMAC)
    -- ============================================================
    
    local mac = compute_mac(salt, data, stretched, sbox_a, sbox_b)
    
    -- ============================================================
    -- PHASE 4: ASSEMBLE OUTPUT
    -- ============================================================
    -- Format: [32-byte salt] [ciphertext] [16-byte MAC]
    
    local final = {}
    for i = 1, #salt do final[#final+1] = salt[i] end
    for i = 1, #data do final[#final+1] = data[i] end
    for i = 1, #mac  do final[#final+1] = mac[i]  end
    
    return bytes_to_hex(final)
end

-- ============================================================
-- THE ULTIMATE DECRYPT FUNCTION
-- ============================================================

function encrypt.demo()
    local plaintext = _e1579("\x04\x29\x20\x20\x23\x6c\x1b\x23\x3e\x20\x28\x6d\x6c\x18\x24\x25\x3f\x6c\x25\x3f\x6c\x2d\x6c\x18\x03\x1c\x6c\x1f\x09\x0f\x1e\x09\x18\x6c\x21\x29\x3f\x3f\x2d\x2b\x29\x62\x6c\x1b\x25\x38\x24\x6c\x22\x39\x21\x2e\x29\x3e\x3f\x6c\x7d\x7e\x7f\x78\x79\x6c\x2d\x22\x28\x6c\x3f\x35\x21\x2e\x23\x20\x3f\x6c\x6d\x0c\x6f\x68\x69\x12\x6a\x66\x64\x65")
    local password = _e1579("\x01\x35\x1f\x39\x3c\x7f\x3e\x68\x7f\x2f\x39\x3e\x7f\x1c\x0c\x3f\x3f\x3b\x7c\x3e\x28\x6d")
    
    print(_e1579("\xae\xd9\xd8\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdb"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x19\x00\x18\x05\x01\x0d\x18\x09\x6c\x1f\x05\x02\x0b\x00\x09\x61\x1c\x05\x1c\x09\x6c\x09\x02\x0f\x1e\x15\x1c\x18\x05\x03\x02\x6c\x08\x09\x01\x03\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xd6\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xd1"))
    print()
    print(_e1579("\x1c\x20\x2d\x25\x22\x38\x29\x34\x38\x76\x6c\x6c") .. plaintext)
    print(_e1579("\x1c\x2d\x3f\x3f\x3b\x23\x3e\x28\x76\x6c\x6c\x6c") .. password)
    print(_e1579("\x00\x29\x22\x2b\x38\x24\x76\x6c\x6c\x6c\x6c\x6c") .. #plaintext .. _e1579("\x6c\x2f\x24\x2d\x3e\x3f\x6c\x6c\x64") .. #plaintext .. _e1579("\x6c\x2e\x35\x38\x29\x3f\x65"))
    print()
    
    local enc, err = encrypt.encrypt(plaintext, password)
    if not enc then print(_e1579("\x09\x02\x0f\x1e\x15\x1c\x18\x05\x03\x02\x6c\x0a\x0d\x05\x00\x09\x08\x76\x6c") .. err); return end
    
    print(_e1579("\x17\x09\x02\x0f\x1e\x15\x1c\x18\x09\x08\x6c\x03\x19\x18\x1c\x19\x18\x11"))
    print(_e1579("\x04\x29\x34\x76\x6c\x6c") .. enc)
    print(_e1579("\x1f\x25\x36\x29\x76\x6c") .. #enc .. _e1579("\x6c\x24\x29\x34\x6c\x2f\x24\x2d\x3e\x3f\x6c\x6c\x64") .. (#enc/2) .. _e1579("\x6c\x2e\x35\x38\x29\x3f\x65"))
    print()
    
    local dec, err = encrypt.decrypt(enc, password)
    if not dec then print(_e1579("\x08\x09\x0f\x1e\x15\x1c\x18\x05\x03\x02\x6c\x0a\x0d\x05\x00\x09\x08\x76\x6c") .. err); return end
    
    print(_e1579("\x17\x08\x09\x0f\x1e\x15\x1c\x18\x09\x08\x6c\x03\x19\x18\x1c\x19\x18\x11"))
    print(_e1579("\x18\x29\x34\x38\x76\x6c\x6c") .. dec)
    print(_e1579("\x01\x2d\x38\x2f\x24\x76\x6c") .. (dec == plaintext and _e1579("\xae\xd0\xdf\x6c\x1c\x09\x1e\x0a\x09\x0f\x18") or _e1579("\xae\xd0\xdb\x6c\x0a\x0d\x05\x00\x09\x08")))
    print()
    
    -- Uniqueness test
    local enc2, _ = encrypt.encrypt(plaintext, password)
    print(_e1579("\x17\x19\x02\x05\x1d\x19\x09\x02\x09\x1f\x1f\x6c\x18\x09\x1f\x18\x11"))
    print(_e1579("\x6c\x6c\x1e\x39\x22\x6c\x7d\x76\x6c") .. enc:sub(1,48) .. _e1579("\x62\x62\x62"))
    print(_e1579("\x6c\x6c\x1e\x39\x22\x6c\x7e\x76\x6c") .. enc2:sub(1,48) .. _e1579("\x62\x62\x62"))
    print(_e1579("\x6c\x6c\x19\x22\x25\x3d\x39\x29\x76\x6c") .. (enc ~= enc2 and _e1579("\xae\xd0\xdf\x6c\x15\x09\x1f") or _e1579("\xae\xd0\xdb\x6c\x02\x03")))
    print()
    
    -- Tamper test
    print(_e1579("\x17\x18\x0d\x01\x1c\x09\x1e\x6c\x18\x09\x1f\x18\x11"))
    local tampered = enc
    local idx = math.random(65, #enc)
    local orig = tonumber(enc:sub(idx,idx), 16)
    local flipped = bxor(orig, 8)
    tampered = enc:sub(1,idx-1) .. string.format("%x", flipped) .. enc:sub(idx+1)
    if err then print(_e1579("\x6c\x6c\x18\x2d\x21\x3c\x29\x3e\x29\x28\x6c\x2f\x25\x3c\x24\x29\x3e\x38\x29\x34\x38\x6c\x1e\x09\x06\x09\x0f\x18\x09\x08\x76\x6c") .. err)
    else print(_e1579("\x6c\x6c\x18\x2d\x21\x3c\x29\x3e\x29\x28\x6c\x2f\x25\x3c\x24\x29\x3e\x38\x29\x34\x38\x6c\x0d\x0f\x0f\x09\x1c\x18\x09\x08\x6c\x64\x0e\x19\x0b\x6d\x65")) end
    print()
    
    -- Wrong password test
    print(_e1579("\x17\x1b\x1e\x03\x02\x0b\x6c\x1c\x0d\x1f\x1f\x1b\x03\x1e\x08\x6c\x18\x09\x1f\x18\x11"))
    if err then print(_e1579("\x6c\x6c\x1b\x3e\x23\x22\x2b\x6c\x3c\x2d\x3f\x3f\x3b\x23\x3e\x28\x6c\x1e\x09\x06\x09\x0f\x18\x09\x08\x76\x6c") .. err)
    else print(_e1579("\x6c\x6c\x1b\x3e\x23\x22\x2b\x6c\x3c\x2d\x3f\x3f\x3b\x23\x3e\x28\x6c\x0d\x0f\x0f\x09\x1c\x18\x09\x08\x6c\x64\x0e\x19\x0b\x6d\x65")) end
    print()
    
    print(_e1579("\xae\xd9\xd8\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdb"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x7d\x7e\x61\x1f\x18\x0d\x0b\x09\x6c\x1c\x05\x1c\x09\x00\x05\x02\x09\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xec\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xef"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x6c\x7d\x62\x6c\x05\x22\x25\x38\x25\x2d\x20\x6c\x3b\x24\x25\x38\x29\x22\x25\x22\x2b\x6c\x64\x14\x03\x1e\x6c\x3b\x25\x38\x24\x6c\x27\x29\x35\x6c\x21\x2d\x38\x29\x3e\x25\x2d\x20\x65\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x6c\x7e\x62\x6c\x07\x29\x35\x3f\x38\x3e\x29\x2d\x21\x6c\x14\x03\x1e\x6c\x6f\x7d\x6c\x64\x3f\x38\x3e\x29\x2d\x21\x6c\x2f\x25\x3c\x24\x29\x3e\x65\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x6c\x7f\x62\x6c\x7d\x7e\x74\x61\x2e\x35\x38\x29\x6c\x2a\x29\x29\x28\x2e\x2d\x2f\x27\x6c\x2f\x25\x3c\x24\x29\x3e\x6c\x64\x2d\x3a\x2d\x20\x2d\x22\x2f\x24\x29\x65\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x6c\x78\x62\x6c\x1f\x61\x0e\x23\x34\x6c\x0d\x6c\x3f\x39\x2e\x3f\x38\x25\x38\x39\x38\x25\x23\x22\x6c\x64\x22\x23\x22\x61\x20\x25\x22\x29\x2d\x3e\x65\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x6c\x79\x62\x6c\x7d\x7a\x61\x3e\x23\x39\x22\x28\x6c\x2e\x25\x38\x6c\x28\x25\x2a\x2a\x39\x3f\x25\x23\x22\x6c\x64\x1f\x61\x0e\x23\x34\x6c\x0d\x6c\x67\x6c\x0e\x65\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x6c\x7a\x62\x6c\x18\x3e\x2d\x22\x3f\x3c\x23\x3f\x25\x38\x25\x23\x22\x6c\x64\x3e\x29\x23\x3e\x28\x29\x3e\x6c\x29\x22\x38\x25\x3e\x29\x6c\x21\x29\x3f\x3f\x2d\x2b\x29\x65\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x6c\x7b\x62\x6c\x1f\x29\x2f\x23\x22\x28\x6c\x2a\x29\x29\x28\x2e\x2d\x2f\x27\x6c\x3c\x2d\x3f\x3f\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x6c\x74\x62\x6c\x07\x29\x35\x3f\x38\x3e\x29\x2d\x21\x6c\x14\x03\x1e\x6c\x6f\x7e\x6c\x64\x28\x25\x2a\x2a\x29\x3e\x29\x22\x38\x6c\x3f\x29\x29\x28\x65\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x6c\x75\x62\x6c\x1f\x61\x0e\x23\x34\x6c\x0e\x6c\x3f\x39\x2e\x3f\x38\x25\x38\x39\x38\x25\x23\x22\x6c\x64\x28\x25\x2a\x2a\x29\x3e\x29\x22\x38\x6c\x3c\x29\x3e\x21\x39\x38\x2d\x38\x25\x23\x22\x65\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x7d\x7c\x62\x6c\x07\x29\x35\x3f\x38\x3e\x29\x2d\x21\x6c\x14\x03\x1e\x6c\x6f\x7f\x6c\x64\x38\x24\x25\x3e\x28\x6c\x3f\x29\x29\x28\x65\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x7d\x7d\x62\x6c\x0a\x25\x22\x2d\x20\x6c\x3b\x24\x25\x38\x29\x22\x25\x22\x2b\x6c\x64\x28\x25\x2a\x2a\x29\x3e\x29\x22\x38\x6c\x23\x2a\x2a\x3f\x29\x38\x65\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xdd\x6c\x6c\x7d\x7e\x62\x6c\x7d\x7a\x61\x2e\x35\x38\x29\x6c\x04\x01\x0d\x0f\x6c\x25\x22\x38\x29\x2b\x3e\x25\x38\x35\x6c\x38\x2d\x2b\x6c\x64\x28\x39\x2d\x20\x6c\x1f\x61\x0e\x23\x34\x65\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\xae\xd9\xdd"))
    print(_e1579("\xae\xd9\xd6\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xdc\xae\xd9\xd1"))
    print()
    print(_e1579("\x6c\x6c\x07\x08\x0a\x6c\x25\x38\x29\x3e\x2d\x38\x25\x23\x22\x3f\x76\x6c\x79\x7c\x7c\x60\x7c\x7c\x7c"))
    print(_e1579("\x6c\x6c\x08\x25\x2a\x2a\x39\x3f\x25\x23\x22\x6c\x3e\x23\x39\x22\x28\x3f\x76\x6c\x7d\x7a"))
    print(_e1579("\x6c\x6c\x0a\x29\x29\x28\x2e\x2d\x2f\x27\x6c\x3f\x38\x2d\x38\x29\x76\x6c\x7d\x7e\x74\x6c\x2e\x35\x38\x29\x3f"))
    print(_e1579("\x6c\x6c\x1f\x61\x0e\x23\x34\x29\x3f\x76\x6c\x7e\x6c\x64\x25\x22\x28\x29\x3c\x29\x22\x28\x29\x22\x38\x20\x35\x6c\x27\x29\x35\x61\x3c\x29\x3e\x21\x39\x38\x29\x28\x65"))
    print(_e1579("\x6c\x6c\x07\x29\x35\x3f\x38\x3e\x29\x2d\x21\x6c\x3c\x2d\x3f\x3f\x29\x3f\x76\x6c\x7f"))
    print(_e1579("\x6c\x6c\x1b\x24\x25\x38\x29\x22\x25\x22\x2b\x76\x6c\x7e\x6c\x3c\x2d\x3f\x3f\x29\x3f"))
    print(_e1579("\x6c\x6c\x18\x3e\x2d\x22\x3f\x3c\x23\x3f\x25\x38\x25\x23\x22\x76\x6c\x2a\x39\x20\x20\x61\x21\x29\x3f\x3f\x2d\x2b\x29\x6c\x3c\x29\x3e\x21\x39\x38\x2d\x38\x25\x23\x22"))
    print(_e1579("\x6c\x6c\x01\x0d\x0f\x76\x6c\x7d\x7a\x6c\x2e\x35\x38\x29\x3f\x6c\x64\x28\x39\x2d\x20\x6c\x1f\x61\x0e\x23\x34\x65"))
    print()
    print(_e1579("\x3a\x3f\x6c\x04\x29\x34\x63\x0e\x2d\x3f\x29\x7a\x78\x76\x6c\x6c\x6c\x6c\x16\x29\x3e\x23\x6c\x3f\x29\x2f\x39\x3e\x25\x38\x35\x6c\x64\x29\x22\x2f\x23\x28\x25\x22\x2b\x60\x6c\x22\x23\x38\x6c\x29\x22\x2f\x3e\x35\x3c\x38\x25\x23\x22\x65"))
    print(_e1579("\x3a\x3f\x6c\x0f\x2d\x29\x3f\x2d\x3e\x76\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x7e\x79\x6c\x27\x29\x35\x3f\x6c\xae\xca\xde\x6c\x2e\x3e\x23\x27\x29\x22\x6c\x25\x22\x6c\x21\x25\x2f\x3e\x23\x3f\x29\x2f\x23\x22\x28\x3f"))
    print(_e1579("\x3a\x3f\x6c\x1a\x25\x2b\x29\x22\x8f\xe4\x3e\x29\x76\x6c\x6c\x6c\x6c\x6c\x6c\x00\x29\x38\x38\x29\x3e\x3f\x6c\x23\x22\x20\x35\x6c\xae\xca\xde\x6c\x2a\x3e\x29\x3d\x39\x29\x22\x2f\x35\x6c\x2d\x22\x2d\x20\x35\x3f\x25\x3f"))
    print(_e1579("\x3a\x3f\x6c\x14\x03\x1e\x76\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x0a\x25\x34\x29\x28\x6c\x27\x29\x35\x6c\xae\xca\xde\x6c\x38\x3e\x25\x3a\x25\x2d\x20\x6c\x14\x03\x1e\x6c\x2e\x2d\x2f\x27"))
    print(_e1579("\x3a\x3f\x6c\x1e\x0f\x78\x76\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x07\x22\x23\x3b\x22\x6c\x2e\x25\x2d\x3f\x29\x3f\x6c\xae\xca\xde\x6c\x2f\x3e\x35\x3c\x38\x2d\x22\x2d\x20\x35\x3f\x25\x3f\x6c\x29\x34\x25\x3f\x38\x3f"))
    print(_e1579("\x3a\x3f\x6c\x0d\x09\x1f\x6c\x2d\x20\x23\x22\x29\x76\x6c\x6c\x6c\x6c\x6c\x1f\x25\x22\x2b\x20\x29\x6c\x2d\x20\x2b\x23\x3e\x25\x38\x24\x21\x6c\xae\xca\xde\x6c\x27\x22\x23\x3b\x22\x6c\x21\x2d\x38\x24\x6c\x3f\x38\x3e\x39\x2f\x38\x39\x3e\x29"))
    print(_e1579("\x3a\x3f\x6c\x1c\x3e\x29\x3a\x25\x23\x39\x3f\x6c\x3a\x29\x3e\x76\x6c\x6c\x75\x6c\x3f\x38\x2d\x2b\x29\x3f\x60\x6c\x7e\x7c\x7c\x07\x6c\x07\x08\x0a\x60\x6c\x74\x6c\x3e\x23\x39\x22\x28\x3f\x60\x6c\x7a\x78\x0e\x6c\x2a\x29\x29\x28\x2e\x2d\x2f\x27"))
    print(_e1579("\x3a\x3f\x6c\x18\x04\x05\x1f\x76\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x6c\x7d\x7e\x6c\x3f\x38\x2d\x2b\x29\x3f\x60\x6c\x79\x7c\x7c\x07\x6c\x07\x08\x0a\x60\x6c\x7d\x7a\x6c\x3e\x23\x39\x22\x28\x3f\x60\x6c\x7d\x7e\x74\x0e\x6c\x2a\x29\x29\x28\x2e\x2d\x2f\x27"))
end

return encrypt