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

// ============================================================
// Module Instantiation (MVP)
// ============================================================

///|
/// Create a simple module instance from a parsed module
pub fn instantiate_module(
  mod : @types.Module,
) -> (@runtime.Store, @runtime.ModuleInstance) {
  let store = @runtime.Store::new()
  // Set module types for GC support
  store.set_module_types(mod.types, rec_groups=mod.type_rec_groups)

  // Allocate functions with their types
  let func_addrs : Array[Int] = []
  for i, code in mod.codes {
    let type_idx = mod.funcs[i]
    let func_type = mod.get_func_type(type_idx)
    let addr = store.alloc_func(code, func_type~, type_idx~)
    func_addrs.push(addr)
  }

  // Allocate memories
  let mem_addrs : Array[Int] = []
  for i, mem_type in mod.memories {
    let min = mem_type.limits.min.to_int()
    let max = mem_type.limits.max.map(fn(m) { m.to_int() })
    let mem = if i == 0 &&
      !mem_type.is_memory64 &&
      mem_type.page_size_log2 == 16 {
      @runtime.Memory::new_guarded_memory0(min, max)
    } else {
      @runtime.Memory::new(
        min,
        max,
        is_memory64=mem_type.is_memory64,
        page_size_log2=mem_type.page_size_log2,
      )
    }
    let addr = store.alloc_mem(mem)
    mem_addrs.push(addr)
  }

  // Allocate tables
  // Note: table init expressions can reference imported globals, so we need to
  // create imported global instances first if we have any table init expressions.
  // For simplicity, we'll evaluate table init expressions with an empty globals array
  // since the validator already ensures only imported globals can be referenced.
  let table_addrs : Array[Int] = []
  for table_def in mod.tables {
    // Evaluate table init expression if present
    let init_value : @types.Value = if table_def.init is Some(init_expr) {
      eval_const_expr(
        init_expr,
        func_addrs~,
        globals=[],
        store=Some(store),
        types=mod.types,
      )
    } else {
      @types.Value::Null
    }
    let table = @runtime.Table::new(
      table_def.type_.elem_type,
      table_def.type_.limits.min.to_int(),
      table_def.type_.limits.max.map(fn(m) { m.to_int() }),
      init_value~,
      is_table64=table_def.type_.is_table64,
    )
    let addr = store.alloc_table(table)
    table_addrs.push(addr)
  }

  // Allocate globals with initialization
  let global_addrs : Array[Int] = []
  let global_instances : Array[@runtime.GlobalInstance] = []
  for global in mod.globals {
    // Evaluate init expression with access to already-initialized globals
    // Pass store and types for GC const expr support (array.new_default, struct.new, etc.)
    let init_value = eval_const_expr(
      global.init,
      func_addrs~,
      globals=global_instances,
      store=Some(store),
      types=mod.types,
    )
    let global_inst = @runtime.GlobalInstance::new(global.type_, init_value)
    let addr = store.alloc_global(global_inst)
    global_addrs.push(addr)
    global_instances.push(global_inst)
  }

  // Allocate tags
  let tag_addrs : Array[Int] = []
  for tag in mod.tags {
    let tag_type = mod.get_func_type(tag.type_idx)
    let addr = store.alloc_tag(tag_type, type_idx=tag.type_idx)
    tag_addrs.push(addr)
  }

  // func_addrs: indices into store.funcs
  // func_type_indices: type index for each function (from mod.funcs)
  // Initialize dropped arrays with false values
  let dropped_elems : Array[Bool] = []
  for _ in 0..<mod.elems.length() {
    dropped_elems.push(false)
  }
  let dropped_datas : Array[Bool] = []
  for _ in 0..<mod.datas.length() {
    dropped_datas.push(false)
  }
  // Compute canonical type indices for structural equivalence
  let canonical_type_indices = @types.compute_canonical_type_indices(
    mod.types,
    type_rec_groups=mod.type_rec_groups,
  )
  let instance : @runtime.ModuleInstance = {
    types: mod.types,
    type_rec_groups: mod.type_rec_groups,
    canonical_type_indices,
    store_idx: -1,
    func_addrs,
    func_type_indices: mod.funcs,
    table_addrs,
    mem_addrs,
    global_addrs,
    tag_addrs,
    exports: mod.exports,
    elem_segments: mod.elems,
    data_segments: mod.datas,
    dropped_elems,
    dropped_datas,
  }
  (store, instance)
}

