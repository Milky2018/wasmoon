// Wasmoon Executor - Main instruction dispatch and module execution

///|
/// Check if subtype is a subtype of supertype for value types.
/// This implements WebAssembly reference type subtyping:
/// - RefFunc <: FuncRef (ref func <: ref null func)
/// - RefExtern <: ExternRef (ref extern <: ref null extern)
/// - RefFuncTyped(i) <: RefNullFuncTyped(i) (ref $t <: ref null $t)
/// - RefFuncTyped(i) <: RefFunc <: FuncRef (concrete <: abstract <: nullable abstract)
/// - RefNullFuncTyped(i) <: FuncRef (ref null $t <: ref null func)
/// - All types are subtypes of themselves
fn is_value_type_subtype(
  subtype : @types.ValueType,
  supertype : @types.ValueType,
) -> Bool {
  if subtype == supertype {
    return true
  }
  match (subtype, supertype) {
    // RefFunc (ref func) is subtype of FuncRef (ref null func)
    (RefFunc, FuncRef) => true
    // RefExtern (ref extern) is subtype of ExternRef (ref null extern)
    (RefExtern, ExternRef) => true
    // RefFuncTyped(i) is subtype of RefNullFuncTyped(i) for same i
    (RefFuncTyped(i), RefNullFuncTyped(j)) => i == j
    // RefFuncTyped is subtype of RefFunc (concrete <: abstract)
    (RefFuncTyped(_), RefFunc) => true
    // RefFuncTyped is subtype of FuncRef (concrete <: nullable abstract)
    (RefFuncTyped(_), FuncRef) => true
    // RefNullFuncTyped is subtype of FuncRef (nullable concrete <: nullable abstract)
    (RefNullFuncTyped(_), FuncRef) => true
    // Everything else: not a subtype
    _ => false
  }
}

