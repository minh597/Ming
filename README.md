# Achilles Obfuscator v1.1.1

Lua obfuscator with 17 obfuscation passes.

## Usage

```bash
lua obfuscate.lua [weak|medium|maximum]
```

### Modes

| Mode | Description |
|------|-------------|
| `weak` | String Encryption |
| `medium` | + Identifier Rename, Constant Encryption, MBA |
| `maximum` | + All obfuscation passes |

### Features (17 passes)

| # | Pass | Description |
|---|------|-------------|
| 01 | AST Complete | Full AST parser |
| 02 | Identifier Rename | Rename variables |
| 03 | String Encryption | Encrypt string literals |
| 04 | Constant Encryption | Encode numbers |
| 05 | MBA | Mixed Boolean Arithmetic |
| 06 | Opaque Predicate | Insert unreachable code |
| 07 | Dead Code | Inject dead code blocks |
| 08 | Control Flow Flattening | Restructure control flow |
| 09 | Bogus Control Flow | Insert fake branches |
| 10 | Fake States | State machine injection |
| 11 | Table Encryption | Encrypt table literals |
| 12 | Runtime Decoder | Decode at runtime |
| 13 | VM (Stack/Register) | Virtual machine |
| 14 | Anti Dump | Anti-debugging |
| 15 | Anti Decompiler | Confuse decompilers |
| 16 | Multi-pass Scheduler | Multiple passes |
| 17 | Minify | Reduce code size |

## Project Structure

```
/workspace/project/Ming/
├── src/encrypt.lua           # Source code
├── obfuscate.lua             # Main obfuscator
├── obfuscators/              # 17 obfuscation modules
│   ├── 01_ast.lua
│   ├── 02_identifier_rename.lua
│   ├── 03_string_encryption.lua
│   └── ...
├── libs/                    # Utilities
│   └── watermark.lua
└── obfuscated_encrypt.lua    # Output
```

## API

```lua
local enc = require('obfuscated_encrypt')
enc.demo()
local hex = enc.encrypt("msg", "pass")
local text = enc.decrypt(hex, "pass")
```