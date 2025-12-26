// Memory Instructions - load, store, size, and grow operations

///|
/// Compute effective address for memory access using 64-bit arithmetic.
/// Both base_addr and offset are treated as unsigned 32-bit values.
/// Returns the 64-bit effective address (no wrapping).
fn compute_effective_addr(base_addr : Int, offset : Int) -> Int64 {
  // Mask with 0xFFFFFFFF to treat as unsigned 32-bit (clear sign extension)
  let base_u64 = base_addr.to_int64() & 0xFFFFFFFFL
  let offset_u64 = offset.to_int64() & 0xFFFFFFFFL
  base_u64 + offset_u64
}

///|
/// Check if memory access is within bounds.
/// Returns true if the access is out of bounds.
fn is_mem_oob(
  effective_addr : Int64,
  access_size : Int64,
  mem : @runtime.Memory,
) -> Bool {
  let mem_size = mem.size_pages().to_int64() * 65536L
  effective_addr < 0L || effective_addr + access_size > mem_size
}

///|
/// Execute memory load instruction
fn ExecContext::exec_memory_load(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
    // i32.load: load 4 bytes as i32
    I32Load(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i32(effective_addr.to_int())
      self.stack.push(I32(value))
    }
    // i64.load: load 8 bytes as i64
    I64Load(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    // f32.load: load 4 bytes as f32
    F32Load(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_f32(effective_addr.to_int())
      self.stack.push(F32(value))
    }
    // f64.load: load 8 bytes as f64
    F64Load(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_f64(effective_addr.to_int())
      self.stack.push(F64(value))
    }
    // i32.load8_s: load 1 byte, sign-extend to i32
    I32Load8S(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i32_8s(effective_addr.to_int())
      self.stack.push(I32(value))
    }
    // i32.load8_u: load 1 byte, zero-extend to i32
    I32Load8U(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i32_8u(effective_addr.to_int())
      self.stack.push(I32(value))
    }
    // i32.load16_s: load 2 bytes, sign-extend to i32
    I32Load16S(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i32_16s(effective_addr.to_int())
      self.stack.push(I32(value))
    }
    // i32.load16_u: load 2 bytes, zero-extend to i32
    I32Load16U(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i32_16u(effective_addr.to_int())
      self.stack.push(I32(value))
    }
    // i64.load8_s: load 1 byte, sign-extend to i64
    I64Load8S(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64_8s(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    // i64.load8_u: load 1 byte, zero-extend to i64
    I64Load8U(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64_8u(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    // i64.load16_s: load 2 bytes, sign-extend to i64
    I64Load16S(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64_16s(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    // i64.load16_u: load 2 bytes, zero-extend to i64
    I64Load16U(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64_16u(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    // i64.load32_s: load 4 bytes, sign-extend to i64
    I64Load32S(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64_32s(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    // i64.load32_u: load 4 bytes, zero-extend to i64
    I64Load32U(memidx, _align, offset) => {
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64_32u(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    _ => raise @runtime.RuntimeError::Unreachable
  }
}

///|
/// Execute memory store instruction
fn ExecContext::exec_memory_store(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
    // i32.store: store i32 as 4 bytes
    I32Store(memidx, _align, offset) => {
      let value = self.stack.pop_i32()
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i32(effective_addr.to_int(), value)
    }
    // i64.store: store i64 as 8 bytes
    I64Store(memidx, _align, offset) => {
      let value = self.stack.pop_i64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i64(effective_addr.to_int(), value)
    }
    // f32.store: store f32 as 4 bytes
    F32Store(memidx, _align, offset) => {
      let value = self.stack.pop_f32()
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_f32(effective_addr.to_int(), value)
    }
    // f64.store: store f64 as 8 bytes
    F64Store(memidx, _align, offset) => {
      let value = self.stack.pop_f64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_f64(effective_addr.to_int(), value)
    }
    // i32.store8: store low 8 bits of i32
    I32Store8(memidx, _align, offset) => {
      let value = self.stack.pop_i32()
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i32_8(effective_addr.to_int(), value)
    }
    // i32.store16: store low 16 bits of i32
    I32Store16(memidx, _align, offset) => {
      let value = self.stack.pop_i32()
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i32_16(effective_addr.to_int(), value)
    }
    // i64.store8: store low 8 bits of i64
    I64Store8(memidx, _align, offset) => {
      let value = self.stack.pop_i64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i64_8(effective_addr.to_int(), value)
    }
    // i64.store16: store low 16 bits of i64
    I64Store16(memidx, _align, offset) => {
      let value = self.stack.pop_i64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i64_16(effective_addr.to_int(), value)
    }
    // i64.store32: store low 32 bits of i64
    I64Store32(memidx, _align, offset) => {
      let value = self.stack.pop_i64()
      let base_addr = self.stack.pop_i32()
      let effective_addr = compute_effective_addr(base_addr, offset)
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i64_32(effective_addr.to_int(), value)
    }
    _ => raise @runtime.RuntimeError::Unreachable
  }
}

///|
/// Execute memory size/grow/bulk instruction
fn ExecContext::exec_memory_misc(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
    // memory.size: return current memory size in pages
    MemorySize(memidx) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      self.stack.push(I32(mem.size_pages()))
    }
    // memory.grow: grow memory by delta pages, return old size or -1 on failure
    MemoryGrow(memidx) => {
      let delta = self.stack.pop_i32()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let result = mem.grow(delta)
      self.stack.push(I32(result))
    }
    // memory.init: copy data from data segment to memory
    MemoryInit(memidx, data_idx) => {
      let n = self.stack.pop_i32() // length
      let s = self.stack.pop_i32() // source offset in data segment
      let d = self.stack.pop_i32() // destination in memory
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      // Use 64-bit arithmetic to avoid overflow
      let n64 = n.to_int64() & 0xFFFF_FFFFL
      let s64 = s.to_int64() & 0xFFFF_FFFFL
      let d64 = d.to_int64() & 0xFFFF_FFFFL
      // Determine data segment length (0 if dropped)
      let data_len = if self.instance.dropped_datas[data_idx] {
        0
      } else {
        self.instance.data_segments[data_idx].init.length()
      }
      // Check bounds (must happen even when n=0)
      // 1. Check data segment bounds
      if s64 + n64 > data_len.to_int64() {
        raise @runtime.RuntimeError::OutOfBoundsMemoryAccess
      }
      // 2. Check memory bounds
      let mem_size_bytes = mem.size_pages() * 65536
      if d64 + n64 > mem_size_bytes.to_int64() {
        raise @runtime.RuntimeError::OutOfBoundsMemoryAccess
      }
      // 3. If n=0, no-op
      if n == 0 {
        return
      }
      // Copy bytes directly to memory
      let data_segment = self.instance.data_segments[data_idx]
      for i in 0..<n {
        mem.store_byte(d + i, data_segment.init[s + i])
      }
    }
    // data.drop: mark data segment as dropped
    DataDrop(data_idx) => self.instance.dropped_datas[data_idx] = true
    // memory.copy: copy within memory (possibly across memories)
    MemoryCopy(dst_memidx, src_memidx) => {
      let n = self.stack.pop_i32() // length
      let s = self.stack.pop_i32() // source
      let d = self.stack.pop_i32() // destination
      if dst_memidx == src_memidx {
        // Same memory - use optimized copy
        let mem_addr = self.instance.mem_addrs[dst_memidx]
        let mem = self.store.get_mem(mem_addr)
        mem.copy(d, s, n)
      } else {
        // Different memories - need to copy byte by byte
        let src_mem_addr = self.instance.mem_addrs[src_memidx]
        let dst_mem_addr = self.instance.mem_addrs[dst_memidx]
        let src_mem = self.store.get_mem(src_mem_addr)
        let dst_mem = self.store.get_mem(dst_mem_addr)
        for i in 0..<n {
          let byte = src_mem.load_byte(s + i)
          dst_mem.store_byte(d + i, byte)
        }
      }
    }
    // memory.fill: fill memory region with a value
    MemoryFill(memidx) => {
      let n = self.stack.pop_i32() // length
      let val = self.stack.pop_i32() // value (byte)
      let d = self.stack.pop_i32() // destination
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      mem.fill(d, val.land(0xFF).to_byte(), n)
    }
    // elem.drop: mark element segment as dropped
    ElemDrop(elem_idx) => self.instance.dropped_elems[elem_idx] = true
    _ => raise @runtime.RuntimeError::Unreachable
  }
}