///|
/// Execute a single instruction
fn ExecContext::exec_instr(
  self : ExecContext,
  instr : @types.Instruction,
) -> Unit raise {
  match instr {
    // Constants
    I32Const(n) => self.stack.push(I32(n))
    I64Const(n) => self.stack.push(I64(n))
    F32Const(f) => self.stack.push(F32(f))
    F64Const(d) => self.stack.push(F64(d))

    // Local variables
    LocalGet(idx) => {
      let frame = self.get_frame()
      let value = frame.get_local(idx)
      self.stack.push(value)
    }
    LocalSet(idx) => {
      let value = self.stack.pop()
      let frame = self.get_frame()
      frame.set_local(idx, value)
    }
    LocalTee(idx) => {
      let value = self.stack.peek()
      let frame = self.get_frame()
      frame.set_local(idx, value)
    }

    // Global variables
    GlobalGet(idx) => {
      let global_addr = self.instance.global_addrs[idx]
      let global = self.store.get_global(global_addr)
      self.stack.push(global.get())
    }
    GlobalSet(idx) => {
      let value = self.stack.pop()
      let global_addr = self.instance.global_addrs[idx]
      let global = self.store.get_global(global_addr)
      global.set(value)
    }

    // Table operations
    TableGet(table_idx) => {
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      let elem_idx = if table.is_table64() {
        self.stack.pop_i64().to_int()
      } else {
        self.stack.pop_i32()
      }
      let value = table.get(elem_idx)
      self.stack.push(value)
    }
    TableSet(table_idx) => {
      let value = self.stack.pop()
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      let elem_idx = if table.is_table64() {
        self.stack.pop_i64().to_int()
      } else {
        self.stack.pop_i32()
      }
      table.set(elem_idx, value)
    }
    TableSize(table_idx) => {
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      if table.is_table64() {
        self.stack.push(I64(table.size().to_int64()))
      } else {
        self.stack.push(I32(table.size()))
      }
    }
    TableGrow(table_idx) => {
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      let delta = if table.is_table64() {
        self.stack.pop_i64().to_int()
      } else {
        self.stack.pop_i32()
      }
      let init_val = self.stack.pop()
      let old_size = table.grow(delta, init_val)
      if table.is_table64() {
        self.stack.push(I64(old_size.to_int64()))
      } else {
        self.stack.push(I32(old_size))
      }
    }
    TableFill(table_idx) => {
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      let (n, value, dest) = if table.is_table64() {
        let n = self.stack.pop_i64().to_int()
        let value = self.stack.pop()
        let dest = self.stack.pop_i64().to_int()
        (n, value, dest)
      } else {
        let n = self.stack.pop_i32()
        let value = self.stack.pop()
        let dest = self.stack.pop_i32()
        (n, value, dest)
      }
      table.fill(dest, value, n)
    }
    TableCopy(dest_table_idx, src_table_idx) => {
      let dest_table_addr = self.instance.table_addrs[dest_table_idx]
      let src_table_addr = self.instance.table_addrs[src_table_idx]
      let dest_table = self.store.get_table(dest_table_addr)
      let src_table = self.store.get_table(src_table_addr)
      // Length uses i64 only if BOTH tables are table64 (minimum of both types)
      let n = if dest_table.is_table64() && src_table.is_table64() {
        self.stack.pop_i64().to_int()
      } else {
        self.stack.pop_i32()
      }
      // Source index uses source table's index type
      let src = if src_table.is_table64() {
        self.stack.pop_i64().to_int()
      } else {
        self.stack.pop_i32()
      }
      // Dest index uses dest table's index type
      let dest = if dest_table.is_table64() {
        self.stack.pop_i64().to_int()
      } else {
        self.stack.pop_i32()
      }
      dest_table.copy_from(dest, src_table, src, n)
    }
    TableInit(table_idx, elem_idx) => {
      // table.init copies elements from elem segment to table
      // Pop operands: n (count), s (src offset in elem), d (dest offset in table)
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      // s and n are always i32 (elem segments are i32-indexed)
      // d uses table's index type
      let n = self.stack.pop_i32()
      let s = self.stack.pop_i32()
      let d = if table.is_table64() {
        self.stack.pop_i64().to_int()
      } else {
        self.stack.pop_i32()
      }

      // Get elem segment
      let elem_segment = self.instance.elem_segments[elem_idx]

      // Check if segment has been dropped or is declarative
      // Declarative elem segments behave as if they have been dropped
      let is_dropped = self.instance.dropped_elems[elem_idx]
      let is_declarative = elem_segment.mode is @types.ElemMode::Declarative
      if (is_dropped || is_declarative) && n != 0 {
        // Dropped/declarative segments behave as if they have zero length
        raise @runtime.RuntimeError::OutOfBoundsTableAccess
      }
      if is_dropped || is_declarative {
        return
      }

      // Check bounds
      let elem_len = elem_segment.init.length()
      let table_addr = self.instance.table_addrs[table_idx]
      let table = self.store.get_table(table_addr)
      let table_size = table.size()
      if s < 0 || n < 0 || s + n > elem_len || d < 0 || d + n > table_size {
        raise @runtime.RuntimeError::OutOfBoundsTableAccess
      }

      // Copy elements from elem segment to table
      for i in 0..<n {
        let init_expr = elem_segment.init[s + i]
        // Evaluate the init expression to get the value
        let value = match init_expr {
          [RefFunc(func_idx)] => {
            // Convert module function index to store address
            let store_addr = self.instance.func_addrs[func_idx]
            @types.Value::FuncRef(store_addr)
          }
          [RefNull(ref_type)] =>
            match ref_type {
              FuncRef | ExternRef => @types.Value::Null
              _ => @types.Value::Null
            }
          [I32Const(idx)] => {
            // Legacy format: function index as i32
            let store_addr = self.instance.func_addrs[idx]
            @types.Value::FuncRef(store_addr)
          }
          // GC: handle ref.i31 expressions
          [I32Const(n), RefI31] => {
            let i31_val = n & 0x7FFFFFFF
            @types.Value::I31(i31_val)
          }
          [GlobalGet(idx), RefI31] => {
            let globals = get_global_instances(
              self.store,
              self.instance.global_addrs,
            )
            if idx < globals.length() {
              match globals[idx].get() {
                I32(n) => {
                  let i31_val = n & 0x7FFFFFFF
                  @types.Value::I31(i31_val)
                }
                _ => @types.Value::Null
              }
            } else {
              @types.Value::Null
            }
          }
          _ => @types.Value::Null
        }
        table.set(d + i, value)
      }
    }

    // Drop
    Drop => self.stack.pop() |> ignore

    // Reference type instructions
    RefNull(ref_type) => {
      @logger.debug("exec ref.null: \{ref_type}")
      match ref_type {
        FuncRef
        | ExternRef
        | AnyRef
        | ExnRef
        | NullRef
        | NullFuncRef
        | NullExnRef
        | NullExternRef
        | RefFunc
        | RefExtern
        | RefFuncTyped(_)
        | RefNullFuncTyped(_)
        // GC reference types
        | RefNullEq
        | RefEq
        | RefNullI31
        | RefI31
        | StructRef
        | ArrayRef
        | RefNullStruct(_)
        | RefStruct(_)
        | RefNullArray(_)
        | RefArray(_) => self.stack.push(Null)
        _ => raise @runtime.RuntimeError::TypeMismatch
      }
    }
    RefIsNull => {
      let value = self.stack.pop()
      match value {
        Null => self.stack.push(I32(1))
        _ => self.stack.push(I32(0))
      }
    }
    RefFunc(func_idx) => {
      // Get the store address for the function
      let func_addr = self.instance.func_addrs[func_idx]
      self.stack.push(FuncRef(func_addr))
    }
    RefAsNonNull => {
      // ref.as_non_null: traps if reference is null
      let value = self.stack.pop()
      match value {
        Null => raise @runtime.RuntimeError::Unreachable
        _ => self.stack.push(value)
      }
    }
    RefEqInstr => {
      // ref.eq: compare two references for equality
      let v2 = self.stack.pop()
      let v1 = self.stack.pop()
      let equal = match (v1, v2) {
        (Null, Null) => true
        (FuncRef(a), FuncRef(b)) => a == b
        (ExternRef(a), ExternRef(b)) => a == b
        (ExnRef(a), ExnRef(b)) => a == b
        (I31(a), I31(b)) => a == b
        (StructRef(a), StructRef(b)) => a == b
        (ArrayRef(a), ArrayRef(b)) => a == b
        _ => false
      }
      self.stack.push(I32(if equal { 1 } else { 0 }))
    }
    BrOnNull(_) | BrOnNonNull(_) =>
      // br_on_null and br_on_non_null are control instructions
      self.exec_control(instr)

    // i32 numeric operations
    I32Add
    | I32Sub
    | I32Mul
    | I32DivS
    | I32DivU
    | I32RemS
    | I32RemU
    | I32Eq
    | I32Ne
    | I32LtS
    | I32LtU
    | I32GtS
    | I32GtU
    | I32LeS
    | I32LeU
    | I32GeS
    | I32GeU
    | I32Eqz
    | I32And
    | I32Or
    | I32Xor
    | I32Shl
    | I32ShrS
    | I32ShrU
    | I32Rotl
    | I32Rotr
    | I32Clz
    | I32Ctz
    | I32Popcnt
    | I32Extend8S
    | I32Extend16S => self.exec_i32_numeric(instr)

    // i64 numeric operations
    I64Add
    | I64Sub
    | I64Mul
    | I64MulWideS
    | I64MulWideU
    | I64DivS
    | I64DivU
    | I64RemS
    | I64RemU
    | I64Eq
    | I64Ne
    | I64LtS
    | I64LtU
    | I64GtS
    | I64GtU
    | I64LeS
    | I64LeU
    | I64GeS
    | I64GeU
    | I64Eqz
    | I64And
    | I64Or
    | I64Xor
    | I64Shl
    | I64ShrS
    | I64ShrU
    | I64Rotl
    | I64Rotr
    | I64Clz
    | I64Ctz
    | I64Popcnt
    | I64Extend8S
    | I64Extend16S
    | I64Extend32S => self.exec_i64_numeric(instr)

    // f32 numeric operations
    F32Add
    | F32Sub
    | F32Mul
    | F32Div
    | F32Abs
    | F32Neg
    | F32Sqrt
    | F32Ceil
    | F32Floor
    | F32Trunc
    | F32Nearest
    | F32Min
    | F32Max
    | F32Copysign
    | F32Eq
    | F32Ne
    | F32Lt
    | F32Gt
    | F32Le
    | F32Ge => self.exec_f32_numeric(instr)

    // f64 numeric operations
    F64Add
    | F64Sub
    | F64Mul
    | F64Div
    | F64Abs
    | F64Neg
    | F64Sqrt
    | F64Ceil
    | F64Floor
    | F64Trunc
    | F64Nearest
    | F64Min
    | F64Max
    | F64Copysign
    | F64Eq
    | F64Ne
    | F64Lt
    | F64Gt
    | F64Le
    | F64Ge => self.exec_f64_numeric(instr)

    // Conversion operations
    I32WrapI64
    | I64ExtendI32S
    | I64ExtendI32U
    | I32TruncF32S
    | I32TruncF32U
    | I32TruncF64S
    | I32TruncF64U
    | I64TruncF32S
    | I64TruncF32U
    | I64TruncF64S
    | I64TruncF64U
    | F32ConvertI32S
    | F32ConvertI32U
    | F32ConvertI64S
    | F32ConvertI64U
    | F64ConvertI32S
    | F64ConvertI32U
    | F64ConvertI64S
    | F64ConvertI64U
    | F32DemoteF64
    | F64PromoteF32
    | I32ReinterpretF32
    | I64ReinterpretF64
    | F32ReinterpretI32
    | F64ReinterpretI64 => self.exec_conversion(instr)

    // Saturating truncation operations
    I32TruncSatF32S
    | I32TruncSatF32U
    | I32TruncSatF64S
    | I32TruncSatF64U
    | I64TruncSatF32S
    | I64TruncSatF32U
    | I64TruncSatF64S
    | I64TruncSatF64U => self.exec_trunc_sat(instr)

    // Memory load operations
    I32Load(_, _, _)
    | I64Load(_, _, _)
    | F32Load(_, _, _)
    | F64Load(_, _, _)
    | I32Load8S(_, _, _)
    | I32Load8U(_, _, _)
    | I32Load16S(_, _, _)
    | I32Load16U(_, _, _)
    | I64Load8S(_, _, _)
    | I64Load8U(_, _, _)
    | I64Load16S(_, _, _)
    | I64Load16U(_, _, _)
    | I64Load32S(_, _, _)
    | I64Load32U(_, _, _) => self.exec_memory_load(instr)

    // Memory store operations
    I32Store(_, _, _)
    | I64Store(_, _, _)
    | F32Store(_, _, _)
    | F64Store(_, _, _)
    | I32Store8(_, _, _)
    | I32Store16(_, _, _)
    | I64Store8(_, _, _)
    | I64Store16(_, _, _)
    | I64Store32(_, _, _) => self.exec_memory_store(instr)

    // Memory size/grow and bulk operations
    MemorySize(_)
    | MemoryGrow(_)
    | MemoryInit(_, _)
    | DataDrop(_)
    | MemoryCopy(_, _)
    | MemoryFill(_)
    | ElemDrop(_)
    | Atomic(_, _, _, _) => self.exec_memory_misc(instr)

    // Control flow operations
    Block(_, _)
    | Loop(_, _)
    | If(_, _, _)
    | Br(_)
    | BrIf(_)
    | BrTable(_, _)
    | Unreachable
    | Select
    | SelectTyped(_)
    | Nop
    | Return => self.exec_control(instr)

    // Function call operations
    Call(func_idx) => self.exec_call(func_idx)
    CallIndirect(type_idx, table_idx) =>
      self.exec_call_indirect(type_idx, table_idx)
    CallRef(type_idx) => self.exec_call_ref(type_idx)

    // Tail call operations - replace current frame instead of pushing new one
    // This enables true tail call optimization (constant call depth)
    ReturnCall(func_idx) => self.exec_tail_call(func_idx)
    ReturnCallIndirect(type_idx, table_idx) =>
      self.exec_tail_call_indirect(type_idx, table_idx)
    ReturnCallRef(type_idx) => self.exec_tail_call_ref(type_idx)

    // Exception handling instructions
    Throw(tag_idx) => {
      // Get the tag type to know how many values to pop
      let tag_addr = self.instance.tag_addrs[tag_idx]
      let tag_type = self.store.get_tag_type(tag_addr)
      // Pop exception values from stack (in reverse order, then reverse back)
      let values : Array[@types.Value] = []
      for _ in 0..<tag_type.params.length() {
        values.push(self.stack.pop())
      }
      values.rev_in_place()
      // Raise the exception
      raise ThrowException(tag_addr, values)
    }
    ThrowRef => {
      // throw_ref throws an exception reference from the stack
      let exnref = self.stack.pop()
      match exnref {
        ExnRef(exn_addr) => {
          let exn = self.store.get_exn(exn_addr)
          raise ThrowException(exn.tag_addr, exn.values)
        }
        Null => raise @runtime.RuntimeError::NullReference
        _ => raise @runtime.RuntimeError::TypeMismatch
      }
    }
    TryTable(bt, handlers, body) => {
      let arity = self.block_arity(bt)
      let stack_height = self.stack.size()
      self.push_label(false, arity)
      let result = try? self.exec_block(body)
      self.pop_label()
      match result {
        Ok(_) => ()
        Err(ThrowException(tag_addr, values)) => {
          // Find a matching handler
          for handler in handlers {
            match handler {
              Catch(handler_tag_idx, label_idx) => {
                let handler_tag_addr = self.instance.tag_addrs[handler_tag_idx]
                if handler_tag_addr == tag_addr {
                  // Match! Push exception values and branch
                  self.restore_stack_to(stack_height)
                  for v in values {
                    self.stack.push(v)
                  }
                  raise BranchWith(label_idx, values)
                }
              }
              CatchRef(handler_tag_idx, label_idx) => {
                let handler_tag_addr = self.instance.tag_addrs[handler_tag_idx]
                if handler_tag_addr == tag_addr {
                  // Match! Push exception values and exnref, then branch
                  let exn_addr = self.store.alloc_exn(tag_addr, values)
                  self.restore_stack_to(stack_height)
                  for v in values {
                    self.stack.push(v)
                  }
                  self.stack.push(@types.Value::ExnRef(exn_addr))
                  let branch_values = values.copy()
                  branch_values.push(@types.Value::ExnRef(exn_addr))
                  raise BranchWith(label_idx, branch_values)
                }
              }
              CatchAll(label_idx) => {
                // Matches any exception
                self.restore_stack_to(stack_height)
                raise BranchWith(label_idx, [])
              }
              CatchAllRef(label_idx) => {
                // Matches any exception and pushes exnref
                let exn_addr = self.store.alloc_exn(tag_addr, values)
                self.restore_stack_to(stack_height)
                self.stack.push(@types.Value::ExnRef(exn_addr))
                raise BranchWith(label_idx, [@types.Value::ExnRef(exn_addr)])
              }
            }
          }
          // No handler matched, re-raise the exception
          raise ThrowException(tag_addr, values)
        }
        Err(BranchWith(0, values)) => {
          // Normal branch to end of try_table
          self.restore_stack_to(stack_height)
          for v in values {
            self.stack.push(v)
          }
        }
        Err(BranchWith(n, values)) => raise BranchWith(n - 1, values)
        Err(e) => raise e
      }
    }

    // GC instructions - struct operations
    StructNew(type_idx) => self.exec_struct_new(type_idx)
    StructNewDefault(type_idx) => self.exec_struct_new_default(type_idx)
    StructGet(type_idx, field_idx) => self.exec_struct_get(type_idx, field_idx)
    StructGetS(type_idx, field_idx) =>
      self.exec_struct_get_s(type_idx, field_idx)
    StructGetU(type_idx, field_idx) =>
      self.exec_struct_get_u(type_idx, field_idx)
    StructSet(type_idx, field_idx) => self.exec_struct_set(type_idx, field_idx)

    // GC instructions - array operations
    ArrayNew(type_idx) => self.exec_array_new(type_idx)
    ArrayNewDefault(type_idx) => self.exec_array_new_default(type_idx)
    ArrayNewFixed(type_idx, len) => self.exec_array_new_fixed(type_idx, len)
    ArrayNewData(type_idx, data_idx) =>
      self.exec_array_new_data(type_idx, data_idx)
    ArrayNewElem(type_idx, elem_idx) =>
      self.exec_array_new_elem(type_idx, elem_idx)
    ArrayGet(type_idx) => self.exec_array_get(type_idx)
    ArrayGetS(type_idx) => self.exec_array_get_s(type_idx)
    ArrayGetU(type_idx) => self.exec_array_get_u(type_idx)
    ArraySet(type_idx) => self.exec_array_set(type_idx)
    ArrayLen => self.exec_array_len()
    ArrayFill(type_idx) => self.exec_array_fill(type_idx)
    ArrayCopy(dst_type_idx, src_type_idx) =>
      self.exec_array_copy(dst_type_idx, src_type_idx)
    ArrayInitData(type_idx, data_idx) =>
      self.exec_array_init_data(type_idx, data_idx)
    ArrayInitElem(type_idx, elem_idx) =>
      self.exec_array_init_elem(type_idx, elem_idx)

    // GC instructions - reference casting
    RefTest(target_type) => self.exec_ref_test(target_type)
    RefTestNull(target_type) => self.exec_ref_test_null(target_type)
    RefCast(target_type) => self.exec_ref_cast(target_type)
    RefCastNull(target_type) => self.exec_ref_cast_null(target_type)
    BrOnCast(label_idx, _from_type, target_type) =>
      self.exec_br_on_cast(label_idx, target_type)
    BrOnCastFail(label_idx, _from_type, target_type) =>
      self.exec_br_on_cast_fail(label_idx, target_type)

    // GC instructions - i31
    RefI31 => self.exec_ref_i31()
    I31GetS => self.exec_i31_get_s()
    I31GetU => self.exec_i31_get_u()

    // GC instructions - type conversion
    AnyConvertExtern => self.exec_any_convert_extern()
    ExternConvertAny => self.exec_extern_convert_any()

    // SIMD instructions - to be implemented in Phase 6
    V128Const(_)
    | V128Load(_, _, _)
    | V128Load8x8S(_, _, _)
    | V128Load8x8U(_, _, _)
    | V128Load16x4S(_, _, _)
    | V128Load16x4U(_, _, _)
    | V128Load32x2S(_, _, _)
    | V128Load32x2U(_, _, _)
    | V128Load8Splat(_, _, _)
    | V128Load16Splat(_, _, _)
    | V128Load32Splat(_, _, _)
    | V128Load64Splat(_, _, _)
    | V128Load32Zero(_, _, _)
    | V128Load64Zero(_, _, _)
    | V128Store(_, _, _)
    | V128Load8Lane(_, _, _, _)
    | V128Load16Lane(_, _, _, _)
    | V128Load32Lane(_, _, _, _)
    | V128Load64Lane(_, _, _, _)
    | V128Store8Lane(_, _, _, _)
    | V128Store16Lane(_, _, _, _)
    | V128Store32Lane(_, _, _, _)
    | V128Store64Lane(_, _, _, _)
    | I8x16Shuffle(_)
    | I8x16Swizzle
    | I8x16Splat
    | I16x8Splat
    | I32x4Splat
    | I64x2Splat
    | F32x4Splat
    | F64x2Splat
    | I8x16ExtractLaneS(_)
    | I8x16ExtractLaneU(_)
    | I16x8ExtractLaneS(_)
    | I16x8ExtractLaneU(_)
    | I32x4ExtractLane(_)
    | I64x2ExtractLane(_)
    | F32x4ExtractLane(_)
    | F64x2ExtractLane(_)
    | I8x16ReplaceLane(_)
    | I16x8ReplaceLane(_)
    | I32x4ReplaceLane(_)
    | I64x2ReplaceLane(_)
    | F32x4ReplaceLane(_)
    | F64x2ReplaceLane(_)
    | I8x16Eq
    | I8x16Ne
    | I8x16LtS
    | I8x16LtU
    | I8x16GtS
    | I8x16GtU
    | I8x16LeS
    | I8x16LeU
    | I8x16GeS
    | I8x16GeU
    | I16x8Eq
    | I16x8Ne
    | I16x8LtS
    | I16x8LtU
    | I16x8GtS
    | I16x8GtU
    | I16x8LeS
    | I16x8LeU
    | I16x8GeS
    | I16x8GeU
    | I32x4Eq
    | I32x4Ne
    | I32x4LtS
    | I32x4LtU
    | I32x4GtS
    | I32x4GtU
    | I32x4LeS
    | I32x4LeU
    | I32x4GeS
    | I32x4GeU
    | I64x2Eq
    | I64x2Ne
    | I64x2LtS
    | I64x2GtS
    | I64x2LeS
    | I64x2GeS
    | F32x4Eq
    | F32x4Ne
    | F32x4Lt
    | F32x4Gt
    | F32x4Le
    | F32x4Ge
    | F64x2Eq
    | F64x2Ne
    | F64x2Lt
    | F64x2Gt
    | F64x2Le
    | F64x2Ge
    | V128Not
    | V128And
    | V128AndNot
    | V128Or
    | V128Xor
    | V128Bitselect
    | V128AnyTrue
    | I8x16Abs
    | I8x16Neg
    | I8x16Popcnt
    | I8x16AllTrue
    | I8x16Bitmask
    | I8x16NarrowI16x8S
    | I8x16NarrowI16x8U
    | I8x16Shl
    | I8x16ShrS
    | I8x16ShrU
    | I8x16Add
    | I8x16AddSatS
    | I8x16AddSatU
    | I8x16Sub
    | I8x16SubSatS
    | I8x16SubSatU
    | I8x16MinS
    | I8x16MinU
    | I8x16MaxS
    | I8x16MaxU
    | I8x16AvgrU
    | I16x8ExtAddPairwiseI8x16S
    | I16x8ExtAddPairwiseI8x16U
    | I16x8Abs
    | I16x8Neg
    | I16x8Q15MulrSatS
    | I16x8AllTrue
    | I16x8Bitmask
    | I16x8NarrowI32x4S
    | I16x8NarrowI32x4U
    | I16x8ExtendLowI8x16S
    | I16x8ExtendHighI8x16S
    | I16x8ExtendLowI8x16U
    | I16x8ExtendHighI8x16U
    | I16x8Shl
    | I16x8ShrS
    | I16x8ShrU
    | I16x8Add
    | I16x8AddSatS
    | I16x8AddSatU
    | I16x8Sub
    | I16x8SubSatS
    | I16x8SubSatU
    | I16x8Mul
    | I16x8MinS
    | I16x8MinU
    | I16x8MaxS
    | I16x8MaxU
    | I16x8AvgrU
    | I16x8ExtMulLowI8x16S
    | I16x8ExtMulHighI8x16S
    | I16x8ExtMulLowI8x16U
    | I16x8ExtMulHighI8x16U
    | I32x4ExtAddPairwiseI16x8S
    | I32x4ExtAddPairwiseI16x8U
    | I32x4Abs
    | I32x4Neg
    | I32x4AllTrue
    | I32x4Bitmask
    | I32x4ExtendLowI16x8S
    | I32x4ExtendHighI16x8S
    | I32x4ExtendLowI16x8U
    | I32x4ExtendHighI16x8U
    | I32x4Shl
    | I32x4ShrS
    | I32x4ShrU
    | I32x4Add
    | I32x4Sub
    | I32x4Mul
    | I32x4MinS
    | I32x4MinU
    | I32x4MaxS
    | I32x4MaxU
    | I32x4DotI16x8S
    | I32x4ExtMulLowI16x8S
    | I32x4ExtMulHighI16x8S
    | I32x4ExtMulLowI16x8U
    | I32x4ExtMulHighI16x8U
    | I64x2Abs
    | I64x2Neg
    | I64x2AllTrue
    | I64x2Bitmask
    | I64x2ExtendLowI32x4S
    | I64x2ExtendHighI32x4S
    | I64x2ExtendLowI32x4U
    | I64x2ExtendHighI32x4U
    | I64x2Shl
    | I64x2ShrS
    | I64x2ShrU
    | I64x2Add
    | I64x2Sub
    | I64x2Mul
    | I64x2ExtMulLowI32x4S
    | I64x2ExtMulHighI32x4S
    | I64x2ExtMulLowI32x4U
    | I64x2ExtMulHighI32x4U
    | F32x4Ceil
    | F32x4Floor
    | F32x4Trunc
    | F32x4Nearest
    | F32x4Abs
    | F32x4Neg
    | F32x4Sqrt
    | F32x4Add
    | F32x4Sub
    | F32x4Mul
    | F32x4Div
    | F32x4Min
    | F32x4Max
    | F32x4Pmin
    | F32x4Pmax
    | F64x2Ceil
    | F64x2Floor
    | F64x2Trunc
    | F64x2Nearest
    | F64x2Abs
    | F64x2Neg
    | F64x2Sqrt
    | F64x2Add
    | F64x2Sub
    | F64x2Mul
    | F64x2Div
    | F64x2Min
    | F64x2Max
    | F64x2Pmin
    | F64x2Pmax
    | I32x4TruncSatF32x4S
    | I32x4TruncSatF32x4U
    | F32x4ConvertI32x4S
    | F32x4ConvertI32x4U
    | I32x4TruncSatF64x2SZero
    | I32x4TruncSatF64x2UZero
    | F64x2ConvertLowI32x4S
    | F64x2ConvertLowI32x4U
    | F32x4DemoteF64x2Zero
    | F64x2PromoteLowF32x4
    // Relaxed SIMD
    | I8x16RelaxedSwizzle
    | I32x4RelaxedTruncF32x4S
    | I32x4RelaxedTruncF32x4U
    | I32x4RelaxedTruncF64x2SZero
    | I32x4RelaxedTruncF64x2UZero
    | F32x4RelaxedMadd
    | F32x4RelaxedNmadd
    | F64x2RelaxedMadd
    | F64x2RelaxedNmadd
    | I8x16RelaxedLaneselect
    | I16x8RelaxedLaneselect
    | I32x4RelaxedLaneselect
    | I64x2RelaxedLaneselect
    | F32x4RelaxedMin
    | F32x4RelaxedMax
    | F64x2RelaxedMin
    | F64x2RelaxedMax
    | I16x8RelaxedQ15mulrS
    | I16x8RelaxedDotI8x16I7x16S
    | I32x4RelaxedDotI8x16I7x16AddS => self.exec_simd(instr)
  }
}

// ============================================================
// Function Execution
// ============================================================

///|
/// Call a function by index
pub fn ExecContext::call_func(
  self : ExecContext,
  func_idx : Int,
  args : Array[@types.Value],
) -> Array[@types.Value] raise {
  // Get the store address from instance
  let store_addr = self.instance.func_addrs[func_idx]
  let func_inst = self.store.get_func_inst(store_addr)

  // Get the function type to determine return arity
  let type_idx = self.instance.func_type_indices[func_idx]
  let func_type = self.instance.get_func_type(type_idx)
  let return_arity = func_type.results.length()

  // Use the same context-switching logic as exec_call
  self.call_func_inst_with_context(store_addr, func_inst, args, return_arity)

  // Collect return values from stack (in reverse order, then reverse back)
  let results : Array[@types.Value] = []
  for _ in 0..<return_arity {
    results.push(self.stack.pop())
  }
  results.rev_in_place()
  results
}
