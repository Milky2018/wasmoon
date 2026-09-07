///|
/// Resolve an abstract binary heap type while preserving explicit nullability.
/// Nonnegative indices refer to concrete module types and are resolved separately.
pub fn ValueType::from_abstract_heap_type(
  heap_type : Int,
  nullable : Bool,
) -> ValueType? {
  Some(
    match heap_type {
      -16 => if nullable { FuncRef } else { RefFunc }
      -17 => if nullable { ExternRef } else { RefExtern }
      -18 => if nullable { AnyRef } else { RefAny }
      -19 => if nullable { RefNullEq } else { RefEq }
      -20 => if nullable { RefNullI31 } else { RefI31 }
      -21 => if nullable { StructRef } else { RefStructAbs }
      -22 => if nullable { ArrayRef } else { RefArrayAbs }
      -23 => ExnRef
      -15 => if nullable { NullRef } else { RefNone }
      -14 => NullExternRef
      -13 => NullFuncRef
      -12 => NullExnRef
      _ => return None
    },
  )
}