///|
/// Evaluate a constant initialization expression
/// Supports extended constant expressions with arithmetic operations
/// and GC instructions (array.new, array.new_default, array.new_fixed, struct.new, struct.new_default)
fn eval_const_expr(
  instrs : Array[@types.Instruction],
  func_addrs? : Array[Int] = [],
  globals? : Array[@runtime.GlobalInstance] = [],
  store? : @runtime.Store? = None,
  types? : Array[@types.SubType] = [],
) -> @types.Value {
  // Use stack-based evaluation for extended constant expressions
  let stack : Array[@types.Value] = []
  for instr in instrs {
    match instr {
      I32Const(n) => stack.push(I32(n))
      I64Const(n) => stack.push(I64(n))
      F32Const(f) => stack.push(F32(f))
      F64Const(d) => stack.push(F64(d))
      V128Const(bytes) => stack.push(V128(bytes))
      RefNull(_) => stack.push(Null)
      RefFunc(idx) => {
        let store_addr = if idx < func_addrs.length() {
          func_addrs[idx]
        } else {
          idx
        }
        stack.push(FuncRef(store_addr))
      }
      GlobalGet(idx) =>
        if idx < globals.length() {
          stack.push(globals[idx].get())
        }
      // GC: i31 reference creation
      RefI31 =>
        if stack.length() >= 1 {
          let val = stack.pop().unwrap()
          match val {
            I32(n) => {
              // i31 stores only the lower 31 bits
              let i31_val = n & 0x7FFFFFFF
              stack.push(I31(i31_val))
            }
            _ => ()
          }
        }
      // GC: array.new_default - create array with default values
      ArrayNewDefault(type_idx) =>
        if stack.length() >= 1 && store is Some(s) && type_idx < types.length() {
          let len_val = stack.pop().unwrap()
          if len_val is I32(len) {
            let array_type = match types[type_idx].composite {
              Array(at) => at
              _ => continue
            }
            let default_val = default_value_for_storage_type(
              array_type.element.storage_type,
            )
            let elements : Array[@types.Value] = Array::make(len, default_val)
            let ref_idx = s.alloc_array(type_idx, elements)
            stack.push(ArrayRef(ref_idx))
          }
        }
      // GC: array.new - create array with initial value
      ArrayNew(type_idx) =>
        if stack.length() >= 2 && store is Some(s) {
          let len_val = stack.pop().unwrap()
          let init_val = stack.pop().unwrap()
          if len_val is I32(len) {
            let elements : Array[@types.Value] = Array::make(len, init_val)
            let ref_idx = s.alloc_array(type_idx, elements)
            stack.push(ArrayRef(ref_idx))
          }
        }
      // GC: array.new_fixed - create array from fixed number of stack values
      ArrayNewFixed(type_idx, len) =>
        if store is Some(s) && type_idx < types.length() {
          // Ensure this is actually an array type.
          match types[type_idx].composite {
            Array(_) => ()
            _ => continue
          }
          if len == 0 {
            let ref_idx = s.alloc_array(type_idx, [])
            stack.push(ArrayRef(ref_idx))
          } else if stack.length() >= len {
            // Pop elements in reverse order (last element pushed first).
            let elements : Array[@types.Value] = Array::make(
              len,
              @types.Value::Null,
            )
            for i = len - 1; i >= 0; i = i - 1 {
              elements[i] = stack.pop().unwrap()
            }
            let ref_idx = s.alloc_array(type_idx, elements)
            stack.push(ArrayRef(ref_idx))
          }
        }
      // GC: struct.new_default - create struct with default values
      StructNewDefault(type_idx) =>
        if store is Some(s) && type_idx < types.length() {
          let struct_type = match types[type_idx].composite {
            Struct(st) => st
            _ => continue
          }
          let fields : Array[@types.Value] = []
          for field in struct_type.fields {
            fields.push(default_value_for_storage_type(field.storage_type))
          }
          let ref_idx = s.alloc_struct(type_idx, fields)
          stack.push(StructRef(ref_idx))
        }
      // GC: struct.new - create struct from stack values
      StructNew(type_idx) =>
        if store is Some(s) && type_idx < types.length() {
          let struct_type = match types[type_idx].composite {
            Struct(st) => st
            _ => continue
          }
          let num_fields = struct_type.fields.length()
          if stack.length() >= num_fields {
            // Pop fields in reverse order (last field pushed first)
            let fields : Array[@types.Value] = Array::make(
              num_fields,
              @types.Value::Null,
            )
            for i = num_fields - 1; i >= 0; i = i - 1 {
              fields[i] = stack.pop().unwrap()
            }
            let ref_idx = s.alloc_struct(type_idx, fields)
            stack.push(StructRef(ref_idx))
          }
        }
      // i32 arithmetic operations
      I32Add =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          if (a, b) is (I32(av), I32(bv)) {
            stack.push(I32(av + bv))
          }
        }
      I32Sub =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          if (a, b) is (I32(av), I32(bv)) {
            stack.push(I32(av - bv))
          }
        }
      I32Mul =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          if (a, b) is (I32(av), I32(bv)) {
            stack.push(I32(av * bv))
          }
        }
      // i64 arithmetic operations
      I64Add =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          if (a, b) is (I64(av), I64(bv)) {
            stack.push(I64(av + bv))
          }
        }
      I64Sub =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          if (a, b) is (I64(av), I64(bv)) {
            stack.push(I64(av - bv))
          }
        }
      I64Mul =>
        if stack.length() >= 2 {
          let b = stack.pop().unwrap()
          let a = stack.pop().unwrap()
          match (a, b) {
            (I64(av), I64(bv)) => stack.push(I64(av * bv))
            _ => ()
          }
        }
      _ => ()
    }
  }
  if stack.length() > 0 {
    stack[stack.length() - 1]
  } else {
    Null
  }
}

