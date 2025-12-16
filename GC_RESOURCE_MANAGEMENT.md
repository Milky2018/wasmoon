# GC-based Resource Management Refactoring Plan

## Problem Analysis

### Current Design Issues
1. **Manual memory management**: Using `struct` to wrap C pointers (ExecCode, JITContext, JITModule, etc.)
2. **Value semantics**: Struct assignment creates shallow copies
3. **Shared C pointers**: Multiple copies share the same C pointer
4. **Manual free() required**: Easy to cause double-free or memory leaks
5. **Complex ownership tracking**: Need deduplication logic, defer cleanup, etc.

### Root Cause
Not using MoonBit's built-in GC mechanism to manage external resources.

## Solution: Use MoonBit GC + Finalizers

### Key Mechanism
According to [MoonBit FFI docs](https://docs.moonbitlang.cn/_sources/language/ffi.md):
- C backend provides `moonbit_make_external_object` API
- Register finalizer callback that executes when object becomes unreachable
- Finalizer automatically cleans up external resources (memory, file handles, etc.)
- GC guarantees each object is finalized exactly once (no double-free)

### Benefits
1. **Automatic management**: GC cleans up when object goes out of scope
2. **No double-free**: GC guarantees one-time finalization
3. **No leaks**: Even on exceptions, GC cleans up
4. **Simple code**: No need for defer, free(), ownership tracking
5. **Correct semantics**: External objects have reference semantics, not accidentally copied

## Implementation Plan

### Types to Refactor

1. **ExecCode** - Executable code memory
2. **JITContext** - JIT execution context
3. **JITFunction** - JIT-compiled function (contains ExecCode)
4. **JITModule** - JIT module (contains JITFunction Map and JITContext)
5. **JITTable** - Shared indirect table
6. **JITMemory** - Linear memory

### Phase 1: ExecCode (Simplest)

#### C side (ffi_jit.c)
```c
// Finalizer
static void finalize_exec_code(void *ptr) {
    if (ptr) {
        wasmoon_jit_free_exec((int64_t)ptr);
    }
}

// Create with finalizer
MOONBIT_FFI_EXPORT moonbit_value wasmoon_jit_alloc_exec_managed(
    const unsigned char *code,
    int size
) {
    int64_t ptr = wasmoon_jit_alloc_exec(size);
    if (ptr == 0) return NULL;

    if (wasmoon_jit_copy_code(ptr, code, size) != 0) {
        wasmoon_jit_free_exec(ptr);
        return NULL;
    }

    return moonbit_make_external_object((void*)ptr, finalize_exec_code, 0);
}
```

#### MoonBit side (ffi_jit.mbt)
```moonbit
// Change from struct to abstract type
type ExecCode

// FFI binding
extern "c" fn c_jit_alloc_exec_managed(
  code : FixedArray[Byte],
  size : Int
) -> ExecCode = "wasmoon_jit_alloc_exec_managed"

// Create (auto cleanup via GC)
fn ExecCode::new(code : Array[Int]) -> ExecCode? {
  let size = code.length()
  if size == 0 { return None }

  let bytes = FixedArray::make(size, b'\x00')
  for i, b in code {
    bytes[i] = b.to_byte()
  }

  let exec_code = c_jit_alloc_exec_managed(bytes, size)
  if exec_code == null {
    return None
  }
  Some(exec_code)
}

// NO free() method needed!
// fn ExecCode::free(...) { ... }  // DELETE
```

### Phase 2: JITContext

Similar pattern:
- Add `finalize_jit_context` in C
- Create `wasmoon_jit_alloc_context_v2_managed`
- Change `JITContext` to abstract type
- Remove `JITContext::free()`

### Phase 3: JITModule

Key changes:
- `functions: Map[Int, JITFunction]` - JITFunction becomes abstract type with GC
- `context: JITContext?` - JITContext is GC-managed
- Remove `JITModule::free()` - GC handles cleanup

### Phase 4: JITModuleContext

After all components use GC:
- `jit_module: JITModule` - GC-managed
- `memory_ptr: Int64` - needs finalizer
- `globals_ptr: Int64` - needs finalizer

Option 1: Wrap memory/globals as separate GC objects
Option 2: Single finalizer for entire context

### Phase 5: WastContext

After JITModuleContext uses GC:
- `jit_modules: Map[String, JITModuleContext]` - all GC-managed
- Remove `WastContext::free()` completely
- Remove `defer ctx.free()`

## Implementation Steps

1. ✅ Document plan
2. Implement ExecCode GC management
3. Implement JITContext GC management
4. Implement JITTable GC management (if needed)
5. Update JITFunction to use GC ExecCode
6. Update JITModule to use GC components
7. Create JITMemory/JITGlobals as GC objects
8. Update JITModuleContext to use GC
9. Remove all manual free() calls
10. Remove WastContext::free() and defer
11. Test thoroughly

## Testing Strategy

After each phase:
- Compile and check for errors
- Run block.wast (should pass 222/222)
- Run multiple test files (loop.wast, br.wast, call.wast, etc.)
- Verify no hangs, no crashes, no leaks

## Expected Outcome

- ✅ No manual free() calls anywhere
- ✅ No defer cleanup
- ✅ No ownership tracking complexity
- ✅ No double-free issues
- ✅ No memory leaks
- ✅ Clean, simple, idiomatic MoonBit code

---

## FFI Reference Counting Knowledge

### Core Concepts

#### 1. `moonbit_make_external_object(finalizer, payload_size)`

创建 GC 管理的外部对象：
- `finalizer`: 回调函数，对象被 GC 回收时调用
- `payload_size`: payload 大小（通常是 `sizeof(int64_t)` 用于存储 C 指针）
- 返回: 指向 payload 的指针，同时也是 MoonBit 的外部对象

```c
static void finalize_foo(void *self) {
    int64_t *ptr = (int64_t *)self;
    if (*ptr != 0) {
        free_foo(*ptr);
        *ptr = 0;
    }
}

void *create_foo_managed() {
    int64_t raw_ptr = alloc_foo();
    int64_t *payload = moonbit_make_external_object(finalize_foo, sizeof(int64_t));
    *payload = raw_ptr;
    return payload;
}
```

#### 2. 参数传递语义

**默认（owned）**：
- C 函数获得参数所有权
- **必须**在函数结束前调用 `moonbit_decref` 释放

**`#borrow`**：
- C 函数只是借用参数
- **不需要**调用 `moonbit_decref`
- 如果要存储到数据结构，**必须**调用 `moonbit_incref`

```moonbit
// Borrowed - C 函数只读取，不存储
#borrow(data)
pub extern "c" fn read_data(data : Bytes) -> Int = "read_data"

// Owned (默认) - C 函数需要负责 decref
pub extern "c" fn consume_data(data : Bytes) -> Unit = "consume_data"
```

#### 3. 外部引用问题

当 C 代码持有 MoonBit 对象的引用（如全局变量），GC 不知道这个引用存在，可能过早回收对象。

**解决方案**：使用 `moonbit_incref` / `moonbit_decref`

```c
static void *g_current_object = NULL;

void set_current_object(void *obj) {
    // 释放旧引用
    if (g_current_object != NULL) {
        moonbit_decref(g_current_object);
    }
    // 获取新引用
    if (obj != NULL) {
        moonbit_incref(obj);
    }
    g_current_object = obj;
}
```

对应的 MoonBit 声明使用 `#borrow`：
```moonbit
#borrow(obj)
pub extern "c" fn set_current_object(obj : MyObject) -> Unit = "set_current_object"
```

#### 4. 返回 Option 类型的限制

C 函数**不能直接返回** `T?`（Option 类型）给外部对象类型，因为 MoonBit 的 Option 内存布局不公开。

**错误做法**：
```moonbit
// ❌ 不工作 - C 返回的指针不会被正确解析为 Option
pub extern "c" fn create_foo() -> Foo? = "create_foo"
```

**正确做法**：返回非 Option 类型，在 MoonBit 侧检查有效性
```moonbit
// C 返回外部对象（可能是 NULL）
pub extern "c" fn create_foo_raw() -> Foo = "create_foo"
pub extern "c" fn foo_get_ptr(foo : Foo) -> Int64 = "foo_get_ptr"

// MoonBit 侧包装
fn create_foo() -> Foo? {
    let foo = create_foo_raw()
    if foo_get_ptr(foo) != 0L {
        Some(foo)
    } else {
        None
    }
}
```

### 实践总结

| 场景 | 操作 |
|------|------|
| 创建 GC 管理对象 | `moonbit_make_external_object` |
| C 函数只读参数 | 使用 `#borrow`，无需 decref |
| C 函数存储参数到全局/结构 | 使用 `#borrow` + `incref` |
| 替换全局引用 | 先 `decref` 旧的，再 `incref` 新的 |
| 返回可能失败的外部对象 | 返回非 Option，MoonBit 侧检查 |
