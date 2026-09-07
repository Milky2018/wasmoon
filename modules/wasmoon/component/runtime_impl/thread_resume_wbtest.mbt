///|
test "explicit resume rejects a runnable thread" {
  for
    operation in [
      "thread.resume-later", "thread.yield-then-resume", "thread.suspend-then-resume",
    ] {
    let source =
      #|(component
      #|  (core module $T (table (export "t") 1 funcref))
      #|  (core instance $t (instantiate $T))
      #|  (core type $start (func (param i32)))
      #|  (core func $new (canon thread.new-indirect $start (core table $t "t")))
      #|  (core func $yield (canon thread.yield))
      #|  (core func $resume (canon thread.yield-then-resume))
      #|  (core func $again (canon OP))
      #|  (core module $M
      #|    (import "" "t" (table 1 funcref))
      #|    (import "" "new" (func $new (param i32 i32) (result i32)))
      #|    (import "" "yield" (func $yield (result i32)))
      #|    (import "" "resume" (func $resume (param i32) (result i32)))
      #|    (import "" "again" (func $again (param i32) RESULT))
      #|    (func $child (param i32) call $yield drop)
      #|    (elem (i32.const 0) func $child)
      #|    (func (export "run") (local $h i32)
      #|      i32.const 0 i32.const 0 call $new local.tee $h
      #|      call $resume drop local.get $h call $again DROP))
      #|  (core instance $m (instantiate $M (with "" (instance
      #|    (export "t" (table $t "t")) (export "new" (func $new))
      #|    (export "yield" (func $yield)) (export "resume" (func $resume))
      #|    (export "again" (func $again))))))
      #|  (func (export "run") async (canon lift (core func $m "run"))))
    let source = source
      .replace_all(old="canon OP", new="canon " + operation)
      .replace_all(
        old="RESULT",
        new=if operation == "thread.resume-later" { "" } else { "(result i32)" },
      )
      .replace_all(
        old="DROP",
        new=if operation == "thread.resume-later" { "" } else { "drop" },
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
    let error = try {
      instance.call_exported_func("run", []) |> ignore
      "unexpected return"
    } catch {
      error => canon_err_message(error)
    }
    inspect(error, content="cannot resume thread which is not suspended")
  }
}
