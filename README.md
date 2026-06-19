# 🔐 Ultimate Encryption + Obfuscation System

Một hệ thống bảo mật 2 lớp cho Lua - mã hóa mạnh mẽ + làm rối code.

## 📁 Cấu trúc Project

```
/workspace/project/Ming/
├── src/                    # Code gốc
│   └── encrypt.lua         # Engine mã hóa 12-stage
├── obfuscators/            # Các module làm rối
│   ├── string_encryption.lua    ✅ Hoạt động
│   ├── variable_mangling.lua    ⚠️ Cần fix
│   ├── control_flow.lua        ⚠️ Cần fix
│   ├── dead_code.lua           ⚠️ Cần fix
│   ├── number_encoding.lua     ⚠️ Cần fix
│   ├── opaque_predicates.lua   ⚠️ Cần fix
│   └── table_obfuscation.lua   ⚠️ Cần fix
├── libs/                   # Utilities
│   ├── random_utils.lua
│   └── transform_utils.lua
├── obfuscate.lua           # Master obfuscator
├── obfuscated_encrypt.lua  # Output (sinh khi chạy obfuscate.lua)
└── README.md
```

## 🛡️ Layer 1: Mã hóa (`src/encrypt.lua`)

**12-stage encryption pipeline** với API đơn giản `encrypt()` / `decrypt()`.

### Pipeline
```
① Initial whitening (XOR với key material)
② Keystream XOR #1 (stream cipher)
③ 128-byte feedback cipher (avalanche effect)
④ S-Box A substitution (non-linear)
⑤ 16-round bit diffusion (S-Box A + B)
⑥ Transposition (hoán vị toàn bộ message)
⑦ Second feedback pass
⑧ Keystream XOR #2 (seed khác)
⑨ S-Box B substitution (permutation khác)
⑩ Keystream XOR #3 (seed thứ 3)
⑪ Final whitening (offset khác)
⑫ 16-byte HMAC integrity tag (dual S-Box)
```

### Thông số
| Thông số | Giá trị |
|----------|---------|
| KDF iterations | **500,000** |
| Salt | **32 bytes** random |
| S-Boxes | **2** (key-dependent) |
| Diffusion rounds | **16** |
| Feedback state | **128 bytes** |

## 🎭 Layer 2: Obfuscation (`obfuscate.lua`)

**7-layer obfuscation pipeline** biến code thành khó đọc/hack.

```
① Variable Mangling     → Tên biến ngẫu nhiên
② Number Encoding       → Số thành biểu thức toán
③ String Encryption     → Chuỗi XOR-encrypted, decode khi chạy
④ Table Obfuscation     → Keys xáo trộn
⑤ Opaque Predicates     → Điều kiện luôn đúng/sai
⑥ Dead Code Injection   → Code không bao giờ chạy
⑦ Control Flow Flattening → goto-based dispatcher
```

## 🚀 Cách sử dụng

```bash
# 1. Chạy obfuscator để tạo obfuscated_encrypt.lua
lua obfuscate.lua

# 2. Test output
lua -e "local enc = require('obfuscated_encrypt'); enc.demo()"

# 3. Sử dụng trong code
lua -e "local enc = require('obfuscated_encrypt'); print(enc.encrypt('hello', 'pass'))"
```

### API
```lua
local enc = require('obfuscated_encrypt')

-- Demo
enc.demo()

-- Mã hóa (mất ~10 giây do 500K KDF iterations)
local hex, err = enc.encrypt("secret message", "password")

-- Giải mã
local text, err = enc.decrypt(hex, "password")
```

## ✅ Trạng thái

| Module | Status |
|--------|--------|
| String Encryption | ✅ Hoạt động |
| Variable Mangling | ⚠️ Bug - sinh tên không hợp lệ |
| Number Encoding | ⚠️ Bug - syntax không đúng |
| Control Flow | ⚠️ Bug - goto không khớp |
| Dead Code | ⚠️ Bug - code không hợp lệ |
| Opaque Predicates | ⚠️ Bug |
| Table Obfuscation | ⚠️ Bug |

## 🔒 Tại sao an toàn?

Nếu không có password đúng, ciphertext không thể phân biệt được với noise ngẫu nhiên. Và nếu ai đó có source code, obfuscation làm nó nearly impossible để hiểu.