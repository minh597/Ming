# 🔐 Lua Encrypt + Obfuscator

A 2-layer security system for Lua - strong encryption + code obfuscation.

## Usage

```bash
# Run obfuscator (default: medium)
lua obfuscate.lua [weak|medium|maximum]

# Test output
lua -e "local enc = require('obfuscated_encrypt'); enc.demo()"

# API
lua -e "local enc = require('obfuscated_encrypt'); print(enc.encrypt('hello', 'pass'))"
```

### Modes

| Mode | Features |
|------|----------|
| `weak` | String Encryption only |
| `medium` | String Encryption + Number Encoding |
| `maximum` | String Encryption + Number Encoding + Table Obfuscation |

### API
```lua
local enc = require('obfuscated_encrypt')

enc.demo()                                    -- Show config
local hex, err = enc.encrypt("msg", "pass")  -- Encrypt (slow: 500K KDF)
local text, err = enc.decrypt(hex, "pass")   -- Decrypt
```

## Project Structure

```
/workspace/project/Ming/
├── src/encrypt.lua              # Original encryption
├── obfuscate.lua                # Master obfuscator (3 modes)
├── obfuscators/                 # Obfuscation modules
│   ├── string_encryption.lua    # ✅ Working
│   ├── number_encoding.lua      # ✅ Working
│   ├── table_obfuscation.lua    # ✅ Working
│   └── ...
├── libs/                        # Utilities
└── obfuscated_encrypt.lua       # Generated output
```

## Encryption Features

- **12-stage pipeline**: whitening → keystream XOR → S-Box → diffusion → transposition → MAC
- **500K KDF iterations**: PBKDF2-like key derivation
- **2 key-dependent S-Boxes**: AES-like non-linear substitution
- **16 diffusion rounds**: full avalanche effect
- **128-byte feedback cipher**: avalanche
- **16-byte HMAC**: integrity check

## Security

Without the correct password, ciphertext is indistinguishable from random noise.