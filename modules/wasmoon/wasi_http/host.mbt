///|
priv struct HttpOptions {
  values : Array[@runtime_impl.ComponentValue]
  mut parent : (Array[Int], Ref[Int])?
  immutable : Bool
}

///|
enum HttpResource {
  Fields(HttpFields)
  Message(HttpMessage)
  Options(HttpOptions)
}

///|
/// Shared HTTP resource identities and registrations for one component linker.
pub struct HttpHost {
  linker : @runtime_impl.ComponentLinker
  runtime : @runtime_impl.HostRuntimeState
  resources : Map[Int, HttpResource]
  bodies : Array[HttpBody]
  wake : @async.CondVar
  pending : Array[HttpInvocation]
  spawn : Ref[((async () -> Unit) -> @async.Task[Unit])?]
  next_id : Ref[Int]
  types : Array[@component.TypeDef?]
  resource_types : Map[String, @component.TypeDef?]
}

///|
pub fn HttpHost::HttpHost(
  linker : @runtime_impl.ComponentLinker,
) -> HttpHost raise @runtime_impl.ComponentRuntimeError {
  let resource_types : Map[String, @component.TypeDef?] = Map([])
  for name in wasi_http_resource_names() {
    resource_types.set(name, linker.new_host_resource_type())
  }
  let types = wasi_http_type_space(fn(name) {
    resource_types.get(name).unwrap()
  })
  {
    linker,
    runtime: linker.host_runtime_state(),
    resources: Map([]),
    bodies: [],
    wake: Cond(),
    pending: [],
    spawn: Ref(None),
    next_id: Ref(0),
    types,
    resource_types,
  }
}

///|
fn HttpHost::allocate(
  self : HttpHost,
  table : @runtime_impl.ResourceTable,
  name : String,
  value : HttpResource,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  guard self.resource_types.get("wasi:http@0.3.0/types." + name)
    is Some(Some(ResourceType(type_id, _, _, _))) else {
    raise HostCallError("missing HTTP resource type")
  }
  let rep = self.next_id.val
  self.next_id.val += 1
  self.resources.set(rep, value)
  // Capture the registry, not the host/linker, to avoid retaining the runtime.
  let resources = self.resources
  let wake = self.wake
  U32(
    table.alloc({
      type_id,
      rep,
      dtor: None,
      host_dtor: Some(
        HostResourceDestructor(fn(rep) {
          if resources.get(rep) is Some(Message(message)) {
            message.body.cancelled.val = true
            wake.broadcast()
          }
          if resources.get(rep) is Some(Options(options)) {
            options.release_parent()
          }
          resources.remove(rep)
        }),
      ),
      kind: HostDefined,
      impl_component_id: table.id,
      own: true,
      borrow_scope: None,
      num_lends: [0],
    }),
  )
}

///|
fn HttpHost::get(
  self : HttpHost,
  table : @runtime_impl.ResourceTable,
  value : @runtime_impl.ComponentValue,
  name : String,
) -> HttpResource raise @runtime_impl.ComponentRuntimeError {
  guard value is U32(handle) &&
    table.get(handle) is Some(entry) &&
    self.resource_types.get("wasi:http@0.3.0/types." + name)
    is Some(Some(ResourceType(type_id, _, _, _))) &&
    entry.type_id == type_id &&
    self.resources.get(entry.rep) is Some(resource) else {
    raise HostCallError("invalid HTTP resource handle")
  }
  resource
}

///|
fn component_bytes(
  value : @runtime_impl.ComponentValue,
) -> Bytes raise @runtime_impl.ComponentRuntimeError {
  guard value is List(values) else { raise HostCallError("expected byte list") }
  let bytes : Array[Byte] = []
  for value in values {
    guard value is U8(byte) && byte >= 0 && byte <= 255 else {
      raise HostCallError("invalid byte")
    }
    bytes.push(byte.to_byte())
  }
  Bytes::from_array(bytes)
}

///|
fn component_string(
  value : @runtime_impl.ComponentValue,
) -> String raise @runtime_impl.ComponentRuntimeError {
  guard value is String(text) else { raise HostCallError("expected string") }
  text
}

///|
fn bytes_value(bytes : Bytes) -> @runtime_impl.ComponentValue {
  List(bytes.to_array().map(fn(byte) { U8(byte.to_int()) }))
}

