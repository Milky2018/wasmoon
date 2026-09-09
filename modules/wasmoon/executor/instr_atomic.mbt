// Atomic (0xFE) instruction execution for WebAssembly interpreter

///|
fn atomic_check_alignment(
  effective_addr : Int64,
  access_size : Int64,
) -> Unit raise @runtime.RuntimeError {
  if access_size <= 0L {
    raise Unreachable
  }
  if effective_addr % access_size != 0L {
    raise UnalignedAtomic
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
    @runtime.atomic_fence()
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
      self.stack.push(I32(0))
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
      if !mem.is_shared() {
        raise @runtime.AtomicWaitNonSharedMemory
      }
      let actual = mem.atomic_load(effective_addr, 4).to_int()
      if actual != expected {
        self.stack.push(I32(1)) // not-equal
      } else {
        self.stack.push(I32(2)) // timed-out
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
      if !mem.is_shared() {
        raise @runtime.AtomicWaitNonSharedMemory
      }
      let actual = mem.atomic_load(effective_addr, 8)
      if actual != expected {
        self.stack.push(I32(1))
      } else {
        self.stack.push(I32(2))
      }
    }
    4..=66 => {
      let shape = if op <= 10 {
        op - 4
      } else if op <= 17 {
        op - 11
      } else {
        (op - 18) % 7
      }
      let (is_i64, width) = match shape {
        0 => (false, 4)
        1 => (true, 8)
        2 => (false, 1)
        3 => (false, 2)
        4 => (true, 1)
        5 => (true, 2)
        _ => (true, 4)
      }
      fn pop_value() -> Int64 raise @runtime.RuntimeError {
        if is_i64 {
          self.stack.pop_i64()
        } else {
          self.stack.pop_i32().to_int64()
        }
      }
      fn push_value(value : Int64) -> Unit raise @runtime.RuntimeError {
        self.stack.push(if is_i64 { I64(value) } else { I32(value.to_int()) })
      }
      if op <= 10 {
        let address = pop_effective_addr()
        push_value(mem.atomic_load(address, width))
      } else if op <= 17 {
        let value = pop_value()
        let address = pop_effective_addr()
        mem.atomic_store(address, width, value)
      } else if op <= 59 {
        let value = pop_value()
        let address = pop_effective_addr()
        let operation : @runtime.AtomicRmwOp = match (op - 18) / 7 {
          0 => Add
          1 => Sub
          2 => And
          3 => Or
          4 => Xor
          _ => Exchange
        }
        push_value(mem.atomic_rmw(operation, address, width, value))
      } else {
        let replacement = pop_value()
        let expected = pop_value()
        let address = pop_effective_addr()
        push_value(
          mem.atomic_compare_exchange(address, width, expected, replacement),
        )
      }
    }
    _ => raise @runtime.Unreachable
  }
}
