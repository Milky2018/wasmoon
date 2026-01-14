// Memory Instructions - load, store, size, and grow operations

///|
/// Compute effective address for memory access using 64-bit arithmetic.
/// For memory32: base_addr is treated as unsigned 32-bit.
/// For memory64: base_addr is already 64-bit.
/// Returns the 64-bit effective address (no wrapping).
fn compute_effective_addr(
  base_addr : Int64,
  offset : Int64,
  is_memory64 : Bool,
) -> Int64 {
  let base_u64 = if is_memory64 {
    base_addr
  } else {
    // Mask with 0xFFFFFFFF to treat as unsigned 32-bit (clear sign extension)
    base_addr & 0xFFFFFFFFL
  }
  // offset is Int64 (supports memory64 64-bit offsets)
  base_u64 + offset
}

///|
/// Pop memory address from stack based on memory type
fn ExecContext::pop_mem_addr(
  self : ExecContext,
  mem : @runtime.Memory,
) -> Int64 raise {
  if mem.is_memory64() {
    self.stack.pop_i64()
  } else {
    self.stack.pop_i32().to_int64()
  }
}

///|
/// Check if memory access is within bounds.
/// Returns true if the access is out of bounds.
fn is_mem_oob(
  effective_addr : Int64,
  access_size : Int64,
  mem : @runtime.Memory,
) -> Bool {
  // Treat addresses/lengths as unsigned for bounds purposes.
  // Negative values represent large unsigned values and are always OOB.
  if effective_addr < 0L || access_size < 0L {
    return true
  }
  let mem_size = mem.byte_len()
  if access_size > mem_size {
    return true
  }
  effective_addr > mem_size - access_size
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
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i32(effective_addr.to_int())
      self.stack.push(I32(value))
    }
    // i64.load: load 8 bytes as i64
    I64Load(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    // f32.load: load 4 bytes as f32
    F32Load(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_f32(effective_addr.to_int())
      self.stack.push(F32(value))
    }
    // f64.load: load 8 bytes as f64
    F64Load(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_f64(effective_addr.to_int())
      self.stack.push(F64(value))
    }
    // i32.load8_s: load 1 byte, sign-extend to i32
    I32Load8S(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i32_8s(effective_addr.to_int())
      self.stack.push(I32(value))
    }
    // i32.load8_u: load 1 byte, zero-extend to i32
    I32Load8U(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i32_8u(effective_addr.to_int())
      self.stack.push(I32(value))
    }
    // i32.load16_s: load 2 bytes, sign-extend to i32
    I32Load16S(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i32_16s(effective_addr.to_int())
      self.stack.push(I32(value))
    }
    // i32.load16_u: load 2 bytes, zero-extend to i32
    I32Load16U(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i32_16u(effective_addr.to_int())
      self.stack.push(I32(value))
    }
    // i64.load8_s: load 1 byte, sign-extend to i64
    I64Load8S(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64_8s(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    // i64.load8_u: load 1 byte, zero-extend to i64
    I64Load8U(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64_8u(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    // i64.load16_s: load 2 bytes, sign-extend to i64
    I64Load16S(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64_16s(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    // i64.load16_u: load 2 bytes, zero-extend to i64
    I64Load16U(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64_16u(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    // i64.load32_s: load 4 bytes, sign-extend to i64
    I64Load32S(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let value = mem.load_i64_32s(effective_addr.to_int())
      self.stack.push(I64(value))
    }
    // i64.load32_u: load 4 bytes, zero-extend to i64
    I64Load32U(memidx, _align, offset) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
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
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i32(effective_addr.to_int(), value)
    }
    // i64.store: store i64 as 8 bytes
    I64Store(memidx, _align, offset) => {
      let value = self.stack.pop_i64()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i64(effective_addr.to_int(), value)
    }
    // f32.store: store f32 as 4 bytes
    F32Store(memidx, _align, offset) => {
      let value = self.stack.pop_f32()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_f32(effective_addr.to_int(), value)
    }
    // f64.store: store f64 as 8 bytes
    F64Store(memidx, _align, offset) => {
      let value = self.stack.pop_f64()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_f64(effective_addr.to_int(), value)
    }
    // i32.store8: store low 8 bits of i32
    I32Store8(memidx, _align, offset) => {
      let value = self.stack.pop_i32()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i32_8(effective_addr.to_int(), value)
    }
    // i32.store16: store low 16 bits of i32
    I32Store16(memidx, _align, offset) => {
      let value = self.stack.pop_i32()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i32_16(effective_addr.to_int(), value)
    }
    // i64.store8: store low 8 bits of i64
    I64Store8(memidx, _align, offset) => {
      let value = self.stack.pop_i64()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i64_8(effective_addr.to_int(), value)
    }
    // i64.store16: store low 16 bits of i64
    I64Store16(memidx, _align, offset) => {
      let value = self.stack.pop_i64()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      mem.store_i64_16(effective_addr.to_int(), value)
    }
    // i64.store32: store low 32 bits of i64
    I64Store32(memidx, _align, offset) => {
      let value = self.stack.pop_i64()
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let base_addr = self.pop_mem_addr(mem)
      let effective_addr = compute_effective_addr(
        base_addr,
        offset,
        mem.is_memory64(),
      )
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
      if mem.is_memory64() {
        self.stack.push(I64(mem.size_pages().to_int64()))
      } else {
        self.stack.push(I32(mem.size_pages()))
      }
    }
    // memory.grow: grow memory by delta pages, return old size or -1 on failure
    MemoryGrow(memidx) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      if mem.is_memory64() {
        let delta = self.stack.pop_i64().to_int()
        let result = mem.grow(delta)
        self.stack.push(I64(result.to_int64()))
      } else {
        let delta = self.stack.pop_i32()
        let result = mem.grow(delta)
        self.stack.push(I32(result))
      }
    }
    // memory.init: copy data from data segment to memory
    MemoryInit(memidx, data_idx) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      // For memory64: d is i64, s and n are always i32
      // Spec: memory.init [i*, i32, i32] -> []
      let n = self.stack.pop_i32() // n is always i32
      let s = self.stack.pop_i32() // s is always i32
      let d64 = if mem.is_memory64() {
        self.stack.pop_i64()
      } else {
        self.stack.pop_i32().to_int64() & 0xFFFF_FFFFL
      }
      let n64 = n.to_int64() & 0xFFFF_FFFFL
      let s64 = s.to_int64() & 0xFFFF_FFFFL
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
      if is_mem_oob(d64, n64, mem) {
        raise @runtime.RuntimeError::OutOfBoundsMemoryAccess
      }
      // 3. If n=0, no-op
      if n64 == 0L {
        return
      }
      // Copy bytes directly to memory
      let data_segment = self.instance.data_segments[data_idx]
      for i in 0L..<n64 {
        mem.store_byte(
          (d64 + i).to_int(),
          data_segment.init[(s64 + i).to_int()],
        )
      }
    }
    // data.drop: mark data segment as dropped
    DataDrop(data_idx) => self.instance.dropped_datas[data_idx] = true
    // memory.copy: copy within memory (possibly across memories)
    MemoryCopy(dst_memidx, src_memidx) => {
      // Get memories first to determine types
      let src_mem_addr = self.instance.mem_addrs[src_memidx]
      let dst_mem_addr = self.instance.mem_addrs[dst_memidx]
      let src_mem = self.store.get_mem(src_mem_addr)
      let dst_mem = self.store.get_mem(dst_mem_addr)
      // Per spec: n and d depend on dst type, s depends on src type
      let n64 = if dst_mem.is_memory64() {
        self.stack.pop_i64()
      } else {
        self.stack.pop_i32().to_int64() & 0xFFFF_FFFFL
      }
      let s64 = if src_mem.is_memory64() {
        self.stack.pop_i64()
      } else {
        self.stack.pop_i32().to_int64() & 0xFFFF_FFFFL
      }
      let d64 = if dst_mem.is_memory64() {
        self.stack.pop_i64()
      } else {
        self.stack.pop_i32().to_int64() & 0xFFFF_FFFFL
      }
      // Bounds check for both source and destination (even when n == 0)
      if is_mem_oob(s64, n64, src_mem) || is_mem_oob(d64, n64, dst_mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      if n64 == 0L {
        return
      }
      if dst_memidx == src_memidx {
        // Same memory - use optimized copy
        src_mem.copy(d64.to_int(), s64.to_int(), n64.to_int())
      } else {
        // Different memories - copy byte by byte
        for i in 0L..<n64 {
          let byte = src_mem.load_byte((s64 + i).to_int())
          dst_mem.store_byte((d64 + i).to_int(), byte)
        }
      }
    }
    // memory.fill: fill memory region with a value
    MemoryFill(memidx) => {
      let mem_addr = self.instance.mem_addrs[memidx]
      let mem = self.store.get_mem(mem_addr)
      let n64 = if mem.is_memory64() {
        self.stack.pop_i64()
      } else {
        self.stack.pop_i32().to_int64() & 0xFFFF_FFFFL
      }
      let val = self.stack.pop_i32()
      let dst = self.pop_mem_addr(mem)
      let effective_dst = compute_effective_addr(dst, 0L, mem.is_memory64())
      if is_mem_oob(effective_dst, n64, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      if n64 == 0L {
        return
      }
      mem.fill(effective_dst.to_int(), val.to_byte(), n64.to_int())
    }
    // elem.drop: mark element segment as dropped
    ElemDrop(elem_idx) => self.instance.dropped_elems[elem_idx] = true
    Atomic(subop, memidx, align, offset) =>
      self.exec_atomic(subop, memidx, align, offset)
    _ => raise @runtime.RuntimeError::Unreachable
  }
}
