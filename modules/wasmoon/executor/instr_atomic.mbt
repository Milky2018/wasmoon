// Atomic (0xFE) instruction execution for WebAssembly interpreter

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
    // Notify and both wait widths share the checked native queue.
    0 => {
      let count = self.stack.pop_i32().reinterpret_as_uint()
      let effective_addr = pop_effective_addr()
      let notified = mem.atomic_notify(effective_addr, count)
      self.stack.push(I32(notified.reinterpret_as_int()))
    }
    1 | 2 => {
      let timeout = self.stack.pop_i64()
      let width = if op == 1 { 4 } else { 8 }
      let expected = if op == 1 {
        self.stack.pop_i32().to_int64()
      } else {
        self.stack.pop_i64()
      }
      let effective_addr = pop_effective_addr()
      let waiter = mem.atomic_wait_begin(
        effective_addr, width, expected, timeout,
      )
      fn finish_wait() -> Unit raise {
        let result = waiter.poll()
        if result == -1 {
          self.set_base_resume_action(AtomicWait, finish_wait)
          raise ExecutionSuspended
        }
        waiter.cancel()
        self.stack.push(I32(result))
      }
      if self.cooperative {
        finish_wait()
      } else {
        defer waiter.cancel()
        while waiter.poll() == -1 {
          self.check_cancellation()
          waiter.pause()
        }
        self.stack.push(I32(waiter.poll()))
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
