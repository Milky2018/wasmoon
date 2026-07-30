///|
test "component text parser: empty component" {
  let bytes = parse_component_wat("(component)") catch {
    e => {
      inspect(e)
      panic()
    }
  }
  let parsed = @component.parse_component(bytes) catch {
    e => {
      inspect(e)
      panic()
    }
  }
  inspect(parsed.binary.layer, content="1")
  inspect(parsed.binary.sections.length(), content="0")
}

///|
test "component text parser: nested component import func" {
  let text = "(component (component (import \"a\" (func))))"
  let bytes = parse_component_wat(text) catch {
    e => {
      inspect(e)
      panic()
    }
  }
  let parsed = @component.parse_component(bytes) catch {
    e => {
      inspect(e)
      panic()
    }
  }
  inspect(parsed.components.length(), content="1")
  inspect(parsed.components[0].types.length(), content="1")
  debug_inspect(parsed.components[0].imports.length(), content="1")
  @component_model.validate_component(parsed)
}

///|
test "component text parser: core module and canon lift" {
  let text = "(component " +
    "(core module $M " +
    "(memory (export \"mem\") 1) " +
    "(func (export \"f\") (result i32) (i32.const 0))" +
    "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0))" +
    ") " +
    "(core instance $m (instantiate $M)) " +
    "(func (export \"f\") (result string) (canon lift (core func $m \"f\") (memory $m \"mem\") (realloc (core func $m \"realloc\"))))" +
    ")"
  let bytes = parse_component_wat(text) catch {
    e => {
      inspect(e)
      panic()
    }
  }
  let parsed = @component.parse_component(bytes) catch {
    e => {
      inspect(e)
      panic()
    }
  }
  inspect(parsed.core_modules.length(), content="1")
  inspect(parsed.core_instances.length(), content="1")
  inspect(parsed.canons.length(), content="1")
  debug_inspect(parsed.exports.length(), content="1")
  @component_model.validate_component(parsed)
}

///|
test "component text parser: utf8 names are accepted" {
  let text = "(component (type (record (field \"参数\" u32))))"
  let bytes = parse_component_wat(text) catch {
    e => {
      inspect(e)
      panic()
    }
  }
  let parsed = @component.parse_component(bytes) catch {
    e => {
      inspect(e)
      panic()
    }
  }
  inspect(parsed.types.length(), content="1")
}

///|
fn validate_component_text_for_test(text : String) -> Unit raise {
  let bytes = parse_component_wat(text)
  let parsed = @component.parse_component(bytes)
  @component_model.validate_component(parsed)
}

///|
fn component_validation_error(text : String) -> Error raise {
  try validate_component_text_for_test(text) catch {
    error => error
  } noraise {
    _ => fail("expected component validation to fail")
  }
}

///|
test "component text parser: strict core index forms" {
  let cases = [
    (
      #|(component
      #|  (import "f" (func $f))
      #|  (core func (canon lower (func 0)))
      #|  (core func (canon lower (func $f))))
      #|
    ),
    (
      #|(component
      #|  (core module $M (func (export "f")))
      #|  (core instance $m (instantiate $M))
      #|  (alias core export $m "f" (core func $f))
      #|  (func (canon lift (core func 0)))
      #|  (func (canon lift (core func $m "f"))))
      #|
    ),
    (
      #|(component
      #|  (core module $M (memory (export "mem") 1))
      #|  (core instance $m (instantiate $M))
      #|  (alias core export $m "mem" (core memory $mem))
      #|  (canon waitable-set.wait
      #|    (memory (core memory 0))
      #|    (core func)))
      #|
    ),
    (
      #|(component
      #|  (core type $ft (func (param i32)))
      #|  (core module $M (table (export "tbl") 1 funcref))
      #|  (core instance $m (instantiate $M))
      #|  (alias core export $m "tbl" (core table $tbl))
      #|  (canon thread.new-indirect
      #|    (core type $ft)
      #|    (core table $tbl)
      #|    (core func)))
      #|
    ),
    (
      #|(component
      #|  (type $T (future u32))
      #|  (canon future.new (type $T) (core func)))
      #|
    ),
  ]
  for i, text in cases {
    validate_component_text_for_test(text) catch {
      error => fail("strict core index case \{i}: \{error}")
    }
  }
}

///|
test "component text parser: import and export attributes" {
  validate_component_text_for_test(
    (
      #|(component
      #|  (import "store" (implements "w:kv/s") (external-id "primary")
      #|    (instance $store))
      #|  (import "wasi:http/types@0.2" (versionsuffix ".6") (instance))
      #|  (export "store" (implements "w:kv/s") (external-id "public")
      #|    (instance $store)))
      #|
    ),
  )
  inspect(
    component_validation_error(
      (
        #|(component
        #|  (import "f" (implements "w:kv/s") (func)))
        #|
      ),
    ),
    content=(
      #|SectionParseError(10, "only instances can have an `implements`")
    ),
  )
  inspect(
    component_validation_error(
      (
        #|(component
        #|  (import "wasi:http/types@0.2.6" (versionsuffix "") (instance)))
        #|
      ),
    ),
    content=(
      #|SectionParseError(10, "invalid version suffix")
    ),
  )
}

