///|
// These spelling aliases match the pinned Wasmtime WAST adapter. They
// preserve the trap category; unrelated trap messages must still fail.
pub fn wast_trap_message_matches(actual : String, expected : String) -> Bool {
  let actual = actual.split(" (sig=").next().unwrap_or("").to_owned()
  actual.contains(expected) ||
  (
    expected == "uninitialized element 2" &&
    actual.contains("uninitialized element")
  ) ||
  (
    expected.contains("null function") &&
    actual.contains("uninitialized element")
  ) ||
  (
    expected.contains("null") &&
    expected.contains("reference") &&
    actual.contains("null reference")
  )
}

///|
pub fn classify_runtime_failure(
  error : @runtime.RuntimeError,
) -> WastRunnerError {
  match error {
    UnsupportedHostCapability(detail) => UnsupportedCapability(detail)
    UncaughtException => GuestException
    UnhandledSuspension => GuestSuspension
    CallStackExhausted | StackOverflow => GuestExhaustion(error.to_string())
    OutOfBoundsMemoryAccess
    | OutOfBoundsTableAccess
    | OutOfBoundsArrayAccess
    | UndefinedElement
    | UninitializedElement
    | IndirectCallTypeMismatch
    | DivisionByZero
    | IntegerOverflow
    | InvalidConversion
    | Unreachable
    | CastFailure
    | NullReference
    | UnalignedAtomic
    | OutOfMemory
    | TableAllocationOverflow
    | TableAllocationFailed
    | MemoryMinimumExceedsLimits(_)
    | AllocationTooLarge
    | ContinuationAlreadyConsumed
    | AtomicWaitNonSharedMemory => GuestTrap(error.to_string())
    _ => RuntimeError(error.to_string())
  }
}

///|
/// Error types for WAST runner
pub(all) suberror WastRunnerError {
  UnsupportedCapability(String)
  ModuleNotFound(String)
  NoCurrentModule
  GuestTrap(String)
  GuestException
  GuestSuspension
  GuestExhaustion(String)
  RuntimeError(String)
}

///|
pub impl Show for WastRunnerError with fn output(self, logger) {
  match self {
    UnsupportedCapability(detail) =>
      logger.write_string("unsupported host capability: \{detail}")
    ModuleNotFound(name) => logger.write_string("module not found: \{name}")
    NoCurrentModule => logger.write_string("no current module")
    GuestTrap(msg) => logger.write_string("wasm trap: \{msg}")
    GuestException => logger.write_string("uncaught Wasm exception")
    GuestSuspension => logger.write_string("unhandled suspension")
    GuestExhaustion(msg) => logger.write_string("wasm exhaustion: \{msg}")
    RuntimeError(msg) => logger.write_string("runtime error: \{msg}")
  }
}

///|
pub fn wast_value_to_runtime(
  v : @wat.WastValue,
  func_addrs~ : ArrayView[Int32] = [],
) -> @types.Value raise WastRunnerError {
  match v {
    I32(n) => I32(n)
    I64(n) => I64(n)
    F32(n) => F32(n)
    F64(n) => F64(n)
    V128(bytes) => V128(bytes)
    F32CanonicalNan | F32ArithmeticNan => F32((0.0 : Float) / (0.0 : Float))
    F64CanonicalNan | F64ArithmeticNan => F64(0.0 / 0.0)
    V128Pattern(_) =>
      // For patterns, use a placeholder - actual matching is done in values_match
      V128(Bytes::make(16, b'\x00'))
    RefNull(_) => Null
    RefExtern(n) => ExternRef(n)
    RefHost(n) => ExternRef(n) // ref.host is like ref.extern for testing
    RefFuncIndex(idx) => {
      if idx < 0 || idx >= func_addrs.length() {
        raise RuntimeError("invalid ref.func argument index")
      }
      FuncRef(func_addrs[idx])
    }
    RefFunc => FuncRef(0) // Placeholder
    RefExternAny => ExternRef(0) // Placeholder for matching
    // GC reference types - these are abstract type matchers, not concrete values
    RefArray | RefStruct | RefEq | RefI31 | RefAny => Null // Placeholder
    // Either is for matching, not for conversion to runtime value
    Either(_) => abort("Either not valid as runtime value")
  }
}

