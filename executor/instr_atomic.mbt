// Atomic (0xFE) instruction execution for WebAssembly interpreter

///|
fn atomic_check_alignment(
  effective_addr : Int64,
  access_size : Int64,
) -> Unit raise @runtime.RuntimeError {
  if access_size <= 0L {
    raise @runtime.Unreachable
  }
  if effective_addr % access_size != 0L {
    raise @runtime.UnalignedAtomic
  }
}

///|
fn ExecContext::exec_atomic(
  self : ExecContext,
  subopcode : Int,
  memidx : Int,
  _align : Int,
  offset : Int64,
) -> Unit raise {
  // atomic.fence has no memarg and no stack operands.
  if subopcode == 3 {
    return
  }
  if memidx < 0 || memidx >= self.instance.mem_addrs.length() {
    raise @runtime.OutOfBoundsMemoryAccess
  }
  let mem_addr = self.instance.mem_addrs[memidx]
  let mem = self.store.get_mem(mem_addr)
  fn pop_effective_addr() -> Int64 raise {
    let base_addr = self.pop_mem_addr(mem)
    compute_effective_addr(base_addr, offset, mem.is_memory64())
  }

  fn load_u8(addr : Int64) -> Int raise @runtime.RuntimeError {
    mem.load_i32_8u(addr.to_int())
  }

  fn load_u16(addr : Int64) -> Int raise @runtime.RuntimeError {
    mem.load_i32_16u(addr.to_int())
  }

  fn load_i32(addr : Int64) -> Int raise @runtime.RuntimeError {
    mem.load_i32(addr.to_int())
  }

  fn load_i64(addr : Int64) -> Int64 raise @runtime.RuntimeError {
    mem.load_i64(addr.to_int())
  }

  fn load_u32_to_i64(addr : Int64) -> Int64 raise @runtime.RuntimeError {
    mem.load_i64_32u(addr.to_int())
  }

  fn store_u8(addr : Int64, v : Int) -> Unit raise @runtime.RuntimeError {
    mem.store_i32_8(addr.to_int(), v)
  }

  fn store_u16(addr : Int64, v : Int) -> Unit raise @runtime.RuntimeError {
    mem.store_i32_16(addr.to_int(), v)
  }

  fn store_i32(addr : Int64, v : Int) -> Unit raise @runtime.RuntimeError {
    mem.store_i32(addr.to_int(), v)
  }

  fn store_i64(addr : Int64, v : Int64) -> Unit raise @runtime.RuntimeError {
    mem.store_i64(addr.to_int(), v)
  }

  fn store_u32_from_i64(
    addr : Int64,
    v : Int64,
  ) -> Unit raise @runtime.RuntimeError {
    mem.store_i64_32(addr.to_int(), v)
  }

  // NOTE: wasm-tools/wasmparser encodes most atomic subopcodes starting at 0x10.
  // The interpreter's atomic table is indexed starting at 0x04, so shift accordingly.
  let op = if subopcode >= 0x10 { subopcode - 12 } else { subopcode }
  match op {
    // memory.atomic.notify
    0 => {
      let _count = self.stack.pop_i32()
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 4L)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      // return 0 (no waiters in single-threaded runtime)
      self.stack.push(@types.Value::I32(0))
    }

    // memory.atomic.wait32
    1 => {
      self.stack.pop_i64() |> ignore // timeout
      let expected = self.stack.pop_i32()
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 4L)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let actual = load_i32(effective_addr)
      if actual != expected {
        self.stack.push(@types.Value::I32(1)) // not-equal
      } else {
        self.stack.push(@types.Value::I32(2)) // timed-out
      }
    }

    // memory.atomic.wait64
    2 => {
      self.stack.pop_i64() |> ignore // timeout
      let expected = self.stack.pop_i64()
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 8L)
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let actual = load_i64(effective_addr)
      if actual != expected {
        self.stack.push(@types.Value::I32(1))
      } else {
        self.stack.push(@types.Value::I32(2))
      }
    }

    // Loads
    4 => {
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 4L)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      self.stack.push(@types.Value::I32(load_i32(effective_addr)))
    }
    5 => {
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 8L)
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      self.stack.push(@types.Value::I64(load_i64(effective_addr)))
    }
    6 => {
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 1L)
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      self.stack.push(@types.Value::I32(load_u8(effective_addr)))
    }
    7 => {
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 2L)
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      self.stack.push(@types.Value::I32(load_u16(effective_addr)))
    }
    8 => {
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 1L)
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      self.stack.push(@types.Value::I64(load_u8(effective_addr).to_int64()))
    }
    9 => {
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 2L)
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      self.stack.push(@types.Value::I64(load_u16(effective_addr).to_int64()))
    }
    10 => {
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 4L)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      self.stack.push(@types.Value::I64(load_u32_to_i64(effective_addr)))
    }

    // Stores
    11 => {
      let v = self.stack.pop_i32()
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 4L)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      store_i32(effective_addr, v)
    }
    12 => {
      let v = self.stack.pop_i64()
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 8L)
      if is_mem_oob(effective_addr, 8L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      store_i64(effective_addr, v)
    }
    13 => {
      let v = self.stack.pop_i32() & 0xFF
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 1L)
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      store_u8(effective_addr, v)
    }
    14 => {
      let v = self.stack.pop_i32() & 0xFFFF
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 2L)
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      store_u16(effective_addr, v)
    }
    15 => {
      let v = self.stack.pop_i64().to_int() & 0xFF
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 1L)
      if is_mem_oob(effective_addr, 1L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      store_u8(effective_addr, v)
    }
    16 => {
      let v = self.stack.pop_i64().to_int() & 0xFFFF
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 2L)
      if is_mem_oob(effective_addr, 2L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      store_u16(effective_addr, v)
    }
    17 => {
      let v = self.stack.pop_i64()
      let effective_addr = pop_effective_addr()
      atomic_check_alignment(effective_addr, 4L)
      if is_mem_oob(effective_addr, 4L, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      store_u32_from_i64(effective_addr, v)
    }

    // RMW operations (i32)
    18
    | 20
    | 21
    | 25
    | 27
    | 28
    | 32
    | 34
    | 35
    | 39
    | 41
    | 42
    | 46
    | 48
    | 49
    | 53
    | 55
    | 56 => {
      let v = self.stack.pop_i32()
      let effective_addr = pop_effective_addr()
      let access_size = if subopcode == 18 ||
        subopcode == 25 ||
        subopcode == 32 ||
        subopcode == 39 ||
        subopcode == 46 ||
        subopcode == 53 {
        4L
      } else if subopcode == 20 ||
        subopcode == 27 ||
        subopcode == 34 ||
        subopcode == 41 ||
        subopcode == 48 ||
        subopcode == 55 {
        1L
      } else {
        2L
      }
      atomic_check_alignment(effective_addr, access_size)
      if is_mem_oob(effective_addr, access_size, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let old = if access_size == 4L {
        load_i32(effective_addr)
      } else if access_size == 1L {
        load_u8(effective_addr)
      } else {
        load_u16(effective_addr)
      }
      let mask = if access_size == 4L {
        -1
      } else if access_size == 1L {
        0xFF
      } else {
        0xFFFF
      }
      let v_masked = v & mask
      let new = match subopcode {
        18 | 20 | 21 => (old + v_masked) & mask
        25 | 27 | 28 => (old - v_masked) & mask
        32 | 34 | 35 => old & v_masked
        39 | 41 | 42 => old | v_masked
        46 | 48 | 49 => old ^ v_masked
        53 | 55 | 56 => v_masked
        _ => old
      }
      if access_size == 4L {
        store_i32(effective_addr, new)
      } else if access_size == 1L {
        store_u8(effective_addr, new)
      } else {
        store_u16(effective_addr, new)
      }
      self.stack.push(@types.Value::I32(old))
    }

    // RMW operations (i64)
    19
    | 22
    | 23
    | 24
    | 26
    | 29
    | 30
    | 31
    | 33
    | 36
    | 37
    | 38
    | 40
    | 43
    | 44
    | 45
    | 47
    | 50
    | 51
    | 52
    | 54
    | 57
    | 58
    | 59 => {
      let v = self.stack.pop_i64()
      let effective_addr = pop_effective_addr()
      let access_size = if subopcode == 19 ||
        subopcode == 26 ||
        subopcode == 33 ||
        subopcode == 40 ||
        subopcode == 47 ||
        subopcode == 54 {
        8L
      } else if subopcode == 22 ||
        subopcode == 29 ||
        subopcode == 36 ||
        subopcode == 43 ||
        subopcode == 50 ||
        subopcode == 57 {
        1L
      } else if subopcode == 23 ||
        subopcode == 30 ||
        subopcode == 37 ||
        subopcode == 44 ||
        subopcode == 51 ||
        subopcode == 58 {
        2L
      } else {
        4L
      }
      atomic_check_alignment(effective_addr, access_size)
      if is_mem_oob(effective_addr, access_size, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let (old, mask) : (Int64, Int64) = if access_size == 8L {
        (load_i64(effective_addr), -1L)
      } else if access_size == 4L {
        (load_u32_to_i64(effective_addr), 0xFFFF_FFFFL)
      } else if access_size == 2L {
        (load_u16(effective_addr).to_int64(), 0xFFFFL)
      } else {
        (load_u8(effective_addr).to_int64(), 0xFFL)
      }
      let v_masked = v & mask
      let new = match subopcode {
        19 | 22 | 23 | 24 => (old + v_masked) & mask
        26 | 29 | 30 | 31 => (old - v_masked) & mask
        33 | 36 | 37 | 38 => old & v_masked
        40 | 43 | 44 | 45 => old | v_masked
        47 | 50 | 51 | 52 => old ^ v_masked
        54 | 57 | 58 | 59 => v_masked
        _ => old
      }
      if access_size == 8L {
        store_i64(effective_addr, new)
      } else if access_size == 4L {
        store_u32_from_i64(effective_addr, new)
      } else if access_size == 2L {
        store_u16(effective_addr, new.to_int())
      } else {
        store_u8(effective_addr, new.to_int())
      }
      self.stack.push(@types.Value::I64(old))
    }

    // cmpxchg (i32)
    60 | 62 | 63 => {
      let replacement = self.stack.pop_i32()
      let expected = self.stack.pop_i32()
      let effective_addr = pop_effective_addr()
      let access_size = if subopcode == 60 {
        4L
      } else if subopcode == 62 {
        1L
      } else {
        2L
      }
      atomic_check_alignment(effective_addr, access_size)
      if is_mem_oob(effective_addr, access_size, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let old = if access_size == 4L {
        load_i32(effective_addr)
      } else if access_size == 1L {
        load_u8(effective_addr)
      } else {
        load_u16(effective_addr)
      }
      let mask = if access_size == 4L {
        -1
      } else if access_size == 1L {
        0xFF
      } else {
        0xFFFF
      }
      if old == (expected & mask) {
        let new = replacement & mask
        if access_size == 4L {
          store_i32(effective_addr, new)
        } else if access_size == 1L {
          store_u8(effective_addr, new)
        } else {
          store_u16(effective_addr, new)
        }
      }
      self.stack.push(@types.Value::I32(old))
    }

    // cmpxchg (i64)
    61 | 64 | 65 | 66 => {
      let replacement = self.stack.pop_i64()
      let expected = self.stack.pop_i64()
      let effective_addr = pop_effective_addr()
      let access_size = if subopcode == 61 {
        8L
      } else if subopcode == 64 {
        1L
      } else if subopcode == 65 {
        2L
      } else {
        4L
      }
      atomic_check_alignment(effective_addr, access_size)
      if is_mem_oob(effective_addr, access_size, mem) {
        raise @runtime.OutOfBoundsMemoryAccess
      }
      let (old, mask) : (Int64, Int64) = if access_size == 8L {
        (load_i64(effective_addr), -1L)
      } else if access_size == 4L {
        (load_u32_to_i64(effective_addr), 0xFFFF_FFFFL)
      } else if access_size == 2L {
        (load_u16(effective_addr).to_int64(), 0xFFFFL)
      } else {
        (load_u8(effective_addr).to_int64(), 0xFFL)
      }
      if old == (expected & mask) {
        let new = replacement & mask
        if access_size == 8L {
          store_i64(effective_addr, new)
        } else if access_size == 4L {
          store_u32_from_i64(effective_addr, new)
        } else if access_size == 2L {
          store_u16(effective_addr, new.to_int())
        } else {
          store_u8(effective_addr, new.to_int())
        }
      }
      self.stack.push(@types.Value::I64(old))
    }
    _ => raise @runtime.Unreachable
  }
}
