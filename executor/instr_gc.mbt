///|
/// GC Instruction Implementations

// ============================================================
// Struct Operations
// ============================================================

///|
/// struct.new: Create a new struct with values from the stack
fn ExecContext::exec_struct_new(
  self : ExecContext,
  type_idx : Int,
) -> Unit raise {
  let struct_type = self.instance.get_struct_type(type_idx)
  let num_fields = struct_type.fields.length()

  // Pop field values from stack (in reverse order)
  let fields : Array[@types.Value] = Array::make(
    num_fields,
    @types.Value::I32(0),
  )
  for i = num_fields - 1; i >= 0; i = i - 1 {
    fields[i] = self.stack.pop()
  }

  // Allocate struct in the store
  let ref_idx = self.store.alloc_struct(type_idx, fields)
  self.stack.push(@types.Value::StructRef(ref_idx))
}

///|
/// struct.new_default: Create a new struct with default values
fn ExecContext::exec_struct_new_default(
  self : ExecContext,
  type_idx : Int,
) -> Unit raise {
  let struct_type = self.instance.get_struct_type(type_idx)
  let num_fields = struct_type.fields.length()

  // Create fields with default values
  let fields : Array[@types.Value] = []
  for i in 0..<num_fields {
    fields.push(
      default_value_for_storage_type(struct_type.fields[i].storage_type),
    )
  }

  // Allocate struct in the store
  let ref_idx = self.store.alloc_struct(type_idx, fields)
  self.stack.push(@types.Value::StructRef(ref_idx))
}

