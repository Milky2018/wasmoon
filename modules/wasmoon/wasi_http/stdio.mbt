///|
fn HttpHost::prepare_interface(
  self : HttpHost,
  package : String,
  name : String,
) -> @runtime_impl.HostInstanceBuilder raise @runtime_impl.ComponentRuntimeError {
  let builder = self.linker.host_instance_builder(
    "wasi:\{package}/\{name}@0.3.0",
    self.runtime,
  )
  builder.set_type_space(self.types)
  for entry in wasi_http_exported_types("wasi:\{package}@0.3.0/\{name}") {
    builder.add_type(entry.0, entry.1)
  }
  builder
}

///|
fn HttpHost::add_service_stdio(
  self : HttpHost,
  stdout : &@io.Writer,
  stderr : &@io.Writer,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  self.linker.add_instance(
    "wasi:cli/types@0.3.0",
    self.prepare_interface("cli", "types").finish(),
  )
  let stdin = self.prepare_interface("cli", "stdin")
  let signature = wasi_http_func_type("wasi:cli@0.3.0/stdin", "read-via-stream").unwrap()
  guard signature.result is Some(TypeIdx(index)) &&
    self.types[index] is Some(Tuple([_, TypeIdx(future)])) &&
    self.types[future] is Some(Future(Some(payload))) else {
    raise HostCallError("invalid stdin contract")
  }
  stdin.add_func("read-via-stream", signature, (_, table) => {
    let contents = self.runtime.new_host_byte_stream(table, b"")
    let result = self.runtime.new_host_value_future(
      table,
      payload,
      self.types,
      Variant(0, None),
    )
    [Tuple([U32(contents), U32(result)])]
  })
  self.linker.add_instance("wasi:cli/stdin@0.3.0", stdin.finish())
  for entry in [("stdout", stdout), ("stderr", stderr)] {
    let (name, writer) = entry
    let builder = self.prepare_interface("cli", name)
    let signature = wasi_http_func_type(
      "wasi:cli@0.3.0/" + name,
      "write-via-stream",
    ).unwrap()
    guard signature.result is Some(TypeIdx(index)) &&
      self.types[index] is Some(Future(Some(payload))) else {
      raise HostCallError("invalid stdout contract")
    }
    builder.add_func("write-via-stream", signature, (args, table) => {
      guard args is [U32(stream)] && self.spawn.val is Some(spawn) else {
        raise HostCallError("HTTP stdio requires a running task scope")
      }
      let result = Ref(None)
      let task = spawn(async fn() {
        defer {
          self.runtime.drop_host_readable_stream(table, stream) catch {
            _ => ()
          }
          self.wake.broadcast()
        }
        try {
          while self.read_body(table, stream) is Some(bytes) {
            writer.write(bytes)
          }
          result.val = Some(@runtime_impl.ComponentValue::Variant(0, None))
        } catch {
          _ => result.val = Some(Variant(1, Some(U32(0))))
        }
      })
      let future = self.runtime.new_host_value_future_source(
        table,
        payload,
        self.types,
        () => {
          match result.val {
            Some(value) => Ready(value)
            None => Pending
          }
        },
        () => task.cancel(),
      )
      [U32(future)]
    })
    self.linker.add_instance("wasi:cli/\{name}@0.3.0", builder.finish())
  }
}