///|
/// Evaluate an extended constant expression for elem/data segment offsets
/// Supports i32/i64.add, i32/i64.sub, i32/i64.mul in addition to basic constants
/// Returns the offset value as Int (truncated for i64)
fn eval_extended_const_expr(
  instrs : Array[@types.Instruction],
  globals : Array[@runtime.GlobalInstance],
) -> Int {
  // Use a simple stack-based evaluator with Int64 to handle both i32 and i64
  let stack : Array[Int64] = []
  for instr in instrs {
    match instr {
      I32Const(n) => stack.push(n.to_int64())
      I64Const(n) => stack.push(n)
      GlobalGet(idx) =>
        if idx < globals.length() {
          match globals[idx].get() {
            I32(n) => stack.push(n.to_int64())
            I64(n) => stack.push(n)
            _ => ()
          }
        }
      I32Add | I64Add =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() + b.unwrap())
        }
      I32Sub | I64Sub =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() - b.unwrap())
        }
      I32Mul | I64Mul =>
        if stack.length() >= 2 {
          let b = stack.pop()
          let a = stack.pop()
          stack.push(a.unwrap() * b.unwrap())
        }
      _ => ()
    }
  }
  if stack.length() > 0 {
    stack[stack.length() - 1].to_int()
  } else {
    0
  }
}

///|
/// Helper to get global instances from a store given global addresses
fn get_global_instances(
  store : @runtime.Store,
  global_addrs : Array[Int],
) -> Array[@runtime.GlobalInstance] {
  let globals : Array[@runtime.GlobalInstance] = []
  for addr in global_addrs {
    globals.push(store.get_global(addr)) catch {
      _ => ()
    }
  }
  globals
}

