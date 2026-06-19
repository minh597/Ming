# Achilles Obfuscator v1.1.1

Obfuscate Lua script nhanh chóng.

## Usage

```bash
lua main.lua <input.lua> <output.lua> <mode>
```

## Args

| Arg | Mô tả |
|-----|--------|
| input.lua | File cần obfuscate |
| output.lua | File đã obfuscate |
| mode | weak / medium / maximum |

## Ví dụ

```bash
lua main.lua input.lua output.lua maximum
lua main.lua script.lua obf.lua medium
lua main.lua code.lua out.lua weak
```

## Modes

| Mode | Passes | Mô tả |
|------|--------|--------|
| weak | 2 | Cơ bản |
| medium | 5 | Trung bình |
| maximum | 17 | Toàn bộ |

## Passes

1. AST
2. Rename
3. StringEnc
4. ConstEnc
5. MBA
6. Opaque
7. DeadCode
8. CtrlFlow
9. Bogus
10. FakeState
11. TableEnc
12. Runtime
13. VM
14. AntiDump
15. AntiDec
16. MultiPass
17. Minify
