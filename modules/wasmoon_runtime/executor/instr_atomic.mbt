// Atomic (0xFE) instruction execution for WebAssembly interpreter

///|
fn ExecContext::exec_atomic(
  self : ExecContext,
  subopcode : Int32,
  memidx : Int32,
  _align : Int32,
  offset : Int64,
) -> Unit raise {
  // atomic.fence has no memarg and no stack operands.
  if subopcode == 3 {
    @runtime.atomic_fence()
    return
  }
  if memidx < 0 || memidx >= self.instance.mem_addrs.length() {
    raise @runtime.RuntimeError::OutOfBoundsMemoryAccess
  }
  let mem_addr = self.instance.mem_addrs[memidx]
  let mem = self.store.get_mem(mem_addr)
  fn pop_effective_addr() -> Int64 raise {
    let base_addr = self.pop_mem_addr(mem)
    compute_effective_addr(base_addr, offset, mem.is_memory64())
  }

  guard @types.atomic_opcode(subopcode) is Some(info) else {
    raise @runtime.RuntimeError::Unreachable
  }
  let is_i64 = info.value_type == I64
  let width = info.width
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
  match info.operation {
    // Notify and both wait widths share the checked native queue.
    Notify => {
      let count = self.stack.pop_i32().reinterpret_as_uint()
      let effective_addr = pop_effective_addr()
      let notified = mem.atomic_notify(effective_addr, count)
      self.stack.push(I32(notified.reinterpret_as_int()))
    }
    Wait => {
      let timeout = self.stack.pop_i64()
      let width = info.width
      let expected = if info.value_type == I32 {
        self.stack.pop_i32().to_int64()
      } else {
        self.stack.pop_i64()
      }
      let effective_addr = pop_effective_addr()
      let waiter = mem.atomic_wait_begin(
        effective_addr, width, expected, timeout,
      )
      fn finish_wait(context : ExecContext) -> Unit raise {
        let result = waiter.poll()
        if result == -1 {
          context.set_base_resume_action(AtomicWait, finish_wait, cancel=fn() {
            waiter.cancel()
          })
          raise ExecutionSuspended
        }
        waiter.cancel()
        context.stack.push(I32(result))
      }
      if self.cooperative {
        finish_wait(self)
      } else {
        defer waiter.cancel()
        while waiter.poll() == -1 {
          self.check_cancellation()
          waiter.pause()
        }
        self.stack.push(I32(waiter.poll()))
      }
    }
    Load => {
      let address = pop_effective_addr()
      push_value(mem.atomic_load(address, width))
    }
    Store => {
      let value = pop_value()
      let address = pop_effective_addr()
      mem.atomic_store(address, width, value)
    }
    Rmw(operation) => {
      let value = pop_value()
      let address = pop_effective_addr()
      push_value(mem.atomic_rmw(operation, address, width, value))
    }
    CompareExchange => {
      let replacement = pop_value()
      let expected = pop_value()
      let address = pop_effective_addr()
      push_value(
        mem.atomic_compare_exchange(address, width, expected, replacement),
      )
    }
    Fence => @runtime.atomic_fence()
  }
}