///|
/// Evaluate an elem segment init expression to get a Value
/// Returns None for unsupported expressions that should be skipped
fn eval_elem_init_expr(
  init_expr : Array[@types.Instruction],
  func_addrs : Array[Int],
  globals : Array[@runtime.GlobalInstance],
) -> @types.Value? {
  match init_expr {
    [RefFunc(idx)] => {
      // Convert module function index to store address
      let store_addr = if idx < func_addrs.length() {
        func_addrs[idx]
      } else {
        idx // fallback, should not happen for valid modules
      }
      Some(@types.Value::FuncRef(store_addr))
    }
    [I32Const(idx)] => {
      // Legacy format: function index as i32
      let store_addr = if idx < func_addrs.length() {
        func_addrs[idx]
      } else {
        idx // fallback
      }
      Some(@types.Value::FuncRef(store_addr))
    }
    [RefNull(_)] => Some(@types.Value::Null)
    [GlobalGet(idx)] =>
      // Get funcref from global
      if idx < globals.length() {
        Some(globals[idx].get())
      } else {
        None
      }
    // GC: handle ref.i31 expressions for i31ref element segments
    [I32Const(n), RefI31] => {
      // i31 stores only the lower 31 bits
      let i31_val = n & 0x7FFFFFFF
      Some(@types.Value::I31(i31_val))
    }
    [GlobalGet(idx), RefI31] =>
      // ref.i31 with global value
      if idx < globals.length() {
        match globals[idx].get() {
          I32(n) => {
            let i31_val = n & 0x7FFFFFFF
            Some(@types.Value::I31(i31_val))
          }
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
/// Create a module instance with element and data segment initialization
pub fn instantiate_module_with_init(
  mod : @types.Module,
) -> (@runtime.Store, @runtime.ModuleInstance) raise @runtime.RuntimeError {
  let (store, instance) = instantiate_module(mod)

  // Per WebAssembly spec: element segments are initialized BEFORE data segments
  // This ensures that if data segment initialization traps, the element segment
  // modifications to shared tables are already visible.

  // Initialize element segments (populate tables with function references)
  for elem_idx, elem in mod.elems {
    // Only process active element segments
    if elem.mode is @types.ElemMode::Active(table_idx, offset_expr) {
      if instance.table_addrs.length() > table_idx {
        let table = store.get_table(instance.table_addrs[table_idx])

        // Evaluate offset expression using extended const expr evaluator
        let globals = get_global_instances(store, instance.global_addrs)
        let offset = eval_extended_const_expr(offset_expr, globals)

        // Check bounds before initializing
        // offset + num_elements must not exceed table size
        if offset < 0 || offset + elem.init.length() > table.size() {
          raise @runtime.OutOfBoundsTableAccess
        }

        // Set table entries - evaluate init expression to get value
        for i, init_expr in elem.init {
          match eval_elem_init_expr(init_expr, instance.func_addrs, globals) {
            Some(value) => table.set(offset + i, value)
            None => continue
          }
        }
      }
      // Active elem segments are implicitly dropped after initialization
      instance.dropped_elems[elem_idx] = true
    }
  }

  // Initialize data segments (copy data to memory)
  // Get global instances for evaluating offset expressions
  let globals_for_data = get_global_instances(store, instance.global_addrs)
  for data in mod.datas {
    if instance.mem_addrs.length() > data.memory_idx {
      let mem = store.get_mem(instance.mem_addrs[data.memory_idx])

      // Evaluate offset expression using extended const expr evaluator
      let offset = eval_extended_const_expr(data.offset, globals_for_data)

      // Copy data to memory
      mem.init_data(offset, data.init)
    }
  }

  // Execute start function if present
  if mod.start is Some(start_func_idx) {
    let ctx = ExecContext::new(store, instance)
    (ctx.call_func(start_func_idx, []) catch {
      BranchWith(_, _) | Return => raise @runtime.Unreachable
      @runtime.StackUnderflow => raise @runtime.StackUnderflow
      @runtime.StackOverflow => raise @runtime.StackOverflow
      @runtime.TypeMismatch => raise @runtime.TypeMismatch
      @runtime.OutOfBoundsMemoryAccess => raise @runtime.OutOfBoundsMemoryAccess
      @runtime.OutOfBoundsTableAccess => raise @runtime.OutOfBoundsTableAccess
      @runtime.OutOfBoundsArrayAccess => raise @runtime.OutOfBoundsArrayAccess
      @runtime.UndefinedElement => raise @runtime.UndefinedElement
      @runtime.UninitializedElement => raise @runtime.UninitializedElement
      @runtime.IndirectCallTypeMismatch =>
        raise @runtime.IndirectCallTypeMismatch
      @runtime.DivisionByZero => raise @runtime.DivisionByZero
      @runtime.IntegerOverflow => raise @runtime.IntegerOverflow
      @runtime.InvalidConversion => raise @runtime.InvalidConversion
      @runtime.Unreachable => raise @runtime.Unreachable
      @runtime.CallStackExhausted => raise @runtime.CallStackExhausted
      @runtime.UnknownImport(_) as e => raise e
      @runtime.NullReference => raise @runtime.NullReference
      @runtime.UnalignedAtomic => raise @runtime.UnalignedAtomic
      _ => raise @runtime.Unreachable
    })
    |> ignore
  }
  (store, instance)
}

///|
/// Create a module instance with imports using an existing store
/// Raises UnknownImport if any required import is not provided
pub fn instantiate_module_with_imports(
  store : @runtime.Store,
  mod : @types.Module,
  imports : @runtime.Imports,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  // Set module types for GC support
  store.set_module_types(mod.types, rec_groups=mod.type_rec_groups)

  // Compute canonical type indices early (needed for import type checking)
  let canonical_type_indices = @types.compute_canonical_type_indices(
    mod.types,
    type_rec_groups=mod.type_rec_groups,
  )

  // Process imports first
  let func_addrs : Array[Int] = []
  let func_type_indices : Array[Int] = []
  let mem_addrs : Array[Int] = []
  let table_addrs : Array[Int] = []
  let global_addrs : Array[Int] = []
  let tag_addrs : Array[Int] = []

  // Import functions and memories first (they come before module definitions in the index space)
  for imp in mod.imports {
    match imp.desc {
      Func(type_idx) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Func(addr)) => {
            // Check that imported function type matches expected type
            let owner = store.get_func_owner(addr)
            let expected_type = mod.get_func_type(type_idx)
            let actual_type = store.get_func_type(addr)
            match owner {
              Some(o) => {
                // Cross-module function: the exported type must be a subtype
                // of the imported type (T_export <: T_import).
                // For GC types, this means checking declared supertype chains
                // and structural compatibility across modules.
                let actual_type_idx = store.get_func_type_idx(addr)

                // Compute canonical indices for both modules
                let canonical_import = canonical_type_indices
                let canonical_export = @types.compute_canonical_type_indices(
                  o.types,
                  type_rec_groups=o.type_rec_groups,
                )

                // Use subtyping context for cross-module comparison
                let ctx = @types.SubtypingContext::cross_module(
                  o.types,
                  mod.types,
                  rec_groups1=o.type_rec_groups,
                  rec_groups2=mod.type_rec_groups,
                  canonical1=canonical_export,
                  canonical2=canonical_import,
                )
                // Check if T_export <: T_import
                if not(ctx.is_subtype(actual_type_idx, type_idx)) {
                  raise @runtime.LinkErrorDetail(
                    "import \{imp.mod_name}.\{imp.name}: exported type is not a subtype of imported type",
                  )
                }
              }
              None => {
                // Host function: direct type comparison (no rec groups)
                // Host functions are always considered singleton rec groups
                let expected_rec_info = @types.get_rec_group_info(
                  mod.type_rec_groups,
                  type_idx,
                )
                // Host functions must be imported by singleton rec group types
                if expected_rec_info != (0, 1) {
                  raise @runtime.LinkErrorDetail(
                    "import \{imp.mod_name}.\{imp.name}: expected singleton rec group type, got \{expected_rec_info}",
                  )
                }
                // Compare types structurally
                if not(@types.func_types_equal(expected_type, actual_type)) {
                  raise @runtime.LinkErrorDetail(
                    "import \{imp.mod_name}.\{imp.name}: type mismatch; expected=\{expected_type} actual=\{actual_type}",
                  )
                }
              }
            }
            func_addrs.push(addr)
            func_type_indices.push(type_idx)
          }
          _ => raise @runtime.UnknownImport(imp.mod_name, imp.name)
        }
      Memory(expected_mem_type) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Memory(addr)) => {
            // Check memory type compatibility
            let actual_mem = store.get_mem(addr)
            let actual_limits = actual_mem.get_limits()
            // Memory64 status must match
            if actual_mem.is_memory64() != expected_mem_type.is_memory64 {
              raise @runtime.LinkError
            }
            // Import memory limits must be compatible:
            // - actual min >= expected min
            // - if expected has max, actual must have max <= expected max
            if actual_limits.0 < expected_mem_type.limits.min.to_int() {
              raise @runtime.LinkError
            }
            if expected_mem_type.limits.max is Some(expected_max) {
              match actual_limits.1 {
                Some(actual_max) =>
                  if actual_max > expected_max.to_int() {
                    raise @runtime.LinkError
                  }
                None => raise @runtime.LinkError
              }
            } // actual has no max but expected does
            mem_addrs.push(addr)
          }
          _ => raise @runtime.UnknownImport(imp.mod_name, imp.name)
        }
      Table(expected_table_type) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Table(addr)) => {
            // Check table type compatibility
            let actual_table = store.get_table(addr)
            let actual_elem_type = actual_table.get_elem_type()
            let actual_limits = actual_table.get_limits()
            // Element types must match
            if actual_elem_type != expected_table_type.elem_type {
              raise @runtime.LinkError
            }
            // Table64 status must match
            if actual_table.is_table64() != expected_table_type.is_table64 {
              raise @runtime.LinkError
            }
            // Limits must be compatible:
            // - actual min >= expected min
            // - if expected has max, actual must have max <= expected max
            if actual_limits.0 < expected_table_type.limits.min.to_int() {
              raise @runtime.LinkError
            }
            if expected_table_type.limits.max is Some(expected_max) {
              match actual_limits.1 {
                Some(actual_max) =>
                  if actual_max > expected_max.to_int() {
                    raise @runtime.LinkError
                  }
                None => raise @runtime.LinkError
              }
            }
            table_addrs.push(addr)
          }
          _ => raise @runtime.UnknownImport(imp.mod_name, imp.name)
        }
      Global(expected_global_type) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Global(addr)) => {
            // Check global type compatibility
            let actual_global = store.get_global(addr)
            let actual_type = actual_global.get_type()
            // For mutable globals: types must match exactly (invariant)
            // For immutable globals: expected type must be supertype of actual type
            if actual_type.mutable {
              // Mutable globals: exact match required
              if actual_type.value_type != expected_global_type.value_type {
                raise @runtime.LinkError
              }
              if actual_type.mutable != expected_global_type.mutable {
                raise @runtime.LinkError
              }
            } else {
              // Immutable globals: expected must be supertype of actual
              // (i.e., actual is subtype of expected)
              if !is_value_type_subtype(
                  actual_type.value_type,
                  expected_global_type.value_type,
                ) {
                raise @runtime.LinkError
              }
              // Import must also be immutable for immutable export
              if expected_global_type.mutable {
                raise @runtime.LinkError
              }
            }
            global_addrs.push(addr)
          }
          _ => raise @runtime.UnknownImport(imp.mod_name, imp.name)
        }
      Tag(expected_type_idx) =>
        match imports.resolve(imp.mod_name, imp.name) {
          Some(Tag(addr)) => {
            // Check that imported tag type matches expected type
            let owner = store.get_tag_owner(addr)
            let actual_type_idx = store.get_tag_type_idx(addr)
            let expected_type = mod.get_func_type(expected_type_idx)
            let actual_type = try! store.get_tag_type(addr)
            match owner {
              Some(o) => {
                // Cross-module tag: check rec group membership
                let expected_rec_info = @types.get_rec_group_info(
                  mod.type_rec_groups,
                  expected_type_idx,
                )
                let actual_rec_info = @types.get_rec_group_info(
                  o.type_rec_groups,
                  actual_type_idx,
                )

                // If both are singleton rec groups, compare structurally
                if expected_rec_info.1 == 1 && actual_rec_info.1 == 1 {
                  // Both are singleton - structural comparison
                  if expected_type.params != actual_type.params {
                    raise @runtime.LinkError
                  }
                } else {
                  // At least one is in a multi-type rec group - use canonical comparison
                  let canonical_import = canonical_type_indices
                  let canonical_export = @types.compute_canonical_type_indices(
                    o.types,
                    type_rec_groups=o.type_rec_groups,
                  )

                  // Use subtyping context for cross-module comparison
                  let ctx = @types.SubtypingContext::cross_module(
                    o.types,
                    mod.types,
                    rec_groups1=o.type_rec_groups,
                    rec_groups2=mod.type_rec_groups,
                    canonical1=canonical_export,
                    canonical2=canonical_import,
                  )
                  // For tags in rec groups, types must match via canonical indices
                  // Check bidirectional subtyping for equality
                  if not(
                      ctx.is_subtype(actual_type_idx, expected_type_idx) &&
                      ctx.is_subtype(expected_type_idx, actual_type_idx),
                    ) {
                    raise @runtime.LinkError
                  }
                }
              }
              None =>
                // No owner - fallback to structural comparison
                if expected_type.params != actual_type.params {
                  raise @runtime.LinkError
                }
            }
            tag_addrs.push(addr)
          }
          _ => raise @runtime.UnknownImport(imp.mod_name, imp.name)
        }
    }
  }

  // Allocate module functions with their types
  for i, code in mod.codes {
    let type_idx = mod.funcs[i]
    let func_type = mod.get_func_type(type_idx)
    let addr = store.alloc_func(code, func_type~, type_idx~)
    func_addrs.push(addr)
    func_type_indices.push(type_idx)
  }

  // Allocate memories (after imported memories)
  for mem_type in mod.memories {
    let min_pages = mem_type.limits.min.to_int()
    let mem = @runtime.Memory::new(
      min_pages,
      mem_type.limits.max.map(fn(m) { m.to_int() }),
      is_memory64=mem_type.is_memory64,
      page_size_log2=mem_type.page_size_log2,
    )
    let addr = store.alloc_mem(mem)
    mem_addrs.push(addr)
  }

  // Set WASI memory address for interpreter mode WASI callbacks
  // This allows WASI functions to access the correct memory instead of hardcoded index 0
  if mem_addrs.length() > 0 {
    store.set_wasi_mem_addr(mem_addrs[0])
  }

  // First, collect instances for already-allocated globals (imports)
  // This is needed for table init expressions that reference imported globals
  let global_instances : Array[@runtime.GlobalInstance] = []
  for addr in global_addrs {
    global_instances.push(
      store.get_global(addr) catch {
        _ =>
          @runtime.GlobalInstance::new(
            { value_type: I32, mutable: false },
            I32(0),
          )
      },
    )
  }

  // Allocate tables (after imported tables and globals)
  // Table init expressions can reference imported globals
  for table_def in mod.tables {
    // Evaluate table init expression if present
    let init_value : @types.Value = match table_def.init {
      Some(init_expr) =>
        eval_const_expr(
          init_expr,
          func_addrs~,
          globals=global_instances,
          store=Some(store),
          types=mod.types,
        )
      None => @types.Value::Null
    }
    let min_elems = table_def.type_.limits.min.to_int()
    let table = @runtime.Table::new(
      table_def.type_.elem_type,
      min_elems,
      table_def.type_.limits.max.map(fn(m) { m.to_int() }),
      init_value~,
      is_table64=table_def.type_.is_table64,
    )
    let addr = store.alloc_table(table)
    table_addrs.push(addr)
  }

  // Allocate globals (after imported globals)
  for global in mod.globals {
    let init_value = eval_const_expr(
      global.init,
      func_addrs~,
      globals=global_instances,
      store=Some(store),
      types=mod.types,
    )
    let global_inst = @runtime.GlobalInstance::new(global.type_, init_value)
    let addr = store.alloc_global(global_inst)
    global_addrs.push(addr)
    global_instances.push(global_inst)
  }

  // Allocate tags (after imported tags)
  for tag in mod.tags {
    let tag_type = mod.get_func_type(tag.type_idx)
    let addr = store.alloc_tag(tag_type, type_idx=tag.type_idx)
    tag_addrs.push(addr)
  }

  // Initialize dropped arrays with false values
  let dropped_elems : Array[Bool] = []
  for _ in 0..<mod.elems.length() {
    dropped_elems.push(false)
  }
  let dropped_datas : Array[Bool] = []
  for _ in 0..<mod.datas.length() {
    dropped_datas.push(false)
  }

  // Per WebAssembly spec: element segments are initialized BEFORE data segments
  // This ensures that if data segment initialization traps, the element segment
  // modifications to shared tables are already visible.

  // Initialize active element segments (populate tables with function references)
  for elem_idx, elem in mod.elems {
    // Only process active element segments
    if elem.mode is @types.ElemMode::Active(table_idx, offset_expr) {
      if table_addrs.length() > table_idx {
        let table = store.get_table(table_addrs[table_idx])
        // Evaluate offset expression using extended const expr evaluator
        let globals = get_global_instances(store, global_addrs)
        let offset = eval_extended_const_expr(offset_expr, globals)

        // Check bounds before initializing
        // offset + num_elements must not exceed table size
        if offset < 0 || offset + elem.init.length() > table.size() {
          raise @runtime.OutOfBoundsTableAccess
        }

        // Set table entries - evaluate init expression to get value
        for i, init_expr in elem.init {
          match eval_elem_init_expr(init_expr, func_addrs, globals) {
            Some(value) => table.set(offset + i, value)
            None => continue
          }
        }
      }
      // Active elem segments are implicitly dropped after initialization
      dropped_elems[elem_idx] = true
    }
  }

  // Initialize active data segments (copy data to memory)
  let globals_for_data_init = get_global_instances(store, global_addrs)
  for data in mod.datas {
    // Active data segments have a non-empty offset expression
    if data.offset.length() > 0 && mem_addrs.length() > data.memory_idx {
      let mem = store.get_mem(mem_addrs[data.memory_idx])
      // Evaluate offset expression using extended const expr evaluator
      let offset = eval_extended_const_expr(data.offset, globals_for_data_init)
      // Copy data to memory
      mem.init_data(offset, data.init)
    }
  }
  // canonical_type_indices was computed at the start of the function (for import type checking)
  let instance : @runtime.ModuleInstance = {
    types: mod.types,
    type_rec_groups: mod.type_rec_groups,
    canonical_type_indices,
    store_idx: -1,
    func_addrs,
    func_type_indices,
    table_addrs,
    mem_addrs,
    global_addrs,
    tag_addrs,
    exports: mod.exports,
    elem_segments: mod.elems,
    data_segments: mod.datas,
    dropped_elems,
    dropped_datas,
  }

  // Register instance with store for cross-module call resolution
  // This also sets the store_idx field
  store.register_instance(instance) |> ignore

  // Execute start function if present
  if mod.start is Some(start_func_idx) {
    let ctx = ExecContext::new(store, instance)
    (ctx.call_func(start_func_idx, []) catch {
      BranchWith(_, _) | Return => raise @runtime.Unreachable
      @runtime.StackUnderflow => raise @runtime.StackUnderflow
      @runtime.StackOverflow => raise @runtime.StackOverflow
      @runtime.TypeMismatch => raise @runtime.TypeMismatch
      @runtime.OutOfBoundsMemoryAccess => raise @runtime.OutOfBoundsMemoryAccess
      @runtime.OutOfBoundsTableAccess => raise @runtime.OutOfBoundsTableAccess
      @runtime.OutOfBoundsArrayAccess => raise @runtime.OutOfBoundsArrayAccess
      @runtime.UndefinedElement => raise @runtime.UndefinedElement
      @runtime.UninitializedElement => raise @runtime.UninitializedElement
      @runtime.IndirectCallTypeMismatch =>
        raise @runtime.IndirectCallTypeMismatch
      @runtime.DivisionByZero => raise @runtime.DivisionByZero
      @runtime.IntegerOverflow => raise @runtime.IntegerOverflow
      @runtime.InvalidConversion => raise @runtime.InvalidConversion
      @runtime.Unreachable => raise @runtime.Unreachable
      @runtime.CallStackExhausted => raise @runtime.CallStackExhausted
      @runtime.UnknownImport(_) as e => raise e
      @runtime.LinkError => raise @runtime.LinkError
      @runtime.LinkErrorDetail(_) as e => raise e
      @runtime.NullReference => raise @runtime.NullReference
      @runtime.UnalignedAtomic => raise @runtime.UnalignedAtomic
      _ => raise @runtime.Unreachable
    })
    |> ignore
  }
  instance
}

