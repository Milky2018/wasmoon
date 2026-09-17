///|
struct HttpBody {
  table : @runtime_impl.ResourceTable
  mut contents : Int?
  mut trailers : Int?
  mut receipt : Int?
  completion : Ref[@runtime_impl.ComponentValue?]
  trailer_status : Ref[@runtime_impl.ComponentValue?]
  trailer_result : Ref[@runtime_impl.ComponentValue?]
  buffer : Array[@runtime_impl.ComponentValue]
  closed : Ref[Bool]
  observed_closed : Ref[Bool]
  cancelled : Ref[Bool]
  mut consumed : Bool
}

///|
priv struct HttpMessage {
  headers : HttpFields
  options : HttpOptions?
  option_children : Ref[Int]
  body : HttpBody
  attributes : Map[String, @runtime_impl.ComponentValue]
}

///|
fn http_error(code : Int) -> @runtime_impl.ComponentValue {
  let payload : @runtime_impl.ComponentValue? = match code {
    17 | 21 | 22 | 23 | 26 | 28 | 29 | 31 | 32 | 38 => Some(Variant(0, None))
    1 | 14 | 24 | 27 | 30 => Some(Tuple([Variant(0, None), Variant(0, None)]))
    _ => None
  }
  Variant(1, Some(Variant(code, payload)))
}

///|
fn component_handle(
  value : @runtime_impl.ComponentValue,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  guard value is U32(handle) else { raise HostCallError("expected handle") }
  handle
}

///|
fn optional_handle(
  value : @runtime_impl.ComponentValue,
) -> Int? raise @runtime_impl.ComponentRuntimeError {
  match value {
    Variant(0, None) => None
    Variant(1, Some(value)) => Some(component_handle(value))
    _ => raise HostCallError("expected optional handle")
  }
}

///|
fn HttpHost::take(
  self : HttpHost,
  table : @runtime_impl.ResourceTable,
  value : @runtime_impl.ComponentValue,
  name : String,
  consume_body? : Bool = false,
) -> HttpResource raise @runtime_impl.ComponentRuntimeError {
  let resource = self.get(table, value, name)
  let handle = component_handle(value)
  let entry = table.get(handle).unwrap()
  let children = if consume_body && resource is Message(message) {
    message.option_children.val
  } else {
    0
  }
  if !entry.own || entry.num_lends[0] != children {
    raise HostCallError("cannot consume borrowed HTTP resource")
  }
  table.free(handle) |> ignore
  self.resources.remove(entry.rep)
  if resource is Options(options) {
    options.release_parent()
  }
  resource
}

///|
fn HttpHost::future_payload(
  self : HttpHost,
  parameter : Int,
) -> @component.ValType raise @runtime_impl.ComponentRuntimeError {
  let signature = wasi_http_func_type(
    "wasi:http@0.3.0/types", "[static]response.consume-body",
  ).unwrap()
  let ty = if parameter == 0 {
    signature.params[1].ty
  } else {
    guard signature.result is Some(TypeIdx(index)) &&
      self.types[index] is Some(Tuple(elements)) else {
      raise HostCallError("invalid HTTP body contract")
    }
    elements[1]
  }
  guard ty is TypeIdx(index) && self.types[index] is Some(Future(Some(payload))) else {
    raise HostCallError("invalid HTTP future contract")
  }
  payload
}

///|
fn HttpHost::new_message(
  self : HttpHost,
  response : Bool,
  args : Array[@runtime_impl.ComponentValue],
  table : @runtime_impl.ResourceTable,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  guard self.get(table, args[0], "fields") is Fields(headers) else {
    raise HostCallError("expected headers")
  }
  let owner = self.runtime.resource_table()
  let contents = optional_handle(args[1]).map(handle => {
    self.runtime.move_readable_stream(table, owner, handle)
  })
  let trailers = self.runtime.move_readable_future(
    table,
    owner,
    component_handle(args[2]),
  )
  let options = if !response && optional_handle(args[3]) is Some(handle) {
    guard self.get(table, U32(handle), "request-options") is Options(options) else {
      raise HostCallError("expected request options")
    }
    Some(options)
  } else {
    None
  }
  let completion = Ref(None)
  let result = self.runtime.new_host_value_future_source(
    table,
    self.future_payload(0),
    self.types,
    () => {
      match completion.val {
        Some(value) => Ready(value)
        None => Pending
      }
    },
    () => (),
  )
  let body : HttpBody = {
    table: owner,
    contents,
    trailers: Some(trailers),
    receipt: None,
    completion,
    trailer_status: Ref(None),
    trailer_result: Ref(None),
    buffer: [],
    closed: Ref(false),
    observed_closed: Ref(false),
    cancelled: Ref(false),
    consumed: false,
  }
  let attributes : Map[String, @runtime_impl.ComponentValue] = Map([
    ("method", Variant(0, None)),
    ("path-with-query", Variant(0, None)),
    ("scheme", Variant(0, None)),
    ("authority", Variant(0, None)),
    ("status-code", U16(200)),
  ])
  self.take(table, args[0], "fields") |> ignore
  if !response && optional_handle(args[3]) is Some(handle) {
    self.take(table, U32(handle), "request-options") |> ignore
  }
  self.bodies.push(body)
  let message = HttpMessage::{
    headers: headers.freeze(),
    options,
    option_children: Ref(0),
    body,
    attributes,
  }
  let name = if response { "response" } else { "request" }
  Tuple([self.allocate(table, name, Message(message)), U32(result)])
}

