///|
test "component context slots are isolated across exports and component instances" {
  let source =
    #|(component
    #|  (component $A
    #|    (core func $get (canon context.get i32 0))
    #|    (core func $set (canon context.set i32 0))
    #|    (core module $M
    #|      (import "" "get" (func $get (result i32)))
    #|      (import "" "set" (func $set (param i32)))
    #|      (func (export "f")
    #|        call $get if unreachable end
    #|        i32.const 99 call $set))
    #|    (core instance $m (instantiate $M (with "" (instance
    #|      (export "get" (func $get)) (export "set" (func $set))))))
    #|    (func (export "f") (canon lift (core func $m "f"))))
    #|  (component $B
    #|    (import "f" (func $f))
    #|    (core func $f (canon lower (func $f)))
    #|    (core func $get0 (canon context.get i32 0))
    #|    (core func $set0 (canon context.set i32 0))
    #|    (core func $get1 (canon context.get i32 1))
    #|    (core func $set1 (canon context.set i32 1))
    #|    (core module $M
    #|      (import "" "f" (func $f))
    #|      (import "" "get0" (func $get0 (result i32)))
    #|      (import "" "set0" (func $set0 (param i32)))
    #|      (import "" "get1" (func $get1 (result i32)))
    #|      (import "" "set1" (func $set1 (param i32)))
    #|      (func (export "run") (result i32)
    #|        call $get0 call $get1 i32.or if unreachable end
    #|        i32.const 11 call $set0
    #|        i32.const 22 call $set1
    #|        call $f
    #|        call $f
    #|        call $get0 call $get1 i32.add))
    #|    (core instance $m (instantiate $M (with "" (instance
    #|      (export "f" (func $f))
    #|      (export "get0" (func $get0)) (export "set0" (func $set0))
    #|      (export "get1" (func $get1)) (export "set1" (func $set1))))))
    #|    (func (export "run") (result u32) (canon lift (core func $m "run"))))
    #|  (instance $a (instantiate $A))
    #|  (instance $b (instantiate $B (with "f" (func $a "f"))))
    #|  (export "run" (func $b "run")))
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
  debug_inspect(instance.call_exported_func("run", []), content="[U32(33)]")
  debug_inspect(instance.call_exported_func("run", []), content="[U32(33)]")
}