///|
/// Find and call an exported function
pub fn call_exported_func(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  name : String,
  args : Array[@types.Value],
) -> Array[@types.Value] raise @runtime.RuntimeError {
  // Find the export
  fn find_export(
    exports : Array[@types.Export],
    target : String,
  ) -> @types.Export? {
    loop 0 {
      idx =>
        if idx >= exports.length() {
          None
        } else {
          let exp = exports[idx]
          if exp.name == target {
            Some(exp)
          } else {
            continue idx + 1
          }
        }
    }
  }

  match find_export(instance.exports, name) {
    Some(exp) =>
      match exp.desc {
        Func(func_idx) => {
          let ctx = ExecContext::new(store, instance)
          // Catch any leaked ControlSignal and convert to RuntimeError
          ctx.call_func(func_idx, args) catch {
            BranchWith(_, _) | Return => raise @runtime.Unreachable
            @runtime.StackUnderflow => raise @runtime.StackUnderflow
            @runtime.StackOverflow => raise @runtime.StackOverflow
            @runtime.TypeMismatch => raise @runtime.TypeMismatch
            @runtime.OutOfBoundsMemoryAccess =>
              raise @runtime.OutOfBoundsMemoryAccess
            @runtime.OutOfBoundsTableAccess =>
              raise @runtime.OutOfBoundsTableAccess
            @runtime.OutOfBoundsArrayAccess =>
              raise @runtime.OutOfBoundsArrayAccess
            @runtime.UndefinedElement => raise @runtime.UndefinedElement
            @runtime.UninitializedElement => raise @runtime.UninitializedElement
            @runtime.IndirectCallTypeMismatch =>
              raise @runtime.IndirectCallTypeMismatch
            @runtime.DivisionByZero => raise @runtime.DivisionByZero
            @runtime.IntegerOverflow => raise @runtime.IntegerOverflow
            @runtime.InvalidConversion => raise @runtime.InvalidConversion
            @runtime.Unreachable => raise @runtime.Unreachable
            @runtime.CallStackExhausted => raise @runtime.CallStackExhausted
            @runtime.UnknownImport(_) as e => raise e
            @runtime.NullReference => raise @runtime.NullReference
            @runtime.UnalignedAtomic => raise @runtime.UnalignedAtomic
            _ => raise @runtime.Unreachable
          }
        } // Unknown error
        _ => raise @runtime.UndefinedElement
      }
    None => raise @runtime.UndefinedElement
  }
}

