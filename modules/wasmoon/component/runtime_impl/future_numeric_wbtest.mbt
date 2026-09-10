///|
test "numeric future payloads preserve 32-bit 64-bit and floating-point values" {
  let results : Array[Array[ComponentValue]] = []
  for read_first in [false, true] {
    for
      data in [
        ("u32", "i32", "55"),
        ("u64", "i64", "4294967351"),
        ("f64", "f64", "1.5"),
      ] {
      let (payload, core, literal) = data
      let source =
        #|(component
        #|  (core module $memory (memory (export "m") 1))
        #|  (core instance $memory (instantiate $memory))
        #|  (type $f (future PAYLOAD))
        #|  (core func $new (canon future.new $f))
        #|  (core func $read (canon future.read $f async (memory (core memory $memory "m"))))
        #|  (core func $write (canon future.write $f async (memory (core memory $memory "m"))))
        #|  (core module $M
        #|    (import "" "m" (memory 1))
        #|    (import "" "new" (func $new (result i64)))
        #|    (import "" "read" (func $read (param i32 i32) (result i32)))
        #|    (import "" "write" (func $write (param i32 i32) (result i32)))
        #|    (func (export "run") (result CORE) (local $pair i64) (local $r i32) (local $w i32)
        #|      call $new local.tee $pair i32.wrap_i64 local.set $r
        #|      local.get $pair i64.const 32 i64.shr_u i32.wrap_i64 local.set $w
        #|      i32.const 0 CORE.const LITERAL CORE.store
        #|      FIRST
        #|      i32.const -1 i32.ne if unreachable end
        #|      SECOND
        #|      if unreachable end
        #|      i32.const 16 CORE.load))
        #|  (core instance $m (instantiate $M (with "" (instance
        #|    (export "m" (memory $memory "m"))
        #|    (export "new" (func $new)) (export "read" (func $read)) (export "write" (func $write))))))
        #|  (func (export "run") (result PAYLOAD) (canon lift (core func $m "run"))))
      let read = "local.get $r i32.const 16 call $read"
      let write = "local.get $w i32.const 0 call $write"
      let source = source
        .replace_all(old="PAYLOAD", new=payload)
        .replace_all(old="CORE", new=core)
        .replace_all(old="LITERAL", new=literal)
        .replace_all(old="FIRST", new=if read_first { read } else { write })
        .replace_all(old="SECOND", new=if read_first { write } else { read })
      let component = @component.parse_component(
        @component_text.parse_component_wat(source),
      )
      let validated = @component_validator.validate_component_for_instantiation_with_config(
        component,
        ComponentValidationConfig(false),
      )
      let linker = ComponentLinker::ComponentLinker()
      defer linker.close()
      let instance = linker.instantiate("root", validated)
      results.push(instance.call_exported_func("run", []))
    }
  }
  debug_inspect(
    results,
    content=(
      #|[
      #|  [U32(55)],
      #|  [U64(4294967351)],
      #|  [F64(1.5)],
      #|  [U32(55)],
      #|  [U64(4294967351)],
      #|  [F64(1.5)],
      #|]
    ),
  )
}
