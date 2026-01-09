///|
/// Shared helper functions for JIT execution
/// Used by both run_wasm (run.mbt) and run_cwasm (run_cwasm.mbt)

///|
/// Convert Value array to Int64 array for JIT function calls
fn convert_args_to_jit(args : Array[@types.Value]) -> Array[Int64] {
  let result : Array[Int64] = []
  for arg in args {
    let v = match arg {
      I32(n) => @types.ToInt64::to_int64_bits(n)
      I64(n) => @types.ToInt64::to_int64_bits(n)
      F32(n) => @types.ToInt64::to_int64_bits(n)
      F64(n) => @types.ToInt64::to_int64_bits(n)
      FuncRef(idx) => idx.to_int64()
      ExternRef(idx) => idx.to_int64()
      ExnRef(idx) => idx.to_int64()
      ArrayRef(idx) => idx.to_int64()
      StructRef(idx) => idx.to_int64()
      I31(n) => n.to_int64()
      Null => @types.FUNCREF_NULL_SENTINEL
      V128(_) => abort("V128 args not yet supported in JIT")
    }
    result.push(v)
  }
  result
}

///|
/// Convert a single JIT result (Int64) to Value based on its type
fn convert_jit_result(
  raw : Int64,
  value_type : @types.ValueType,
) -> @types.Value {
  match value_type {
    I32 => @types.Value::I32(@types.FromInt64::from_int64_bits(raw))
    I64 => @types.Value::I64(@types.FromInt64::from_int64_bits(raw))
    F32 => @types.Value::F32(@types.FromInt64::from_int64_bits(raw))
    F64 => @types.Value::F64(@types.FromInt64::from_int64_bits(raw))
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) | NullFuncRef =>
      if raw == @types.FUNCREF_NULL_SENTINEL {
        @types.Value::Null
      } else {
        @types.Value::FuncRef(raw.to_int())
      }
    ExternRef | RefExtern | NullExternRef =>
      if raw == @types.FUNCREF_NULL_SENTINEL {
        @types.Value::Null
      } else {
        @types.Value::ExternRef(raw.to_int())
      }
    // GC reference types - decode using JIT encoding:
    // null = 0, i31 = (value << 1) | 1, struct/array = gc_ref << 1
    AnyRef | NullRef | RefAny | RefEq | RefNullEq => decode_gc_value(raw)
    ExnRef | NullExnRef =>
      if raw == @types.FUNCREF_NULL_SENTINEL {
        @types.Value::Null
      } else {
        @types.Value::ExnRef(raw.to_int())
      }
    V128 => @types.Value::I64(raw) // Placeholder for V128
    // GC struct/array reference types
    RefStruct(_) | RefNullStruct(_) =>
      if raw == 0L {
        @types.Value::Null
      } else {
        @types.Value::StructRef((raw >> 1).to_int())
      }
    RefArray(_) | RefNullArray(_) =>
      if raw == 0L {
        @types.Value::Null
      } else {
        @types.Value::ArrayRef((raw >> 1).to_int())
      }
    RefI31 | RefNullI31 =>
      if raw == 0L {
        @types.Value::Null
      } else if (raw & 1L) == 1L {
        @types.Value::I31((raw >> 1).to_int())
      } else {
        @types.Value::Null
      }
    RefNone => @types.Value::Null
  }
}

///|
/// Convert Int64 results array to Value array based on result types
fn convert_jit_results(
  raw_results : Array[Int64],
  result_types : Array[@types.ValueType],
) -> Array[@types.Value] {
  let values : Array[@types.Value] = []
  for i, raw in raw_results {
    if i < result_types.length() {
      values.push(convert_jit_result(raw, result_types[i]))
    }
  }
  values
}

///|
/// Decode JIT GC reference value to @types.Value
/// JIT GC encoding: null=0, i31=(val<<1)|1, struct/array=gc_ref<<1
fn decode_gc_value(raw : Int64) -> @types.Value {
  if raw == 0L {
    @types.Value::Null
  } else if (raw & 1L) == 1L {
    // i31: (value << 1) | 1, decode by shifting right
    @types.Value::I31((raw >> 1).to_int())
  } else {
    // Heap reference: gc_ref << 1, decode by shifting right
    // Note: Could be struct or array, we use StructRef as default
    @types.Value::StructRef((raw >> 1).to_int())
  }
}

///|
/// Format a WASM value for display
fn format_value(v : @types.Value) -> String {
  match v {
    I32(n) => n.to_string()
    I64(n) => n.to_string()
    F32(n) => n.to_string()
    F64(n) => n.to_string()
    Null => "null"
    FuncRef(idx) => "funcref(\{idx})"
    ExternRef(idx) => "externref(\{idx})"
    ExnRef(idx) => "exnref(\{idx})"
    ArrayRef(idx) => "arrayref(\{idx})"
    StructRef(idx) => "structref(\{idx})"
    I31(n) => "i31(\{n})"
    V128(bytes) => {
      let hex_chars = "0123456789abcdef"
      let hex = StringBuilder::new()
      for i in 0..<bytes.length() {
        if i > 0 {
          hex.write_string(" ")
        }
        let b = bytes[i].to_int()
        hex.write_char(hex_chars.code_unit_at(b / 16).unsafe_to_char())
        hex.write_char(hex_chars.code_unit_at(b % 16).unsafe_to_char())
      }
      "v128(\{hex.to_string()})"
    }
  }
}

///|
/// Get basename from a file path
fn get_basename(path : String) -> String {
  let mut last_slash = -1
  for i in 0..<path.length() {
    if path.code_unit_at(i) == '/' {
      last_slash = i
    }
  }
  if last_slash >= 0 {
    let builder = StringBuilder::new()
    for i in (last_slash + 1)..<path.length() {
      builder.write_char(path.code_unit_at(i).unsafe_to_char())
    }
    builder.to_string()
  } else {
    path
  }
}