///|
pub fn values_match(
  actual : @types.Value,
  expected : @wat.WastValue,
  func_addrs~ : ArrayView[Int32] = [],
) -> Bool {
  match (actual, expected) {
    (I32(a), I32(e)) => a == e
    (I64(a), I64(e)) => a == e
    (F32(a), F32(e)) => a.reinterpret_as_int() == e.reinterpret_as_int()
    (F64(a), F64(e)) => a.reinterpret_as_int64() == e.reinterpret_as_int64()
    (F32(a), F32CanonicalNan) =>
      (a.reinterpret_as_int() & 0x7fffffff) == 0x7fc00000
    (F32(a), F32ArithmeticNan) =>
      (a.reinterpret_as_int() & 0x7fc00000) == 0x7fc00000
    (F64(a), F64CanonicalNan) =>
      (a.reinterpret_as_int64() & 0x7fffffffffffffffL) == 0x7ff8000000000000L
    (F64(a), F64ArithmeticNan) =>
      (a.reinterpret_as_int64() & 0x7ff8000000000000L) == 0x7ff8000000000000L
    (Null, RefNull(_)) => true
    (FuncRef(_), RefFunc) => true
    (FuncRef(addr), RefFuncIndex(idx)) =>
      idx >= 0 && idx < func_addrs.length() && addr == func_addrs[idx]
    (ExternRef(a), RefExtern(e)) => a == e
    (ExternRef(_), RefExternAny) => true // any non-null externref
    (ExternRef(a), RefHost(e)) => a == e // ref.host is like ref.extern
    // GC reference type matching
    (ArrayRef(_), RefArray) => true
    (StructRef(_), RefStruct) => true
    // ref.eq matches i31, struct, and array references
    (I31(_), RefEq) => true
    (StructRef(_), RefEq) => true
    (ArrayRef(_), RefEq) => true
    // ref.i31 matches i31 references
    (I31(_), RefI31) => true
    // ref.any matches any GC reference
    (I31(_), RefAny) => true
    (StructRef(_), RefAny) => true
    (ArrayRef(_), RefAny) => true
    // V128 matching
    (V128(a), V128(e)) => bytes_equal(a, e)
    (V128(a), V128Pattern(lanes)) => v128_pattern_match(a, lanes)
    // Relaxed SIMD: Either matches if any alternative matches
    (_, Either(alternatives)) =>
      alternatives
      .iter()
      .any(fn(alt) { values_match(actual, alt, func_addrs~) })
    _ => false
  }
}

///|
fn bytes_equal(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
fn v128_pattern_match(
  actual : Bytes,
  lanes : Array[@wat.WastLaneValue],
) -> Bool {
  // Match lane by lane
  if lanes.length() == 4 {
    // f32x4 - 4 lanes
    for i in 0..<4 {
      let offset = i * 4
      let lane_bits = actual[offset].to_int() |
        (actual[offset + 1].to_int() << 8) |
        (actual[offset + 2].to_int() << 16) |
        (actual[offset + 3].to_int() << 24)
      match lanes[i] {
        F32(e) => if lane_bits != e.reinterpret_as_int() { return false }
        F32CanonicalNan =>
          if (lane_bits & 0x7fffffff) != 0x7fc00000 {
            return false
          }
        F32ArithmeticNan =>
          if (lane_bits & 0x7fc00000) != 0x7fc00000 {
            return false
          }
        _ => return false
      }
    }
    true
  } else if lanes.length() == 2 {
    // f64x2 - 2 lanes
    for i in 0..<2 {
      let offset = i * 8
      let lane_bits = actual[offset].to_int().to_int64() |
        (actual[offset + 1].to_int().to_int64() << 8) |
        (actual[offset + 2].to_int().to_int64() << 16) |
        (actual[offset + 3].to_int().to_int64() << 24) |
        (actual[offset + 4].to_int().to_int64() << 32) |
        (actual[offset + 5].to_int().to_int64() << 40) |
        (actual[offset + 6].to_int().to_int64() << 48) |
        (actual[offset + 7].to_int().to_int64() << 56)
      match lanes[i] {
        F64(e) => if lane_bits != e.reinterpret_as_int64() { return false }
        F64CanonicalNan =>
          if (lane_bits & 0x7fffffffffffffffL) != 0x7ff8000000000000L {
            return false
          }
        F64ArithmeticNan =>
          if (lane_bits & 0x7ff8000000000000L) != 0x7ff8000000000000L {
            return false
          }
        _ => return false
      }
    }
    true
  } else {
    false
  }
}

///|
pub extend WastRunnerError with Show::{to_string, output}