///|
/// Call a function by module function index
pub fn call_func_by_index(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  func_idx : Int,
  args : Array[@types.Value],
) -> Array[@types.Value] raise @runtime.RuntimeError {
  let ctx = ExecContext::new(store, instance)
  // Catch any leaked ControlSignal and convert to RuntimeError
  ctx.call_func(func_idx, args) catch {
    BranchWith(_, _) | Return => raise @runtime.Unreachable
    @runtime.StackUnderflow => raise @runtime.StackUnderflow
    @runtime.StackOverflow => raise @runtime.StackOverflow
    @runtime.TypeMismatch => raise @runtime.TypeMismatch
    @runtime.OutOfBoundsMemoryAccess => raise @runtime.OutOfBoundsMemoryAccess
    @runtime.OutOfBoundsTableAccess => raise @runtime.OutOfBoundsTableAccess
    @runtime.OutOfBoundsArrayAccess => raise @runtime.OutOfBoundsArrayAccess
    @runtime.UndefinedElement => raise @runtime.UndefinedElement
    @runtime.UninitializedElement => raise @runtime.UninitializedElement
    @runtime.IndirectCallTypeMismatch => raise @runtime.IndirectCallTypeMismatch
    @runtime.DivisionByZero => raise @runtime.DivisionByZero
    @runtime.IntegerOverflow => raise @runtime.IntegerOverflow
    @runtime.InvalidConversion => raise @runtime.InvalidConversion
    @runtime.Unreachable => raise @runtime.Unreachable
    @runtime.CallStackExhausted => raise @runtime.CallStackExhausted
    @runtime.UnknownImport(_) as e => raise e
    @runtime.NullReference => raise @runtime.NullReference
    @runtime.UnalignedAtomic => raise @runtime.UnalignedAtomic
    _ => raise @runtime.Unreachable
  }
}

