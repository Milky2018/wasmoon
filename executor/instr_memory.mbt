// Memory Instructions - load, store, size, and grow operations

///|
/// Execute memory load instruction
fn ExecContext::exec_memory_load(
  self : ExecContext,
  instr : @wasmoon.Instruction,
) -> Unit raise {
  match instr {
    // i32.load: load 4 bytes as i32
    I32Load(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i32(effective_addr)
      self.stack.push(I32(value))
    }
    // i64.load: load 8 bytes as i64
    I64Load(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64(effective_addr)
      self.stack.push(I64(value))
    }
    // f32.load: load 4 bytes as f32
    F32Load(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_f32(effective_addr)
      self.stack.push(F32(value))
    }
    // f64.load: load 8 bytes as f64
    F64Load(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_f64(effective_addr)
      self.stack.push(F64(value))
    }
    // i32.load8_s: load 1 byte, sign-extend to i32
    I32Load8S(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i32_8s(effective_addr)
      self.stack.push(I32(value))
    }
    // i32.load8_u: load 1 byte, zero-extend to i32
    I32Load8U(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i32_8u(effective_addr)
      self.stack.push(I32(value))
    }
    // i32.load16_s: load 2 bytes, sign-extend to i32
    I32Load16S(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i32_16s(effective_addr)
      self.stack.push(I32(value))
    }
    // i32.load16_u: load 2 bytes, zero-extend to i32
    I32Load16U(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i32_16u(effective_addr)
      self.stack.push(I32(value))
    }
    // i64.load8_s: load 1 byte, sign-extend to i64
    I64Load8S(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64_8s(effective_addr)
      self.stack.push(I64(value))
    }
    // i64.load8_u: load 1 byte, zero-extend to i64
    I64Load8U(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64_8u(effective_addr)
      self.stack.push(I64(value))
    }
    // i64.load16_s: load 2 bytes, sign-extend to i64
    I64Load16S(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64_16s(effective_addr)
      self.stack.push(I64(value))
    }
    // i64.load16_u: load 2 bytes, zero-extend to i64
    I64Load16U(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64_16u(effective_addr)
      self.stack.push(I64(value))
    }
    // i64.load32_s: load 4 bytes, sign-extend to i64
    I64Load32S(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64_32s(effective_addr)
      self.stack.push(I64(value))
    }
    // i64.load32_u: load 4 bytes, zero-extend to i64
    I64Load32U(_align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      let value = mem.load_i64_32u(effective_addr)
      self.stack.push(I64(value))
    }
    _ => raise @runtime.RuntimeError::Unreachable
  }
}

///|
/// Execute memory store instruction
fn ExecContext::exec_memory_store(
  self : ExecContext,
  instr : @wasmoon.Instruction,
) -> Unit raise {
  match instr {
    // i32.store: store i32 as 4 bytes
    I32Store(_align, offset) => {
      let value = self.stack.pop_i32()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i32(effective_addr, value)
    }
    // i64.store: store i64 as 8 bytes
    I64Store(_align, offset) => {
      let value = self.stack.pop_i64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i64(effective_addr, value)
    }
    // f32.store: store f32 as 4 bytes
    F32Store(_align, offset) => {
      let value = self.stack.pop_f32()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_f32(effective_addr, value)
    }
    // f64.store: store f64 as 8 bytes
    F64Store(_align, offset) => {
      let value = self.stack.pop_f64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_f64(effective_addr, value)
    }
    // i32.store8: store low 8 bits of i32
    I32Store8(_align, offset) => {
      let value = self.stack.pop_i32()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i32_8(effective_addr, value)
    }
    // i32.store16: store low 16 bits of i32
    I32Store16(_align, offset) => {
      let value = self.stack.pop_i32()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i32_16(effective_addr, value)
    }
    // i64.store8: store low 8 bits of i64
    I64Store8(_align, offset) => {
      let value = self.stack.pop_i64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i64_8(effective_addr, value)
    }
    // i64.store16: store low 16 bits of i64
    I64Store16(_align, offset) => {
      let value = self.stack.pop_i64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i64_16(effective_addr, value)
    }
    // i64.store32: store low 32 bits of i64
    I64Store32(_align, offset) => {
      let value = self.stack.pop_i64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = base_addr + offset
      let mem = self.store.get_mem(0)
      mem.store_i64_32(effective_addr, value)
    }
    _ => raise @runtime.RuntimeError::Unreachable
  }
}

///|
/// Execute memory size/grow instruction
fn ExecContext::exec_memory_misc(
  self : ExecContext,
  instr : @wasmoon.Instruction,
) -> Unit raise {
  match instr {
    // memory.size: return current memory size in pages
    MemorySize => {
      let mem = self.store.get_mem(0)
      self.stack.push(I32(mem.size_pages()))
    }
    // memory.grow: grow memory by delta pages, return old size or -1 on failure
    MemoryGrow => {
      let delta = self.stack.pop_i32()
      let mem = self.store.get_mem(0)
      let result = mem.grow(delta)
      self.stack.push(I32(result))
    }
    _ => raise @runtime.RuntimeError::Unreachable
  }
}
