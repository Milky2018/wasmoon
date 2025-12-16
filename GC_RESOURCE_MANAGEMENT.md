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