///|
fn HttpHost::consume_body(
  self : HttpHost,
  message : HttpMessage,
  receipt : Int,
  table : @runtime_impl.ResourceTable,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  let body = message.body
  let wake = self.wake
  body.receipt = Some(
    self.runtime.move_readable_future(table, body.table, receipt),
  )
  body.consumed = true
  let stream = self.runtime.new_host_value_stream_source(
    body.table,
    Prim(U8),
    [],
    maximum => {
      if !body.buffer.is_empty() {
        let count = Int::min(maximum, body.buffer.length())
        let values = body.buffer[:count].to_owned()
        let remaining = body.buffer[count:].to_owned()
        body.buffer.clear()
        body.buffer.append(remaining)
        wake.broadcast()
        Values(values)
      } else if body.closed.val {
        body.observed_closed.val = true
        wake.broadcast()
        Closed
      } else {
        Pending
      }
    },
    () => {
      if !body.observed_closed.val {
        body.cancelled.val = true
      }
      wake.broadcast()
    },
  )
  let future = self.runtime.new_host_value_future_source(
    body.table,
    self.future_payload(1),
    self.types,
    () => {
      if body.observed_closed.val && body.trailer_result.val is Some(value) {
        body.trailer_result.val = None
        Ready(value)
      } else {
        Pending
      }
    },
    () => {
      body.cancelled.val = true
      self.discard_trailers(body.trailer_result)
      wake.broadcast()
    },
  )
  Tuple([
    U32(self.runtime.move_readable_stream(body.table, table, stream)),
    U32(self.runtime.move_readable_future(body.table, table, future)),
  ])
}

///|
fn uri_part_valid(text : String, authority : Bool) -> Bool {
  for char in text {
    if char <= ' ' || char >= '\u007f' || char == '#' || char == '\\' {
      return false
    }
    if authority && (char == '/' || char == '?') {
      return false
    }
  }
  true
}

///|
fn scheme_valid(text : String) -> Bool {
  if text.is_empty() || !(text[0] is ('a'..='z' | 'A'..='Z')) {
    return false
  }
  for char in text {
    if !(char is ('a'..='z' | 'A'..='Z' | '0'..='9' | '+' | '-' | '.')) {
      return false
    }
  }
  true
}

///|
fn attribute_valid(name : String, value : @runtime_impl.ComponentValue) -> Bool {
  match (name, value) {
    ("method", Variant(9, Some(String(text)))) => field_token(text)
    ("path-with-query", Variant(1, Some(String(text)))) =>
      uri_part_valid(text, false)
    ("authority", Variant(1, Some(String(text)))) =>
      try authority_host_port(text, false) catch {
        _ => false
      } noraise {
        _ => true
      }
    ("scheme", Variant(1, Some(Variant(2, Some(String(text)))))) =>
      scheme_valid(text)
    ("status-code", U16(status)) => status >= 100 && status <= 999
    _ => true
  }
}

///|
fn HttpHost::message_call(
  self : HttpHost,
  name : String,
  args : Array[@runtime_impl.ComponentValue],
  table : @runtime_impl.ResourceTable,
) -> @runtime_impl.ComponentValue raise @runtime_impl.ComponentRuntimeError {
  let response = name.has_prefix("[method]response.") ||
    name.has_prefix("[static]response.")
  let kind = if response { "response" } else { "request" }
  if name.has_suffix(".new") {
    return self.new_message(response, args, table)
  }
  guard self.get(table, args[0], kind) is Message(message) else {
    raise HostCallError("expected HTTP message")
  }
  if name.has_suffix(".consume-body") {
    let result = self.consume_body(message, component_handle(args[1]), table)
    self.take(table, args[0], kind, consume_body=true) |> ignore
    return result
  }
  if name.has_suffix(".get-headers") {
    return self.allocate(table, "fields", Fields(message.headers))
  }
  if name.has_suffix(".get-options") {
    return match message.options {
      Some(options) => {
        let parent = table.get(component_handle(args[0])).unwrap()
        parent.num_lends[0] += 1
        message.option_children.val += 1
        Variant(
          1,
          Some(
            self.allocate(
              table,
              "request-options",
              Options({
                values: options.values.copy(),
                immutable: true,
                parent: Some((parent.num_lends, message.option_children)),
              }),
            ),
          ),
        )
      }
      None => Variant(0, None)
    }
  }
  let parts = name.split(".").to_array()
  let operation = parts[1].to_owned()
  let key = operation[4:].to_owned()
  if operation.has_prefix("get-") {
    return message.attributes.get(key).unwrap()
  }
  if !attribute_valid(key, args[1]) {
    return Variant(1, None)
  }
  message.attributes.set(key, args[1])
  Variant(0, None)
}

///|
/// Install the official HTTP types interface. Client and handler dispatch are
/// configured independently so middleware can forward without network I/O.
pub fn HttpHost::add_types(
  self : HttpHost,
) -> Unit raise @runtime_impl.ComponentRuntimeError {
  let interface = "wasi:http@0.3.0/types"
  let builder = self.linker.host_instance_builder(
    "wasi:http/types@0.3.0",
    self.runtime,
  )
  builder.set_type_space(self.types)
  for entry in wasi_http_exported_types(interface) {
    builder.add_type(entry.0, entry.1)
  }
  for name in http_type_functions() {
    let signature = wasi_http_func_type(interface, name).unwrap()
    builder.add_func(name, signature, (args, table) => {
      let result = if name.has_prefix("[method]fields.") ||
        name.has_prefix("[static]fields.") ||
        name == "[constructor]fields" {
        self.fields_call(name, args, table)
      } else if name.has_prefix("[method]request-options.") ||
        name == "[constructor]request-options" {
        self.options_call(name, args, table)
      } else {
        self.message_call(name, args, table)
      }
      [result]
    })
  }
  self.linker.add_instance("wasi:http/types@0.3.0", builder.finish())
}
