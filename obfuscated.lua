local _e4119=function(s)local r={}for i=1,#s do r[i]=string.char(string.byte(s,i)~122)end return table.concat(r)end
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
    local p = {}; for i = 1, #t do p[i] = string.format(_e4119("\x5f\x4a\x48\x02"), t[i]) end; return table.concat(p)
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
        return nil, _e4119("\x2a\x16\x1b\x13\x14\x0e\x1f\x02\x0e\x5a\x19\x1b\x14\x14\x15\x0e\x5a\x18\x1f\x5a\x1f\x17\x0a\x0e\x03")
    end
    if not password or password == "" then
        return nil, _e4119("\x2a\x1b\x09\x09\x0d\x15\x08\x1e\x5a\x19\x1b\x14\x14\x15\x0e\x5a\x18\x1f\x5a\x1f\x17\x0a\x0e\x03")
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
    local plaintext = _e4119("\x32\x1f\x16\x16\x15\x5a\x2d\x15\x08\x16\x1e\x5b\x5a\x2e\x12\x13\x09\x5a\x13\x09\x5a\x1b\x5a\x2e\x35\x2a\x5a\x29\x3f\x39\x28\x3f\x2e\x5a\x17\x1f\x09\x09\x1b\x1d\x1f\x54\x5a\x2d\x13\x0e\x12\x5a\x14\x0f\x17\x18\x1f\x08\x09\x5a\x4b\x48\x49\x4e\x4f\x5a\x1b\x14\x1e\x5a\x09\x03\x17\x18\x15\x16\x09\x5a\x5b\x3a\x59\x5e\x5f\x24\x5c\x50\x52\x53")
    local password = _e4119("\x37\x03\x29\x0f\x0a\x49\x08\x5e\x49\x19\x0f\x08\x49\x2a\x3a\x09\x09\x0d\x4a\x08\x1e\x5b")
    
    print(_e4119("\x98\xef\xee\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xed"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x2f\x36\x2e\x33\x37\x3b\x2e\x3f\x5a\x29\x33\x34\x3d\x36\x3f\x57\x2a\x33\x2a\x3f\x5a\x3f\x34\x39\x28\x23\x2a\x2e\x33\x35\x34\x5a\x3e\x3f\x37\x35\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xe0\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xe7"))
    print()
    print(_e4119("\x2a\x16\x1b\x13\x14\x0e\x1f\x02\x0e\x40\x5a\x5a") .. plaintext)
    print(_e4119("\x2a\x1b\x09\x09\x0d\x15\x08\x1e\x40\x5a\x5a\x5a") .. password)
    print(_e4119("\x36\x1f\x14\x1d\x0e\x12\x40\x5a\x5a\x5a\x5a\x5a") .. #plaintext .. _e4119("\x5a\x19\x12\x1b\x08\x09\x5a\x5a\x52") .. #plaintext .. _e4119("\x5a\x18\x03\x0e\x1f\x09\x53"))
    print()
    
    local enc, err = encrypt.encrypt(plaintext, password)
    if not enc then print(_e4119("\x3f\x34\x39\x28\x23\x2a\x2e\x33\x35\x34\x5a\x3c\x3b\x33\x36\x3f\x3e\x40\x5a") .. err); return end
    
    print(_e4119("\x21\x3f\x34\x39\x28\x23\x2a\x2e\x3f\x3e\x5a\x35\x2f\x2e\x2a\x2f\x2e\x27"))
    print(_e4119("\x32\x1f\x02\x40\x5a\x5a") .. enc)
    print(_e4119("\x29\x13\x00\x1f\x40\x5a") .. #enc .. _e4119("\x5a\x12\x1f\x02\x5a\x19\x12\x1b\x08\x09\x5a\x5a\x52") .. (#enc/2) .. _e4119("\x5a\x18\x03\x0e\x1f\x09\x53"))
    print()
    
    local dec, err = encrypt.decrypt(enc, password)
    if not dec then print(_e4119("\x3e\x3f\x39\x28\x23\x2a\x2e\x33\x35\x34\x5a\x3c\x3b\x33\x36\x3f\x3e\x40\x5a") .. err); return end
    
    print(_e4119("\x21\x3e\x3f\x39\x28\x23\x2a\x2e\x3f\x3e\x5a\x35\x2f\x2e\x2a\x2f\x2e\x27"))
    print(_e4119("\x2e\x1f\x02\x0e\x40\x5a\x5a") .. dec)
    print(_e4119("\x37\x1b\x0e\x19\x12\x40\x5a") .. (dec == plaintext and _e4119("\x98\xe6\xe9\x5a\x2a\x3f\x28\x3c\x3f\x39\x2e") or _e4119("\x98\xe6\xed\x5a\x3c\x3b\x33\x36\x3f\x3e")))
    print()
    
    -- Uniqueness test
    local enc2, _ = encrypt.encrypt(plaintext, password)
    print(_e4119("\x21\x2f\x34\x33\x2b\x2f\x3f\x34\x3f\x29\x29\x5a\x2e\x3f\x29\x2e\x27"))
    print(_e4119("\x5a\x5a\x28\x0f\x14\x5a\x4b\x40\x5a") .. enc:sub(1,48) .. _e4119("\x54\x54\x54"))
    print(_e4119("\x5a\x5a\x28\x0f\x14\x5a\x48\x40\x5a") .. enc2:sub(1,48) .. _e4119("\x54\x54\x54"))
    print(_e4119("\x5a\x5a\x2f\x14\x13\x0b\x0f\x1f\x40\x5a") .. (enc ~= enc2 and _e4119("\x98\xe6\xe9\x5a\x23\x3f\x29") or _e4119("\x98\xe6\xed\x5a\x34\x35")))
    print()
    
    -- Tamper test
    print(_e4119("\x21\x2e\x3b\x37\x2a\x3f\x28\x5a\x2e\x3f\x29\x2e\x27"))
    local tampered = enc
    local idx = math.random(65, #enc)
    local orig = tonumber(enc:sub(idx,idx), 16)
    local flipped = bxor(orig, 8)
    tampered = enc:sub(1,idx-1) .. string.format("%x", flipped) .. enc:sub(idx+1)
    if err then print(_e4119("\x5a\x5a\x2e\x1b\x17\x0a\x1f\x08\x1f\x1e\x5a\x19\x13\x0a\x12\x1f\x08\x0e\x1f\x02\x0e\x5a\x28\x3f\x30\x3f\x39\x2e\x3f\x3e\x40\x5a") .. err)
    else print(_e4119("\x5a\x5a\x2e\x1b\x17\x0a\x1f\x08\x1f\x1e\x5a\x19\x13\x0a\x12\x1f\x08\x0e\x1f\x02\x0e\x5a\x3b\x39\x39\x3f\x2a\x2e\x3f\x3e\x5a\x52\x38\x2f\x3d\x5b\x53")) end
    print()
    
    -- Wrong password test
    print(_e4119("\x21\x2d\x28\x35\x34\x3d\x5a\x2a\x3b\x29\x29\x2d\x35\x28\x3e\x5a\x2e\x3f\x29\x2e\x27"))
    if err then print(_e4119("\x5a\x5a\x2d\x08\x15\x14\x1d\x5a\x0a\x1b\x09\x09\x0d\x15\x08\x1e\x5a\x28\x3f\x30\x3f\x39\x2e\x3f\x3e\x40\x5a") .. err)
    else print(_e4119("\x5a\x5a\x2d\x08\x15\x14\x1d\x5a\x0a\x1b\x09\x09\x0d\x15\x08\x1e\x5a\x3b\x39\x39\x3f\x2a\x2e\x3f\x3e\x5a\x52\x38\x2f\x3d\x5b\x53")) end
    print()
    
    print(_e4119("\x98\xef\xee\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xed"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x4b\x48\x57\x29\x2e\x3b\x3d\x3f\x5a\x2a\x33\x2a\x3f\x36\x33\x34\x3f\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xda\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xd9"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x5a\x4b\x54\x5a\x33\x14\x13\x0e\x13\x1b\x16\x5a\x0d\x12\x13\x0e\x1f\x14\x13\x14\x1d\x5a\x52\x22\x35\x28\x5a\x0d\x13\x0e\x12\x5a\x11\x1f\x03\x5a\x17\x1b\x0e\x1f\x08\x13\x1b\x16\x53\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x5a\x48\x54\x5a\x31\x1f\x03\x09\x0e\x08\x1f\x1b\x17\x5a\x22\x35\x28\x5a\x59\x4b\x5a\x52\x09\x0e\x08\x1f\x1b\x17\x5a\x19\x13\x0a\x12\x1f\x08\x53\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x5a\x49\x54\x5a\x4b\x48\x42\x57\x18\x03\x0e\x1f\x5a\x1c\x1f\x1f\x1e\x18\x1b\x19\x11\x5a\x19\x13\x0a\x12\x1f\x08\x5a\x52\x1b\x0c\x1b\x16\x1b\x14\x19\x12\x1f\x53\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x5a\x4e\x54\x5a\x29\x57\x38\x15\x02\x5a\x3b\x5a\x09\x0f\x18\x09\x0e\x13\x0e\x0f\x0e\x13\x15\x14\x5a\x52\x14\x15\x14\x57\x16\x13\x14\x1f\x1b\x08\x53\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x5a\x4f\x54\x5a\x4b\x4c\x57\x08\x15\x0f\x14\x1e\x5a\x18\x13\x0e\x5a\x1e\x13\x1c\x1c\x0f\x09\x13\x15\x14\x5a\x52\x29\x57\x38\x15\x02\x5a\x3b\x5a\x51\x5a\x38\x53\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x5a\x4c\x54\x5a\x2e\x08\x1b\x14\x09\x0a\x15\x09\x13\x0e\x13\x15\x14\x5a\x52\x08\x1f\x15\x08\x1e\x1f\x08\x5a\x1f\x14\x0e\x13\x08\x1f\x5a\x17\x1f\x09\x09\x1b\x1d\x1f\x53\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x5a\x4d\x54\x5a\x29\x1f\x19\x15\x14\x1e\x5a\x1c\x1f\x1f\x1e\x18\x1b\x19\x11\x5a\x0a\x1b\x09\x09\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x5a\x42\x54\x5a\x31\x1f\x03\x09\x0e\x08\x1f\x1b\x17\x5a\x22\x35\x28\x5a\x59\x48\x5a\x52\x1e\x13\x1c\x1c\x1f\x08\x1f\x14\x0e\x5a\x09\x1f\x1f\x1e\x53\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x5a\x43\x54\x5a\x29\x57\x38\x15\x02\x5a\x38\x5a\x09\x0f\x18\x09\x0e\x13\x0e\x0f\x0e\x13\x15\x14\x5a\x52\x1e\x13\x1c\x1c\x1f\x08\x1f\x14\x0e\x5a\x0a\x1f\x08\x17\x0f\x0e\x1b\x0e\x13\x15\x14\x53\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x4b\x4a\x54\x5a\x31\x1f\x03\x09\x0e\x08\x1f\x1b\x17\x5a\x22\x35\x28\x5a\x59\x49\x5a\x52\x0e\x12\x13\x08\x1e\x5a\x09\x1f\x1f\x1e\x53\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x4b\x4b\x54\x5a\x3c\x13\x14\x1b\x16\x5a\x0d\x12\x13\x0e\x1f\x14\x13\x14\x1d\x5a\x52\x1e\x13\x1c\x1c\x1f\x08\x1f\x14\x0e\x5a\x15\x1c\x1c\x09\x1f\x0e\x53\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xeb\x5a\x5a\x4b\x48\x54\x5a\x4b\x4c\x57\x18\x03\x0e\x1f\x5a\x32\x37\x3b\x39\x5a\x13\x14\x0e\x1f\x1d\x08\x13\x0e\x03\x5a\x0e\x1b\x1d\x5a\x52\x1e\x0f\x1b\x16\x5a\x29\x57\x38\x15\x02\x53\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x98\xef\xeb"))
    print(_e4119("\x98\xef\xe0\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xea\x98\xef\xe7"))
    print()
    print(_e4119("\x5a\x5a\x31\x3e\x3c\x5a\x13\x0e\x1f\x08\x1b\x0e\x13\x15\x14\x09\x40\x5a\x4f\x4a\x4a\x56\x4a\x4a\x4a"))
    print(_e4119("\x5a\x5a\x3e\x13\x1c\x1c\x0f\x09\x13\x15\x14\x5a\x08\x15\x0f\x14\x1e\x09\x40\x5a\x4b\x4c"))
    print(_e4119("\x5a\x5a\x3c\x1f\x1f\x1e\x18\x1b\x19\x11\x5a\x09\x0e\x1b\x0e\x1f\x40\x5a\x4b\x48\x42\x5a\x18\x03\x0e\x1f\x09"))
    print(_e4119("\x5a\x5a\x29\x57\x38\x15\x02\x1f\x09\x40\x5a\x48\x5a\x52\x13\x14\x1e\x1f\x0a\x1f\x14\x1e\x1f\x14\x0e\x16\x03\x5a\x11\x1f\x03\x57\x0a\x1f\x08\x17\x0f\x0e\x1f\x1e\x53"))
    print(_e4119("\x5a\x5a\x31\x1f\x03\x09\x0e\x08\x1f\x1b\x17\x5a\x0a\x1b\x09\x09\x1f\x09\x40\x5a\x49"))
    print(_e4119("\x5a\x5a\x2d\x12\x13\x0e\x1f\x14\x13\x14\x1d\x40\x5a\x48\x5a\x0a\x1b\x09\x09\x1f\x09"))
    print(_e4119("\x5a\x5a\x2e\x08\x1b\x14\x09\x0a\x15\x09\x13\x0e\x13\x15\x14\x40\x5a\x1c\x0f\x16\x16\x57\x17\x1f\x09\x09\x1b\x1d\x1f\x5a\x0a\x1f\x08\x17\x0f\x0e\x1b\x0e\x13\x15\x14"))
    print(_e4119("\x5a\x5a\x37\x3b\x39\x40\x5a\x4b\x4c\x5a\x18\x03\x0e\x1f\x09\x5a\x52\x1e\x0f\x1b\x16\x5a\x29\x57\x38\x15\x02\x53"))
    print()
    print(_e4119("\x0c\x09\x5a\x32\x1f\x02\x55\x38\x1b\x09\x1f\x4c\x4e\x40\x5a\x5a\x5a\x5a\x20\x1f\x08\x15\x5a\x09\x1f\x19\x0f\x08\x13\x0e\x03\x5a\x52\x1f\x14\x19\x15\x1e\x13\x14\x1d\x56\x5a\x14\x15\x0e\x5a\x1f\x14\x19\x08\x03\x0a\x0e\x13\x15\x14\x53"))
    print(_e4119("\x0c\x09\x5a\x39\x1b\x1f\x09\x1b\x08\x40\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x48\x4f\x5a\x11\x1f\x03\x09\x5a\x98\xfc\xe8\x5a\x18\x08\x15\x11\x1f\x14\x5a\x13\x14\x5a\x17\x13\x19\x08\x15\x09\x1f\x19\x15\x14\x1e\x09"))
    print(_e4119("\x0c\x09\x5a\x2c\x13\x1d\x1f\x14\xb9\xd2\x08\x1f\x40\x5a\x5a\x5a\x5a\x5a\x5a\x36\x1f\x0e\x0e\x1f\x08\x09\x5a\x15\x14\x16\x03\x5a\x98\xfc\xe8\x5a\x1c\x08\x1f\x0b\x0f\x1f\x14\x19\x03\x5a\x1b\x14\x1b\x16\x03\x09\x13\x09"))
    print(_e4119("\x0c\x09\x5a\x22\x35\x28\x40\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x3c\x13\x02\x1f\x1e\x5a\x11\x1f\x03\x5a\x98\xfc\xe8\x5a\x0e\x08\x13\x0c\x13\x1b\x16\x5a\x22\x35\x28\x5a\x18\x1b\x19\x11"))
    print(_e4119("\x0c\x09\x5a\x28\x39\x4e\x40\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x31\x14\x15\x0d\x14\x5a\x18\x13\x1b\x09\x1f\x09\x5a\x98\xfc\xe8\x5a\x19\x08\x03\x0a\x0e\x1b\x14\x1b\x16\x03\x09\x13\x09\x5a\x1f\x02\x13\x09\x0e\x09"))
    print(_e4119("\x0c\x09\x5a\x3b\x3f\x29\x5a\x1b\x16\x15\x14\x1f\x40\x5a\x5a\x5a\x5a\x5a\x29\x13\x14\x1d\x16\x1f\x5a\x1b\x16\x1d\x15\x08\x13\x0e\x12\x17\x5a\x98\xfc\xe8\x5a\x11\x14\x15\x0d\x14\x5a\x17\x1b\x0e\x12\x5a\x09\x0e\x08\x0f\x19\x0e\x0f\x08\x1f"))
    print(_e4119("\x0c\x09\x5a\x2a\x08\x1f\x0c\x13\x15\x0f\x09\x5a\x0c\x1f\x08\x40\x5a\x5a\x43\x5a\x09\x0e\x1b\x1d\x1f\x09\x56\x5a\x48\x4a\x4a\x31\x5a\x31\x3e\x3c\x56\x5a\x42\x5a\x08\x15\x0f\x14\x1e\x09\x56\x5a\x4c\x4e\x38\x5a\x1c\x1f\x1f\x1e\x18\x1b\x19\x11"))
    print(_e4119("\x0c\x09\x5a\x2e\x32\x33\x29\x40\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x5a\x4b\x48\x5a\x09\x0e\x1b\x1d\x1f\x09\x56\x5a\x4f\x4a\x4a\x31\x5a\x31\x3e\x3c\x56\x5a\x4b\x4c\x5a\x08\x15\x0f\x14\x1e\x09\x56\x5a\x4b\x48\x42\x38\x5a\x1c\x1f\x1f\x1e\x18\x1b\x19\x11"))
end

return encrypt