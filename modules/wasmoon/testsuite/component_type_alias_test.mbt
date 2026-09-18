///|
test "component type arguments preserve nested definitions behind instance aliases" {
  let bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (type $interface (instance
      #|    (type $optional (option string))
      #|    (type $record (record (field "value" $optional)))
      #|    (export "record" (type (eq $record)))))
      #|  (import "source" (instance $source (type $interface)))
      #|  (alias export $source "record" (type $record))
      #|  (component $consumer
      #|    (type $optional (option string))
      #|    (type $record (record (field "value" $optional)))
      #|    (import "record" (type (eq $record))))
      #|  (instance (instantiate $consumer (with "record" (type $record)))))
    ),
  )
  @component_model.validate_component(@component_types.parse_component(bytes))
}

///|
test "component type arguments still reject a mismatched nested alias payload" {
  let bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (type $interface (instance
      #|    (type $optional (option string))
      #|    (type $record (record (field "value" $optional)))
      #|    (export "record" (type (eq $record)))))
      #|  (import "source" (instance $source (type $interface)))
      #|  (alias export $source "record" (type $record))
      #|  (component $consumer
      #|    (type $optional (option u32))
      #|    (type $record (record (field "value" $optional)))
      #|    (import "record" (type (eq $record))))
      #|  (instance (instantiate $consumer (with "record" (type $record)))))
    ),
  )
  try
    @component_model.validate_component(@component_types.parse_component(bytes))
  catch {
    @component_model.ComponentImportTypeMismatch("type record") => ()
    error => fail("unexpected validation error: \{error}")
  } noraise {
    _ => fail("invalid component was accepted")
  }
}

///|
test "nested component type imports rebase dependency indices before re-export" {
  let producer = @component_model.validate_component_for_instantiation(
    @component_types.parse_component(
      @component_text.parse_component_wat(
        (
          #|(component
          #|  (type $padding u64)
          #|  (type $optional (option string))
          #|  (type $record (record (field "value" $optional)))
          #|  (component $child
          #|    (type $optional (option string))
          #|    (type $record (record (field "value" $optional)))
          #|    (import "record" (type $imported (eq $record)))
          #|    (export "record" (type $imported)))
          #|  (instance $child (instantiate $child (with "record" (type $record))))
          #|  (export "child" (instance $child)))
        ),
      ),
    ),
  )
  let consumer = @component_model.validate_component_for_instantiation(
    @component_types.parse_component(
      @component_text.parse_component_wat(
        (
          #|(component
          #|  (import "source" (instance
          #|    (type $optional (option string))
          #|    (type $record (record (field "value" $optional)))
          #|    (export "record" (type (eq $record))))))
        ),
      ),
    ),
  )
  let linker = @runtime_impl.ComponentLinker()
  defer linker.close()
  let instance = linker.instantiate("producer", producer)
  guard instance.get_export("child") is Some(Instance(child)) else {
    return fail("missing child")
  }
  linker.add_instance("source", child)
  linker.instantiate("consumer", consumer) |> ignore
}

///|
test "instantiated resource aliases preserve equality and distinct identities" {
  for same_resource in [true, false] {
    let second = if same_resource { "a" } else { "b" }
    let source =
      $|(component
      $|  (component $producer
      $|    (type $a (resource (rep i32)))
      $|    (type $b (resource (rep i32)))
      $|    (export "a" (type $a))
      $|    (export "b" (type $b)))
      $|  (instance $instance (instantiate $producer))
      $|  (alias export $instance "a" (type $a))
      $|  (alias export $instance "\{second}" (type $b))
      $|  (component $consumer
      $|    (import "a" (type $a (sub resource)))
      $|    (import "b" (type (eq $a))))
      $|  (instance (instantiate $consumer (with "a" (type $a)) (with "b" (type $b)))))
    let bytes = @component_text.parse_component_wat(source)
    try
      @component_model.validate_component(
        @component_types.parse_component(bytes),
      )
    catch {
      @component_model.SectionParseError(5, "resource types are not the same") =>
        assert_false(same_resource)
      error => fail("unexpected resource alias error: \{error}")
    } noraise {
      _ => assert_true(same_resource)
    }
  }
}
