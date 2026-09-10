///|
test "future strings cross memories and encodings in both rendezvous orders" {
  for read_first in [false, true] {
    let source =
      #|(component
      #|  (component $Reader
      #|    (type $f (future string))
      #|    (core module $Mem
      #|      (memory (export "m") 1)
      #|      (func (export "realloc") (param i32 i32 i32 i32) (result i32) i32.const 256))
      #|    (core instance $mem (instantiate $Mem))
      #|    (core func $read (canon future.read $f async string-encoding=utf16
      #|      (memory (core memory $mem "m")) (realloc (core func $mem "realloc"))))
      #|    (core module $M
      #|      (import "" "read" (func $read (param i32 i32) (result i32)))
      #|      (func (export "read") (param i32) (result i32) local.get 0 i32.const 0 call $read)
      #|      (func (export "result") (result i32) i32.const 0))
      #|    (core instance $m (instantiate $M (with "" (instance (export "read" (func $read))))))
      #|    (func (export "read") (param "f" $f) (result s32) (canon lift (core func $m "read")))
      #|    (func (export "result") (result string) (canon lift (core func $m "result")
      #|      string-encoding=utf16 (memory (core memory $mem "m")))))
      #|  (instance $reader (instantiate $Reader))
      #|  (component $Writer
      #|  (type $f (future string))
      #|  (import "read" (func $reader-read (param "f" $f) (result s32)))
      #|  (import "result" (func $reader-result (result string)))
      #|  (core module $Mem
      #|    (memory (export "m") 1) (data (i32.const 128) "h\c3\a9")
      #|    (func (export "realloc") (param i32 i32 i32 i32) (result i32) i32.const 256))
      #|  (core instance $mem (instantiate $Mem))
      #|  (core func $new (canon future.new $f))
      #|  (core func $write (canon future.write $f async (memory (core memory $mem "m"))))
      #|  (core func $read (canon lower (func $reader-read)))
      #|  (core func $result (canon lower (func $reader-result)
      #|    (memory (core memory $mem "m")) (realloc (core func $mem "realloc"))))
      #|  (core module $M
      #|    (import "" "m" (memory 1))
      #|    (import "" "new" (func $new (result i64)))
      #|    (import "" "write" (func $write (param i32 i32) (result i32)))
      #|    (import "" "read" (func $read (param i32) (result i32)))
      #|    (import "" "result" (func $result (param i32)))
      #|    (func (export "run") (result i32) (local $pair i64) (local $r i32) (local $w i32)
      #|      i32.const 32 i32.const 128 i32.store
      #|      i32.const 36 i32.const 3 i32.store
      #|      call $new local.tee $pair i32.wrap_i64 local.set $r
      #|      local.get $pair i64.const 32 i64.shr_u i32.wrap_i64 local.set $w
      #|      FIRST i32.const -1 i32.ne if unreachable end
      #|      MUTATE
      #|      SECOND if unreachable end
      #|      i32.const 0 call $result i32.const 0))
      #|  (core instance $m (instantiate $M (with "" (instance
      #|    (export "m" (memory $mem "m")) (export "new" (func $new))
      #|    (export "write" (func $write)) (export "read" (func $read)) (export "result" (func $result))))))
      #|  (func (export "run") (result string) (canon lift (core func $m "run") (memory (core memory $mem "m")))))
      #|  (instance $writer (instantiate $Writer
      #|    (with "read" (func $reader "read")) (with "result" (func $reader "result"))))
      #|  (export "run" (func $writer "run")))
    let read = "local.get $r call $read"
    let write = "local.get $w i32.const 32 call $write"
    let source = source
      .replace_all(old="FIRST", new=if read_first { read } else { write })
      .replace_all(old="SECOND", new=if read_first { write } else { read })
      .replace_all(
        old="MUTATE",
        new=if read_first {
          ""
        } else {
          "i32.const 128 i32.const 122 i32.store8"
        },
      )
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
    debug_inspect(
      instance.call_exported_func("run", []),
      content="[String(\"hé\")]",
    )
  }
}
