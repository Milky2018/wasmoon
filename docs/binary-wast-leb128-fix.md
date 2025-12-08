# 修复 binary.wast 和 binary-leb128.wast 测试失败

## 问题

运行 WebAssembly 规范测试时，`binary.wast` 和 `binary-leb128.wast` 存在多个测试失败。

## 修复内容

### 1. Element Section 格式支持

WebAssembly 规范支持多种 element section 格式（active、passive、declarative）。添加了 `ElemMode` 枚举：

```moonbit
pub(all) enum ElemMode {
  Active(Int, Array[Instruction]) // table_idx, offset_expr
  Passive
  Declarative
}
```

### 2. 非引用类型检测

Element segment 只能使用引用类型（funcref、externref）。添加 `MalformedReferenceType` 错误检测非法类型。

### 3. LEB128 验证修复

**问题**：signed LEB128 的最后一个字节未验证 unused bits 是否正确符号扩展。

**修复**：
- i32 (5字节)：第5字节的 bits 4-6 必须从 bit 3 符号扩展
- i64 (10字节)：第10字节的 bits 1-6 必须从 bit 0 符号扩展

```moonbit
// i32 示例：shift=28 时
let sign_bit = (byte & 0x08) != 0
let upper_bits = byte & 0x70
if sign_bit {
  if upper_bits != 0x70 { raise LEB128TooLarge }
} else {
  if upper_bits != 0x00 { raise LEB128TooLarge }
}
```

### 4. Custom Section 解析

之前跳过整个 custom section，导致其中的 LEB128 未被验证。修复后会解析 name 字段以触发 LEB128 验证。

## 结果

- binary.wast: 107 passed, 0 failed
- binary-leb128.wast: 58 passed, 0 failed, 7 skipped