///|
/// struct.get: Get a field value from a struct
fn ExecContext::exec_struct_get(
  self : ExecContext,
  _type_idx : Int,
  field_idx : Int,
) -> Unit raise {
  let ref_val = self.stack.pop()
  match ref_val {
    StructRef(ref_idx) => {
      let value = self.store.struct_get(ref_idx, field_idx)
      self.stack.push(value)
    }
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

///|
/// struct.get_s: Get a signed packed field value from a struct
fn ExecContext::exec_struct_get_s(
  self : ExecContext,
  type_idx : Int,
  field_idx : Int,
) -> Unit raise {
  let ref_val = self.stack.pop()
  match ref_val {
    StructRef(ref_idx) => {
      let value = self.store.struct_get(ref_idx, field_idx)
      // Get the field's storage type to check if it's packed
      let struct_type = self.instance.get_struct_type(type_idx)
      let storage_type = struct_type.fields[field_idx].storage_type
      // Sign-extend packed types
      let extended_value = match (value, storage_type) {
        (I32(n), Packed(I8)) => {
          // Sign-extend 8-bit value
          let signed = if (n & 0x80) != 0 { n | 0xFFFFFF00 } else { n & 0xFF }
          @types.Value::I32(signed)
        }
        (I32(n), Packed(I16)) => {
          // Sign-extend 16-bit value
          let signed = if (n & 0x8000) != 0 {
            n | 0xFFFF0000
          } else {
            n & 0xFFFF
          }
          @types.Value::I32(signed)
        }
        _ => value
      }
      self.stack.push(extended_value)
    }
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

///|
/// struct.get_u: Get an unsigned packed field value from a struct
fn ExecContext::exec_struct_get_u(
  self : ExecContext,
  type_idx : Int,
  field_idx : Int,
) -> Unit raise {
  let ref_val = self.stack.pop()
  match ref_val {
    StructRef(ref_idx) => {
      let value = self.store.struct_get(ref_idx, field_idx)
      // Get the field's storage type to check if it's packed
      let struct_type = self.instance.get_struct_type(type_idx)
      let storage_type = struct_type.fields[field_idx].storage_type
      // Zero-extend packed types (mask off high bits)
      let extended_value = match (value, storage_type) {
        (I32(n), Packed(I8)) => @types.Value::I32(n & 0xFF)
        (I32(n), Packed(I16)) => @types.Value::I32(n & 0xFFFF)
        _ => value
      }
      self.stack.push(extended_value)
    }
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

///|
/// struct.set: Set a field value in a struct
fn ExecContext::exec_struct_set(
  self : ExecContext,
  type_idx : Int,
  field_idx : Int,
) -> Unit raise {
  let value = self.stack.pop()
  let ref_val = self.stack.pop()
  match ref_val {
    StructRef(ref_idx) => {
      // Get the field's storage type to check if it's packed
      let struct_type = self.instance.get_struct_type(type_idx)
      let storage_type = struct_type.fields[field_idx].storage_type
      // Mask packed types to their bit width
      let masked_value = match (value, storage_type) {
        (I32(n), Packed(I8)) => @types.Value::I32(n & 0xFF)
        (I32(n), Packed(I16)) => @types.Value::I32(n & 0xFFFF)
        _ => value
      }
      self.store.struct_set(ref_idx, field_idx, masked_value)
    }
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

// ============================================================
// Array Operations
// ============================================================

///|
/// array.new: Create a new array with a fill value and length
fn ExecContext::exec_array_new(
  self : ExecContext,
  type_idx : Int,
) -> Unit raise {
  let len_val = self.stack.pop()
  let fill_val = self.stack.pop()
  let len = match len_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }

  // Create array with fill value
  let elements : Array[@types.Value] = Array::make(len, fill_val)

  // Allocate array in the store
  let ref_idx = self.store.alloc_array(type_idx, elements)
  self.stack.push(@types.Value::ArrayRef(ref_idx))
}

///|
/// array.new_default: Create a new array with default values
fn ExecContext::exec_array_new_default(
  self : ExecContext,
  type_idx : Int,
) -> Unit raise {
  let len_val = self.stack.pop()
  let len = match len_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let array_type = self.instance.get_array_type(type_idx)
  let default_val = default_value_for_storage_type(
    array_type.element.storage_type,
  )

  // Create array with default values
  let elements : Array[@types.Value] = Array::make(len, default_val)

  // Allocate array in the store
  let ref_idx = self.store.alloc_array(type_idx, elements)
  self.stack.push(@types.Value::ArrayRef(ref_idx))
}

///|
/// array.new_fixed: Create a new array with fixed number of elements from stack
fn ExecContext::exec_array_new_fixed(
  self : ExecContext,
  type_idx : Int,
  len : Int,
) -> Unit raise {
  // Pop elements from stack (in reverse order)
  let elements : Array[@types.Value] = Array::make(len, @types.Value::I32(0))
  for i = len - 1; i >= 0; i = i - 1 {
    elements[i] = self.stack.pop()
  }

  // Allocate array in the store
  let ref_idx = self.store.alloc_array(type_idx, elements)
  self.stack.push(@types.Value::ArrayRef(ref_idx))
}

///|
/// array.get: Get an element from an array
fn ExecContext::exec_array_get(
  self : ExecContext,
  _type_idx : Int,
) -> Unit raise {
  let idx_val = self.stack.pop()
  let ref_val = self.stack.pop()
  let idx = match idx_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  match ref_val {
    ArrayRef(ref_idx) => {
      let value = self.store.array_get(ref_idx, idx)
      self.stack.push(value)
    }
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

///|
/// array.get_s: Get a signed packed element from an array
fn ExecContext::exec_array_get_s(
  self : ExecContext,
  type_idx : Int,
) -> Unit raise {
  let idx_val = self.stack.pop()
  let ref_val = self.stack.pop()
  let idx = match idx_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  match ref_val {
    ArrayRef(ref_idx) => {
      let value = self.store.array_get(ref_idx, idx)
      // Sign-extend the value based on the packed type
      let array_type = self.instance.get_array_type(type_idx)
      let extended = match array_type.element.storage_type {
        Packed(I8) =>
          // Sign-extend from 8 bits
          match value {
            I32(n) => {
              let byte_val = n & 0xff
              if (byte_val & 0x80) != 0 {
                // Negative: extend with 1s
                @types.Value::I32(byte_val | -256) // 0xFFFFFF00
              } else {
                @types.Value::I32(byte_val)
              }
            }
            _ => value
          }
        Packed(I16) =>
          // Sign-extend from 16 bits
          match value {
            I32(n) => {
              let short_val = n & 0xffff
              if (short_val & 0x8000) != 0 {
                // Negative: extend with 1s
                @types.Value::I32(short_val | -65536) // 0xFFFF0000
              } else {
                @types.Value::I32(short_val)
              }
            }
            _ => value
          }
        _ => value // Non-packed types don't need extension
      }
      self.stack.push(extended)
    }
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

///|
/// array.get_u: Get an unsigned packed element from an array
fn ExecContext::exec_array_get_u(
  self : ExecContext,
  type_idx : Int,
) -> Unit raise {
  let idx_val = self.stack.pop()
  let ref_val = self.stack.pop()
  let idx = match idx_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  match ref_val {
    ArrayRef(ref_idx) => {
      let value = self.store.array_get(ref_idx, idx)
      // Zero-extend the value based on the packed type
      let array_type = self.instance.get_array_type(type_idx)
      let extended = match array_type.element.storage_type {
        Packed(I8) =>
          // Zero-extend from 8 bits (just mask, no sign extension)
          match value {
            I32(n) => @types.Value::I32(n & 0xff)
            _ => value
          }
        Packed(I16) =>
          // Zero-extend from 16 bits (just mask, no sign extension)
          match value {
            I32(n) => @types.Value::I32(n & 0xffff)
            _ => value
          }
        _ => value // Non-packed types don't need extension
      }
      self.stack.push(extended)
    }
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

///|
/// array.set: Set an element in an array
fn ExecContext::exec_array_set(
  self : ExecContext,
  _type_idx : Int,
) -> Unit raise {
  let value = self.stack.pop()
  let idx_val = self.stack.pop()
  let ref_val = self.stack.pop()
  let idx = match idx_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  match ref_val {
    ArrayRef(ref_idx) => self.store.array_set(ref_idx, idx, value)
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

///|
/// array.len: Get the length of an array
fn ExecContext::exec_array_len(self : ExecContext) -> Unit raise {
  let ref_val = self.stack.pop()
  match ref_val {
    ArrayRef(ref_idx) => {
      let len = self.store.array_len(ref_idx)
      self.stack.push(@types.Value::I32(len))
    }
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

///|
/// array.fill: Fill array elements with a value
fn ExecContext::exec_array_fill(
  self : ExecContext,
  _type_idx : Int,
) -> Unit raise {
  let count_val = self.stack.pop()
  let value = self.stack.pop()
  let offset_val = self.stack.pop()
  let ref_val = self.stack.pop()
  let count = match count_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let offset = match offset_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  match ref_val {
    ArrayRef(ref_idx) => self.store.array_fill(ref_idx, offset, value, count)
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

///|
/// array.copy: Copy elements between arrays
fn ExecContext::exec_array_copy(
  self : ExecContext,
  _dst_type_idx : Int,
  _src_type_idx : Int,
) -> Unit raise {
  let count_val = self.stack.pop()
  let src_offset_val = self.stack.pop()
  let src_ref = self.stack.pop()
  let dst_offset_val = self.stack.pop()
  let dst_ref = self.stack.pop()
  let count = match count_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let src_offset = match src_offset_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let dst_offset = match dst_offset_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let dst_idx = match dst_ref {
    ArrayRef(idx) => idx
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let src_idx = match src_ref {
    ArrayRef(idx) => idx
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  self.store.array_copy(dst_idx, dst_offset, src_idx, src_offset, count)
}

///|
/// array.new_data: Create a new array from data segment bytes
fn ExecContext::exec_array_new_data(
  self : ExecContext,
  type_idx : Int,
  data_idx : Int,
) -> Unit raise {
  let len_val = self.stack.pop()
  let offset_val = self.stack.pop()
  let len = match len_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let offset = match offset_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }

  // Check if data segment has been dropped
  if self.instance.dropped_datas[data_idx] {
    if len != 0 {
      raise @runtime.RuntimeError::OutOfBoundsMemoryAccess
    }
    // Create empty array
    let ref_idx = self.store.alloc_array(type_idx, [])
    self.stack.push(@types.Value::ArrayRef(ref_idx))
    return
  }
  let data_segment = self.instance.data_segments[data_idx]
  let array_type = self.instance.get_array_type(type_idx)

  // Calculate bytes per element based on storage type
  let bytes_per_elem = storage_type_byte_size(array_type.element.storage_type)

  // Check bounds
  let total_bytes = len * bytes_per_elem
  if offset < 0 || len < 0 || offset + total_bytes > data_segment.init.length() {
    raise @runtime.RuntimeError::OutOfBoundsMemoryAccess
  }

  // Read elements from data segment
  let elements : Array[@types.Value] = []
  for i in 0..<len {
    let byte_offset = offset + i * bytes_per_elem
    let value = read_value_from_bytes(
      data_segment.init,
      byte_offset,
      array_type.element.storage_type,
    )
    elements.push(value)
  }

  // Allocate array in the store
  let ref_idx = self.store.alloc_array(type_idx, elements)
  self.stack.push(@types.Value::ArrayRef(ref_idx))
}

///|
/// array.new_elem: Create a new array from element segment
fn ExecContext::exec_array_new_elem(
  self : ExecContext,
  type_idx : Int,
  elem_idx : Int,
) -> Unit raise {
  let len_val = self.stack.pop()
  let offset_val = self.stack.pop()
  let len = match len_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let offset = match offset_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }

  // Check if elem segment has been dropped or is declarative
  let elem_segment = self.instance.elem_segments[elem_idx]
  let is_dropped = self.instance.dropped_elems[elem_idx]
  let is_declarative = elem_segment.mode is @types.ElemMode::Declarative
  if (is_dropped || is_declarative) && len != 0 {
    raise @runtime.RuntimeError::OutOfBoundsTableAccess
  }
  if is_dropped || is_declarative {
    let ref_idx = self.store.alloc_array(type_idx, [])
    self.stack.push(@types.Value::ArrayRef(ref_idx))
    return
  }

  // Check bounds
  let elem_len = elem_segment.init.length()
  if offset < 0 || len < 0 || offset + len > elem_len {
    raise @runtime.RuntimeError::OutOfBoundsTableAccess
  }

  // Read elements from elem segment
  let elements : Array[@types.Value] = []
  for i in 0..<len {
    let init_expr = elem_segment.init[offset + i]
    let value = self.eval_elem_init_expr(init_expr)
    elements.push(value)
  }

  // Allocate array in the store
  let ref_idx = self.store.alloc_array(type_idx, elements)
  self.stack.push(@types.Value::ArrayRef(ref_idx))
}

///|
/// array.init_data: Initialize array elements from data segment
fn ExecContext::exec_array_init_data(
  self : ExecContext,
  type_idx : Int,
  data_idx : Int,
) -> Unit raise {
  let len_val = self.stack.pop()
  let src_offset_val = self.stack.pop()
  let dst_offset_val = self.stack.pop()
  let arr_ref = self.stack.pop()
  let len = match len_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let src_offset = match src_offset_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let dst_offset = match dst_offset_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let arr_idx = match arr_ref {
    ArrayRef(idx) => idx
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }

  // Check if data segment has been dropped
  if self.instance.dropped_datas[data_idx] {
    if len != 0 {
      raise @runtime.RuntimeError::OutOfBoundsMemoryAccess
    }
    return
  }
  let data_segment = self.instance.data_segments[data_idx]
  let array_type = self.instance.get_array_type(type_idx)
  let bytes_per_elem = storage_type_byte_size(array_type.element.storage_type)

  // Check bounds
  let total_bytes = len * bytes_per_elem
  if src_offset < 0 ||
    len < 0 ||
    src_offset + total_bytes > data_segment.init.length() {
    raise @runtime.RuntimeError::OutOfBoundsMemoryAccess
  }
  let arr_len = self.store.array_len(arr_idx)
  if dst_offset < 0 || dst_offset + len > arr_len {
    raise @runtime.RuntimeError::OutOfBoundsMemoryAccess
  }

  // Copy bytes from data segment to array
  for i in 0..<len {
    let byte_offset = src_offset + i * bytes_per_elem
    let value = read_value_from_bytes(
      data_segment.init,
      byte_offset,
      array_type.element.storage_type,
    )
    self.store.array_set(arr_idx, dst_offset + i, value)
  }
}

///|
/// array.init_elem: Initialize array elements from element segment
fn ExecContext::exec_array_init_elem(
  self : ExecContext,
  _type_idx : Int,
  elem_idx : Int,
) -> Unit raise {
  let len_val = self.stack.pop()
  let src_offset_val = self.stack.pop()
  let dst_offset_val = self.stack.pop()
  let arr_ref = self.stack.pop()
  let len = match len_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let src_offset = match src_offset_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let dst_offset = match dst_offset_val {
    I32(n) => n
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
  let arr_idx = match arr_ref {
    ArrayRef(idx) => idx
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }

  // Check if elem segment has been dropped or is declarative
  let elem_segment = self.instance.elem_segments[elem_idx]
  let is_dropped = self.instance.dropped_elems[elem_idx]
  let is_declarative = elem_segment.mode is @types.ElemMode::Declarative
  if (is_dropped || is_declarative) && len != 0 {
    raise @runtime.RuntimeError::OutOfBoundsTableAccess
  }
  if is_dropped || is_declarative {
    return
  }

  // Check bounds
  let elem_len = elem_segment.init.length()
  if src_offset < 0 || len < 0 || src_offset + len > elem_len {
    raise @runtime.RuntimeError::OutOfBoundsTableAccess
  }
  let arr_len = self.store.array_len(arr_idx)
  if dst_offset < 0 || dst_offset + len > arr_len {
    raise @runtime.RuntimeError::OutOfBoundsTableAccess
  }

  // Copy elements from elem segment to array
  for i in 0..<len {
    let init_expr = elem_segment.init[src_offset + i]
    let value = self.eval_elem_init_expr(init_expr)
    self.store.array_set(arr_idx, dst_offset + i, value)
  }
}

///|
/// Helper: Get byte size for a storage type
fn storage_type_byte_size(st : @types.StorageType) -> Int {
  match st {
    Val(vt) =>
      match vt {
        I32 | F32 => 4
        I64 | F64 => 8
        _ => 4 // Default to 4 for reference types
      }
    Packed(pt) =>
      match pt {
        I8 => 1
        I16 => 2
      }
  }
}

///|
/// Helper: Read a value from bytes based on storage type
fn read_value_from_bytes(
  bytes : Bytes,
  offset : Int,
  st : @types.StorageType,
) -> @types.Value {
  match st {
    Packed(I8) => {
      let b = bytes[offset].to_int()
      @types.Value::I32(b)
    }
    Packed(I16) => {
      let b0 = bytes[offset].to_int()
      let b1 = bytes[offset + 1].to_int()
      let val = b0 | (b1 << 8)
      @types.Value::I32(val)
    }
    Val(I32) => {
      let b0 = bytes[offset].to_int()
      let b1 = bytes[offset + 1].to_int()
      let b2 = bytes[offset + 2].to_int()
      let b3 = bytes[offset + 3].to_int()
      let val = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
      @types.Value::I32(val)
    }
    Val(I64) => {
      let mut val = 0L
      for i in 0..<8 {
        val = val | (bytes[offset + i].to_int().to_int64() << (i * 8))
      }
      @types.Value::I64(val)
    }
    Val(F32) => {
      let b0 = bytes[offset].to_int()
      let b1 = bytes[offset + 1].to_int()
      let b2 = bytes[offset + 2].to_int()
      let b3 = bytes[offset + 3].to_int()
      let bits = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
      @types.Value::F32(Float::reinterpret_from_int(bits))
    }
    Val(F64) => {
      let mut bits = 0L
      for i in 0..<8 {
        bits = bits | (bytes[offset + i].to_int().to_int64() << (i * 8))
      }
      @types.Value::F64(bits.reinterpret_as_double())
    }
    Val(_) =>
      // Reference types are not valid for data segments
      @types.Value::Null
  }
}

///|
/// Helper: Evaluate an element init expression to get a value
/// For complex expressions (like array.new), execute them through the interpreter
fn ExecContext::eval_elem_init_expr(
  self : ExecContext,
  init_expr : Array[@types.Instruction],
) -> @types.Value raise {
  match init_expr {
    [RefFunc(func_idx)] => {
      let store_addr = self.instance.func_addrs[func_idx]
      @types.Value::FuncRef(store_addr)
    }
    [RefNull(_)] => @types.Value::Null
    [I32Const(idx)] => {
      // Legacy format: function index as i32
      let store_addr = self.instance.func_addrs[idx]
      @types.Value::FuncRef(store_addr)
    }
    _ => {
      // For complex expressions, execute them through the interpreter
      // Save the current stack state
      let saved_stack_len = self.stack.size()
      // Execute all instructions
      for instr in init_expr {
        self.exec_instr(instr)
      }
      // Pop the result
      if self.stack.size() > saved_stack_len {
        self.stack.pop()
      } else {
        @types.Value::Null
      }
    }
  }
}

// ============================================================
// i31 Operations
// ============================================================

///|
/// ref.i31: Create an i31ref from an i32
fn ExecContext::exec_ref_i31(self : ExecContext) -> Unit raise {
  let val = self.stack.pop()
  match val {
    I32(n) => {
      // i31 stores only the lower 31 bits
      let i31_val = n & 0x7FFFFFFF
      self.stack.push(@types.Value::I31(i31_val))
    }
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

///|
/// i31.get_s: Get signed i32 from i31ref
fn ExecContext::exec_i31_get_s(self : ExecContext) -> Unit raise {
  let val = self.stack.pop()
  match val {
    I31(n) => {
      // Sign extend from 31 bits to 32 bits
      // If bit 30 is set, we need to set bit 31 (sign bit)
      // -2147483648 = 0x80000000 as signed int
      let extended = if (n & 0x40000000) != 0 { n | -2147483648 } else { n }
      self.stack.push(@types.Value::I32(extended))
    }
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

///|
/// i31.get_u: Get unsigned i32 from i31ref
fn ExecContext::exec_i31_get_u(self : ExecContext) -> Unit raise {
  let val = self.stack.pop()
  match val {
    I31(n) => self.stack.push(@types.Value::I32(n))
    Null => raise @runtime.RuntimeError::NullReference
    _ => raise @runtime.RuntimeError::TypeMismatch
  }
}

// ============================================================
// Type Conversion Operations
// ============================================================

///|
/// any.convert_extern: Convert externref to anyref
fn ExecContext::exec_any_convert_extern(self : ExecContext) -> Unit raise {
  // Unwrap externref back to its internal representation
  let val = self.stack.pop()
  match val {
    Null => self.stack.push(@types.Value::Null)
    ExternRef(_) => {
      // Unwrap: host externrefs stay as ExternRef, wrapped internals get unwrapped
      let unwrapped = self.store.unwrap_extern(val)
      self.stack.push(unwrapped)
    }
    _ => self.stack.push(val) // Pass through other values
  }
}

///|
/// extern.convert_any: Convert anyref to externref
fn ExecContext::exec_extern_convert_any(self : ExecContext) -> Unit raise {
  // Wrap internal values as externref
  let val = self.stack.pop()
  match val {
    Null => self.stack.push(@types.Value::Null)
    ExternRef(_) =>
      // Already an externref, pass through
      self.stack.push(val)
    I31(_) | StructRef(_) | ArrayRef(_) => {
      // Wrap internal GC values as externref
      let wrapped = self.store.wrap_as_extern(val)
      self.stack.push(wrapped)
    }
    _ => self.stack.push(val) // Pass through other values
  }
}

// ============================================================
// Reference Casting Operations
// ============================================================

///|
/// Check if a runtime value matches a type
fn value_matches_type(
  value : @types.Value,
  target_type : @types.ValueType,
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
) -> Bool {
  match (value, target_type) {
    // Null matches nullable types
    (Null, FuncRef) => true
    (Null, ExternRef) => true
    (Null, AnyRef) => true
    (Null, RefNullEq) => true
    (Null, RefNullI31) => true
    (Null, RefNullStruct(_)) => true
    (Null, RefNullArray(_)) => true
    (Null, RefNullFuncTyped(_)) => true
    (Null, NullRef) => true
    (Null, NullFuncRef) => true
    (Null, NullExternRef) => true
    (Null, _) => false

    // i31ref matches i31 and eq types
    (I31(_), @types.ValueType::RefI31) => true
    (I31(_), RefNullI31) => true
    (I31(_), RefEq) => true
    (I31(_), RefNullEq) => true
    (I31(_), AnyRef) => true
    (I31(_), RefAny) => true

    // StructRef matches struct, eq, and any types
    (StructRef(idx), RefStruct(type_idx)) =>
      // type_idx == -1 means abstract struct type (any struct)
      if type_idx == -1 {
        true
      } else {
        // Check if runtime type matches expected type
        let result = try? store.get_gc_type_idx(idx)
        match result {
          Ok(runtime_type_idx) =>
            is_subtype(runtime_type_idx, type_idx, instance)
          Err(_) => false
        }
      }
    (StructRef(idx), RefNullStruct(type_idx)) =>
      // type_idx == -1 means abstract struct type (any struct)
      if type_idx == -1 {
        true
      } else {
        let result = try? store.get_gc_type_idx(idx)
        match result {
          Ok(runtime_type_idx) =>
            is_subtype(runtime_type_idx, type_idx, instance)
          Err(_) => false
        }
      }
    (StructRef(_), RefEq) => true
    (StructRef(_), RefNullEq) => true
    (StructRef(_), AnyRef) => true
    (StructRef(_), RefAny) => true

    // ArrayRef matches array, eq, and any types
    (ArrayRef(idx), RefArray(type_idx)) =>
      // type_idx == -1 means abstract array type (any array)
      if type_idx == -1 {
        true
      } else {
        let result = try? store.get_gc_type_idx(idx)
        match result {
          Ok(runtime_type_idx) =>
            is_subtype(runtime_type_idx, type_idx, instance)
          Err(_) => false
        }
      }
    (ArrayRef(idx), RefNullArray(type_idx)) =>
      // type_idx == -1 means abstract array type (any array)
      if type_idx == -1 {
        true
      } else {
        let result = try? store.get_gc_type_idx(idx)
        match result {
          Ok(runtime_type_idx) =>
            is_subtype(runtime_type_idx, type_idx, instance)
          Err(_) => false
        }
      }
    (ArrayRef(_), RefEq) => true
    (ArrayRef(_), RefNullEq) => true
    (ArrayRef(_), AnyRef) => true
    (ArrayRef(_), RefAny) => true

    // FuncRef matches func types
    (FuncRef(_), @types.ValueType::FuncRef) => true
    (FuncRef(_), RefFunc) => true // non-null abstract func type
    (FuncRef(func_addr), RefFuncTyped(type_idx)) => {
      // Check if function type matches
      let func_type_idx = store.get_func_type_idx(func_addr)
      is_subtype(func_type_idx, type_idx, instance)
    }
    (FuncRef(func_addr), RefNullFuncTyped(type_idx)) => {
      let func_type_idx = store.get_func_type_idx(func_addr)
      is_subtype(func_type_idx, type_idx, instance)
    }

    // ExternRef matches externref and anyref (when converted via any.convert_extern)
    (ExternRef(_), @types.ValueType::ExternRef) => true
    (ExternRef(_), RefExtern) => true
    // When externref is converted to anyref via any.convert_extern, it becomes anyref
    // and should match anyref types
    (ExternRef(_), AnyRef) => true
    (ExternRef(_), RefAny) => true

    // When anyref values are converted to externref via extern.convert_any,
    // they should match externref types. In our implementation, the underlying
    // value type is preserved, so we need to match them against externref.
    (I31(_), @types.ValueType::ExternRef) => true
    (I31(_), RefExtern) => true
    (StructRef(_), @types.ValueType::ExternRef) => true
    (StructRef(_), RefExtern) => true
    (ArrayRef(_), @types.ValueType::ExternRef) => true
    (ArrayRef(_), RefExtern) => true
    _ => false
  }
}

///|
/// Check if type1 is a subtype of type2.
/// Uses the unified SubtypingContext API for proper isorecursive type checking.
fn is_subtype(
  type_idx1 : Int,
  type_idx2 : Int,
  instance : @runtime.ModuleInstance,
) -> Bool {
  let ctx = @types.SubtypingContext::same_module(
    instance.types,
    rec_groups=instance.type_rec_groups,
    canonical=instance.canonical_type_indices,
  )
  ctx.is_subtype(type_idx1, type_idx2)
}

///|
/// ref.test: Test if a reference matches a type (non-null)
fn ExecContext::exec_ref_test(
  self : ExecContext,
  target_type : @types.ValueType,
) -> Unit raise {
  let val = self.stack.pop()
  // ref.test returns false for null
  if val is Null {
    self.stack.push(@types.Value::I32(0))
    return
  }
  let matches = value_matches_type(val, target_type, self.store, self.instance)
  self.stack.push(@types.Value::I32(if matches { 1 } else { 0 }))
}

///|
/// ref.test null: Test if a reference matches a nullable type
fn ExecContext::exec_ref_test_null(
  self : ExecContext,
  target_type : @types.ValueType,
) -> Unit raise {
  let val = self.stack.pop()
  // ref.test null returns true for null (since target is nullable)
  if val is Null {
    self.stack.push(@types.Value::I32(1))
    return
  }
  let matches = value_matches_type(val, target_type, self.store, self.instance)
  self.stack.push(@types.Value::I32(if matches { 1 } else { 0 }))
}

///|
/// ref.cast: Cast a reference to a type (non-null, traps on failure)
fn ExecContext::exec_ref_cast(
  self : ExecContext,
  target_type : @types.ValueType,
) -> Unit raise {
  let val = self.stack.pop()
  // ref.cast traps on null
  if val is Null {
    raise @runtime.RuntimeError::NullReference
  }
  let matches = value_matches_type(val, target_type, self.store, self.instance)
  if not(matches) {
    raise @runtime.RuntimeError::TypeMismatch
  }
  self.stack.push(val)
}

///|
/// ref.cast null: Cast a reference to a nullable type (traps on type mismatch)
fn ExecContext::exec_ref_cast_null(
  self : ExecContext,
  target_type : @types.ValueType,
) -> Unit raise {
  let val = self.stack.pop()
  // ref.cast null allows null
  if val is Null {
    self.stack.push(@types.Value::Null)
    return
  }
  let matches = value_matches_type(val, target_type, self.store, self.instance)
  if not(matches) {
    raise @runtime.RuntimeError::TypeMismatch
  }
  self.stack.push(val)
}

// ============================================================
// Branch on Cast Operations
// ============================================================

///|
/// br_on_cast: Branch if value matches target type
fn ExecContext::exec_br_on_cast(
  self : ExecContext,
  label_idx : Int,
  target_type : @types.ValueType,
) -> Unit raise {
  let val = self.stack.pop()
  // For null values, branch only if target type is nullable
  if val is Null {
    if target_type.is_nullable() {
      // Null matches nullable type, branch
      raise BranchWith(label_idx, [val])
    } else {
      // Null doesn't match non-null type, don't branch
      self.stack.push(val)
      return
    }
  }
  let matches = value_matches_type(val, target_type, self.store, self.instance)
  if matches {
    // Branch with the cast value
    raise BranchWith(label_idx, [val])
  } else {
    // Doesn't branch, push value back
    self.stack.push(val)
  }
}

///|
/// br_on_cast_fail: Branch if value does NOT match target type
fn ExecContext::exec_br_on_cast_fail(
  self : ExecContext,
  label_idx : Int,
  target_type : @types.ValueType,
) -> Unit raise {
  let val = self.stack.pop()
  // br_on_cast_fail branches if the cast fails
  // For null values, cast fails only if target type is non-null
  if val is Null {
    if target_type.is_nullable() {
      // Null matches nullable type, cast succeeds, don't branch
      self.stack.push(val)
      return
    } else {
      // Null doesn't match non-null type, cast fails, branch
      raise BranchWith(label_idx, [val])
    }
  }
  let matches = value_matches_type(val, target_type, self.store, self.instance)
  if not(matches) {
    // Cast failed, branch
    raise BranchWith(label_idx, [val])
  } else {
    // Cast succeeded, push value and continue
    self.stack.push(val)
  }
}

// ============================================================
// Helper Functions
// ============================================================

///|
/// Get the default value for a storage type
fn default_value_for_storage_type(
  storage_type : @types.StorageType,
) -> @types.Value {
  match storage_type {
    Val(I32) => @types.Value::I32(0)
    Val(I64) => @types.Value::I64(0L)
    Val(F32) => @types.Value::F32(0.0)
    Val(F64) => @types.Value::F64(0.0)
    Val(FuncRef) | Val(RefNullFuncTyped(_)) => @types.Value::Null
    Val(ExternRef) => @types.Value::Null
    Val(RefNullStruct(_)) => @types.Value::Null
    Val(RefNullArray(_)) => @types.Value::Null
    Val(RefNullI31) => @types.Value::Null
    Val(RefNullEq) => @types.Value::Null
    Val(RefAny) | Val(RefNone) => @types.Value::Null
    Packed(I8) | Packed(I16) => @types.Value::I32(0)
    _ => @types.Value::Null // Default for other reference types
  }
}