///|
test "component validator: external type visibility is nominal" {
  inspect(
    component_validation_error(
      (
        #|(component
        #|  (core module $m (func (export "f") (result i32) unreachable))
        #|  (core instance $i (instantiate $m))
        #|  (type $R (resource (rep i32)))
        #|  (func $f (result (own $R)) (canon lift (core func $i "f")))
        #|  (export $R-visible "r" (type $R))
        #|  (export "f" (func $f)))
        #|
      ),
    ),
    content=(
      #|SectionParseError(11, "func not valid to be used as export")
    ),
  )
  let positive =
    #|(component
    #|  (core module $m (func (export "f") (result i32) unreachable))
    #|  (core instance $i (instantiate $m))
    #|  (type $R (resource (rep i32)))
    #|  (export $R-visible "r" (type $R))
    #|  (type $Rec (record (field "r" (own $R-visible))))
    #|  (export $Rec-visible "rec" (type $Rec))
    #|  (func $f (result $Rec-visible) (canon lift (core func $i "f")))
    #|  (export "f" (func $f)))
    #|
  validate_component_text_for_test(positive)
  validate_component_text_for_test(
    (
      #|(component
      #|  (type $r' (record (field "f" u32)))
      #|  (import "r" (type $r (eq $r')))
      #|  (component $C
      #|    (type $r' (record (field "f" u32)))
      #|    (import "r" (type $r (eq $r')))
      #|    (type $r2' (record (field "r" $r)))
      #|    (export "r2" (type $r2')))
      #|  (instance $c (instantiate $C (with "r" (type $r))))
      #|  (export "r2" (type $c "r2")))
      #|
    ),
  )
}

///|
test "component validator: outer aliases respect declarator boundaries" {
  inspect(
    component_validation_error(
      (
        #|(component $C
        #|  (type $R (resource (rep i32)))
        #|  (component
        #|    (type (component
        #|      (alias outer 2 0 (type $a))))))
        #|
      ),
    ),
    content=(
      #|SectionParseError(7, "transitively refers to resources")
    ),
  )
  inspect(
    component_validation_error(
      (
        #|(component
        #|  (type (component
        #|    (import "i" (instance $i (export "f" (func))))
        #|    (alias export $i "f" (func $a)))))
        #|
      ),
    ),
    content=(
      #|SectionParseError(7, "alias export may only refer to types or instances")
    ),
  )
  validate_component_text_for_test(
    (
      #|(component $C
      #|  (core type $FT (func (param i32) (result i32)))
      #|  (type (component
      #|    (alias outer $C $FT (core type $ct)))))
      #|
    ),
  )
}

///|
test "component validator: resource identity includes handle mode" {
  inspect(
    component_validation_error(
      (
        #|(component
        #|  (import "T" (type $T (sub resource)))
        #|  (import "f" (func $f (param "x" (borrow $T))))
        #|  (component $c
        #|    (import "T" (type $T (sub resource)))
        #|    (import "g" (func (param "x" (own $T)))))
        #|  (instance (instantiate $c
        #|    (with "T" (type $T))
        #|    (with "g" (func $f)))))
        #|
      ),
    ),
    content=(
      #|SectionParseError(5, "resource types are not the same")
    ),
  )
  inspect(
    component_validation_error(
      (
        #|(component
        #|  (type $R1 (resource (rep i32)))
        #|  (type $R2 (resource (rep i32)))
        #|  (component $eq
        #|    (import "a" (type $a (sub resource)))
        #|    (import "b" (type (eq $a))))
        #|  (instance (instantiate $eq
        #|    (with "a" (type $R1))
        #|    (with "b" (type $R2)))))
        #|
      ),
    ),
    content=(
      #|SectionParseError(5, "resource types are not the same")
    ),
  )
  inspect(
    component_validation_error(
      (
        #|(component
        #|  (component $C
        #|    (type $R (resource (rep i32)))
        #|    (export "r1" (type $R))
        #|    (export "r2" (type $R) (type (sub resource))))
        #|  (instance $c (instantiate $C))
        #|  (alias export $c "r1" (type $R1))
        #|  (alias export $c "r2" (type $R2))
        #|  (component $eq
        #|    (import "a" (type $a (sub resource)))
        #|    (import "b" (type (eq $a))))
        #|  (instance (instantiate $eq
        #|    (with "a" (type $R1))
        #|    (with "b" (type $R2)))))
        #|
      ),
    ),
    content=(
      #|SectionParseError(5, "resource types are not the same")
    ),
  )
}
