///|
test "sanitizer instrumentation positive control" {
  if @env.get_env_var("WASMOON_SANITIZER_PROBE") == Some("native") {
    native_probe()
  }
  // This branch is run only by the gate's separate expected-failure process.
  // The unsafe load must reach generated MoonBit C, not a native test stub.
  if @env.get_env_var("WASMOON_SANITIZER_PROBE") == Some("asan") {
    let values : FixedArray[Int] = FixedArray::make(1_000_000, 42)
    inspect(values.unsafe_get(1_000_000), content="unreachable")
  }
}

///|
extern "c" fn native_probe() -> Unit = "wasmoon_sanitizer_native_probe"