///|
/// Get the value of an exported global variable
pub fn get_exported_global(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  name : String,
) -> @types.Value raise @runtime.RuntimeError {
  // Find the export
  fn find_export(
    exports : Array[@types.Export],
    target : String,
  ) -> @types.Export? {
    loop 0 {
      idx =>
        if idx >= exports.length() {
          None
        } else {
          let exp = exports[idx]
          if exp.name == target {
            Some(exp)
          } else {
            continue idx + 1
          }
        }
    }
  }

  match find_export(instance.exports, name) {
    Some(exp) =>
      match exp.desc {
        Global(global_idx) => {
          let global_addr = instance.global_addrs[global_idx]
          let global = store.get_global(global_addr)
          global.get()
        }
        _ => raise @runtime.UndefinedElement
      }
    None => raise @runtime.UndefinedElement
  }
}

///|
/// Instantiate a module using a Linker
/// The linker provides imports from previously registered modules
/// The instantiated module is automatically registered with the given name
pub fn instantiate_with_linker(
  linker : @runtime.Linker,
  name : String,
  mod : @types.Module,
) -> @runtime.ModuleInstance raise @runtime.RuntimeError {
  let imports = linker.build_imports()
  let store = linker.get_store()
  let instance = instantiate_module_with_imports(store, mod, imports)

  // Register the instance with the store for cross-module call resolution
  store.register_instance(instance) |> ignore

  // Initialize data segments (copy data to memory)
  let globals_for_linker_data = get_global_instances(
    store,
    instance.global_addrs,
  )
  for data in mod.datas {
    if instance.mem_addrs.length() > data.memory_idx {
      let mem = store.get_mem(instance.mem_addrs[data.memory_idx])
      let offset = eval_extended_const_expr(
        data.offset,
        globals_for_linker_data,
      )
      mem.init_data(offset, data.init)
    }
  }

  // Initialize element segments (populate tables with function references)
  for elem_idx, elem in mod.elems {
    // Only process active element segments
    if elem.mode is @types.ElemMode::Active(table_idx, offset_expr) {
      if instance.table_addrs.length() > table_idx {
        let table = store.get_table(instance.table_addrs[table_idx])
        // Evaluate offset expression using extended const expr evaluator
        let globals = get_global_instances(store, instance.global_addrs)
        let offset = eval_extended_const_expr(offset_expr, globals)

        // Check bounds before initializing
        // offset + num_elements must not exceed table size
        if offset < 0 || offset + elem.init.length() > table.size() {
          raise @runtime.OutOfBoundsTableAccess
        }

        // Set table entries - evaluate init expression to get value
        for i, init_expr in elem.init {
          match eval_elem_init_expr(init_expr, instance.func_addrs, globals) {
            Some(value) => table.set(offset + i, value)
            None => continue
          }
        }
      }
      // Active elem segments are implicitly dropped after initialization
      instance.dropped_elems[elem_idx] = true
    }
  }

  // Execute start function if present
  if mod.start is Some(start_func_idx) {
    let ctx = ExecContext::new(store, instance)
    (ctx.call_func(start_func_idx, []) catch {
      BranchWith(_, _) | Return => raise @runtime.Unreachable
      @runtime.StackUnderflow => raise @runtime.StackUnderflow
      @runtime.StackOverflow => raise @runtime.StackOverflow
      @runtime.TypeMismatch => raise @runtime.TypeMismatch
      @runtime.OutOfBoundsMemoryAccess => raise @runtime.OutOfBoundsMemoryAccess
      @runtime.OutOfBoundsTableAccess => raise @runtime.OutOfBoundsTableAccess
      @runtime.OutOfBoundsArrayAccess => raise @runtime.OutOfBoundsArrayAccess
      @runtime.UndefinedElement => raise @runtime.UndefinedElement
      @runtime.UninitializedElement => raise @runtime.UninitializedElement
      @runtime.IndirectCallTypeMismatch =>
        raise @runtime.IndirectCallTypeMismatch
      @runtime.DivisionByZero => raise @runtime.DivisionByZero
      @runtime.IntegerOverflow => raise @runtime.IntegerOverflow
      @runtime.InvalidConversion => raise @runtime.InvalidConversion
      @runtime.Unreachable => raise @runtime.Unreachable
      @runtime.CallStackExhausted => raise @runtime.CallStackExhausted
      @runtime.UnknownImport(_) as e => raise e
      @runtime.NullReference => raise @runtime.NullReference
      @runtime.UnalignedAtomic => raise @runtime.UnalignedAtomic
      _ => raise @runtime.Unreachable
    })
    |> ignore
  }
  linker.register(name, instance)
  instance
}
