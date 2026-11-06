///|
test "CLI JIT uses shared imported globals, tables, and memory" {
  let stamp = @env.now()
  let provider = @test_fs.temp_dir() + "/wasmoon-shared-provider-\{stamp}.wat"
  let consumer = @test_fs.temp_dir() + "/wasmoon-shared-consumer-\{stamp}.wat"
  @fs.write_string_to_file(
    provider,
    (
      #|(module
      #|(type $sig (func (result i32)))
      #|(global (export "g") (mut i32) (i32.const 3))
      #|(memory (export "m") 1)
      #|(table (export "t") 1 funcref)
      #|(func $f (export "call") (type $sig) (result i32)
      #|  global.get 0 i32.const 1 i32.add global.set 0
      #|  i32.const 0 i32.load global.get 0 i32.add)
      #|(elem (i32.const 0) $f))
    ),
  )
  defer (@fs.remove_file(provider) catch { _ => () })
  @fs.write_string_to_file(
    consumer,
    (
      #|(module
      #|(type $sig (func (result i32)))
      #|(import "dep" "call" (func $direct (type $sig)))
      #|(import "dep" "g" (global (mut i32)))
      #|(import "dep" "m" (memory 1))
      #|(import "dep" "t" (table 1 funcref))
      #|(export "t" (table 0))
      #|(func (export "run") (result i32 i32)
      #|  i32.const 0 i32.const 10 i32.store
      #|  global.get 0 i32.const 2 i32.add global.set 0
      #|  i32.const 0 call_indirect (type $sig)
      #|  global.get 0)
      #|(func (export "run-direct") (result i32 i32 i32)
      #|  i32.const 0 i32.const 10 i32.store
      #|  global.get 0 i32.const 2 i32.add global.set 0
      #|  i32.const 0 call_indirect (type $sig)
      #|  call $direct
      #|  global.get 0))
    ),
  )
  defer (@fs.remove_file(consumer) catch { _ => () })
  for function in ["run", "run-direct"] {
    inspect(
      run_wasm(
        consumer,
        Some(function),
        [],
        [],
        ["dep=" + provider],
        [],
        [],
        [],
        false,
        false,
        true,
        2,
        false,
      ),
      content="0",
    )
  }
}