///|
fn header_error(error : HeaderError) -> @runtime_impl.ComponentValue {
  Variant(
    1,
    Some(
      Variant(
        match error {
          InvalidSyntax => 0
          Forbidden => 1
          Immutable => 2
          SizeExceeded => 3
        },
        None,
      ),
    ),
  )
}

///|
fn header_result(
  result : Result[Unit, HeaderError],
) -> @runtime_impl.ComponentValue {
  match result {
    Ok(_) => Variant(0, None)
    Err(error) => header_error(error)
  }
}

///|
fn HttpHost::fields_call(
  self : HttpHost,
  name : String,
  args : Array[@runtime_impl.ComponentValue],
  table : @runtime_impl.ResourceTable,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  if name == "[constructor]fields" {
    return self.allocate(
      table,
      "fields",
      Fields(HttpFields::from_list().unwrap()),
    )
  }
  if name == "[static]fields.from-list" {
    guard args is [List(entries)] else {
      raise HostCallError("expected fields entries")
    }
    let fields : Array[(String, Bytes)] = []
    for entry in entries {
      guard entry is Tuple([key, value]) else {
        raise HostCallError("expected field pair")
      }
      fields.push((component_string(key), component_bytes(value)))
    }
    return match HttpFields::from_list(entries=fields) {
      Ok(fields) =>
        Variant(0, Some(self.allocate(table, "fields", Fields(fields))))
      Err(error) => header_error(error)
    }
  }
  guard args.length() > 0 &&
    self.get(table, args[0], "fields") is Fields(fields) else {
    raise HostCallError("expected fields resource")
  }
  match name {
    "[method]fields.get" =>
      List(fields.get(component_string(args[1])).map(bytes_value))
    "[method]fields.has" => Bool(fields.has(component_string(args[1])))
    "[method]fields.set" => {
      guard args[2] is List(values) else {
        raise HostCallError("expected field values")
      }
      header_result(
        fields.set(component_string(args[1]), values.map(component_bytes)),
      )
    }
    "[method]fields.append" =>
      header_result(
        fields.append(component_string(args[1]), component_bytes(args[2])),
      )
    "[method]fields.delete" =>
      header_result(fields.delete(component_string(args[1])))
    "[method]fields.get-and-delete" => {
      let name = component_string(args[1])
      let values = fields.get(name)
      match fields.delete(name) {
        Ok(_) => Variant(0, Some(List(values.map(bytes_value))))
        Err(error) => header_error(error)
      }
    }
    "[method]fields.copy-all" =>
      List(
        fields
        .copy_all()
        .map(fn(entry) { Tuple([String(entry.0), bytes_value(entry.1)]) }),
      )
    "[method]fields.clone" =>
      self.allocate(table, "fields", Fields(fields.clone()))
    _ => raise HostCallError("unknown fields operation")
  }
}

///|
fn HttpHost::options_call(
  self : HttpHost,
  name : String,
  args : Array[@runtime_impl.ComponentValue],
  table : @runtime_impl.ResourceTable,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  if name == "[constructor]request-options" {
    return self.allocate(
      table,
      "request-options",
      Options({
        values: [Variant(0, None), Variant(0, None), Variant(0, None)],
        immutable: false,
        parent: None,
      }),
    )
  }
  guard args.length() > 0 &&
    self.get(table, args[0], "request-options") is Options(options) else {
    raise HostCallError("expected request options")
  }
  if name == "[method]request-options.clone" {
    return self.allocate(
      table,
      "request-options",
      Options({ values: options.values.copy(), immutable: false, parent: None, }),
    )
  }
  let index = if name.has_suffix("connect-timeout") {
    0
  } else if name.has_suffix("first-byte-timeout") {
    1
  } else {
    2
  }
  if name.has_prefix("[method]request-options.get-") {
    return options.values[index]
  }
  if options.immutable {
    return Variant(1, Some(Variant(1, None)))
  }
  options.values[index] = args[1]
  Variant(0, None)
}

///|
fn HttpOptions::release_parent(self : HttpOptions) -> Unit {
  if self.parent is Some((lends, children)) {
    lends[0] -= 1
    children.val -= 1
    self.parent = None
  }
}
