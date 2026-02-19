///|
pub suberror ComponentTextError {
  ParseError(String)
  Unsupported(String)
}

///|
fn ComponentTextError::to_string(self : ComponentTextError) -> String {
  match self {
    ParseError(msg) => "parse error: \{msg}"
    Unsupported(msg) => "unsupported: \{msg}"
  }
}

///|
pub impl Show for ComponentTextError with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
priv enum SExpr {
  Atom(String)
  Str(String)
  List(Array[SExpr])
}

///|
priv struct TextReader {
  input : String
  mut pos : Int
}

///|
fn TextReader::new(input : String) -> TextReader {
  { input, pos: 0 }
}

///|
fn TextReader::is_eof(self : TextReader) -> Bool {
  self.pos >= self.input.length()
}

///|
fn TextReader::peek_char(self : TextReader) -> Char? {
  if self.is_eof() {
    None
  } else {
    Some(self.input.code_unit_at(self.pos).unsafe_to_char())
  }
}

///|
fn TextReader::peek_next_char(self : TextReader) -> Char? {
  if self.pos + 1 >= self.input.length() {
    None
  } else {
    Some(self.input.code_unit_at(self.pos + 1).unsafe_to_char())
  }
}

///|
fn TextReader::next_char(self : TextReader) -> Char? {
  if self.is_eof() {
    None
  } else {
    let ch = self.input.code_unit_at(self.pos).unsafe_to_char()
    self.pos += 1
    Some(ch)
  }
}

///|
fn is_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t'
}

///|
fn TextReader::skip_line_comment(self : TextReader) -> Unit {
  while !self.is_eof() {
    let ch = self.input.code_unit_at(self.pos).unsafe_to_char()
    self.pos += 1
    if ch == '\n' {
      return
    }
  }
}

///|
fn TextReader::skip_block_comment(
  self : TextReader,
) -> Unit raise ComponentTextError {
  let mut depth = 1
  while depth > 0 {
    if self.is_eof() {
      raise ParseError("unterminated block comment")
    }
    let current = self.peek_char()
    let next = self.peek_next_char()
    if current == Some('(') && next == Some(';') {
      self.pos += 2
      depth += 1
      continue
    }
    if current == Some(';') && next == Some(')') {
      self.pos += 2
      depth -= 1
      continue
    }
    self.pos += 1
  }
}

///|
fn TextReader::skip_ws_and_comments(
  self : TextReader,
) -> Unit raise ComponentTextError {
  while !self.is_eof() {
    let current = self.peek_char()
    let next = self.peek_next_char()
    if current is Some(ch) && is_space(ch) {
      self.pos += 1
      continue
    }
    if current == Some(';') && next == Some(';') {
      self.pos += 2
      self.skip_line_comment()
      continue
    }
    if current == Some('(') && next == Some(';') {
      self.pos += 2
      self.skip_block_comment()
      continue
    }
    return
  }
}

///|
fn is_hex_digit(ch : Char) -> Bool {
  ('0' <= ch && ch <= '9') ||
  ('a' <= ch && ch <= 'f') ||
  ('A' <= ch && ch <= 'F')
}

///|
fn hex_digit_value(ch : Char) -> Int {
  if '0' <= ch && ch <= '9' {
    ch.to_int() - '0'.to_int()
  } else if 'a' <= ch && ch <= 'f' {
    ch.to_int() - 'a'.to_int() + 10
  } else if 'A' <= ch && ch <= 'F' {
    ch.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
fn TextReader::read_string(
  self : TextReader,
) -> String raise ComponentTextError {
  let out = StringBuilder::new()
  self.next_char() |> ignore // consume opening quote
  while !self.is_eof() {
    let ch = match self.next_char() {
      Some(ch) => ch
      None => raise ParseError("unterminated string literal")
    }
    if ch == '"' {
      return out.to_string()
    }
    if ch != '\\' {
      out.write_char(ch)
      continue
    }
    if self.is_eof() {
      raise ParseError("unterminated string escape")
    }
    let esc = match self.next_char() {
      Some(ch) => ch
      None => raise ParseError("unterminated string escape")
    }
    if esc == 'n' {
      out.write_char('\n')
    } else if esc == 'r' {
      out.write_char('\r')
    } else if esc == 't' {
      out.write_char('\t')
    } else if esc == '"' {
      out.write_char('"')
    } else if esc == '\\' {
      out.write_char('\\')
    } else if is_hex_digit(esc) &&
      self.peek_char() is Some(next_ch) &&
      is_hex_digit(next_ch) {
      let hi = hex_digit_value(esc)
      let lo_ch = match self.next_char() {
        Some(ch) => ch
        None => raise ParseError("unterminated hex escape")
      }
      let lo = hex_digit_value(lo_ch)
      out.write_char((hi * 16 + lo).unsafe_to_char())
    } else {
      out.write_char(esc)
    }
  }
  raise ParseError("unterminated string literal")
}

///|
fn TextReader::read_atom(self : TextReader) -> String raise ComponentTextError {
  let start = self.pos
  while !self.is_eof() {
    let ch = match self.peek_char() {
      Some(ch) => ch
      None => break
    }
    if is_space(ch) || ch == '(' || ch == ')' {
      break
    }
    self.pos += 1
  }
  if self.pos <= start {
    raise ParseError("expected atom")
  }
  let builder = StringBuilder::new()
  for index in start..<self.pos {
    builder.write_char(self.input.code_unit_at(index).unsafe_to_char())
  }
  builder.to_string()
}

///|
fn parse_sexpr(reader : TextReader) -> SExpr raise ComponentTextError {
  reader.skip_ws_and_comments()
  let first = reader.peek_char()
  if first is None {
    raise ParseError("unexpected end of input")
  }
  if first == Some('(') {
    reader.next_char() |> ignore
    let list : Array[SExpr] = []
    while true {
      reader.skip_ws_and_comments()
      let next = reader.peek_char()
      if next is None {
        raise ParseError("unterminated list")
      }
      if next == Some(')') {
        reader.next_char() |> ignore
        return List(list)
      }
      list.push(parse_sexpr(reader))
    }
  }
  if first == Some(')') {
    raise ParseError("unexpected ')'")
  }
  if first == Some('"') {
    return Str(reader.read_string())
  }
  Atom(reader.read_atom())
}

///|
priv struct FuncParam {
  label : String
  type_opcode : Int
} derive(Eq)

///|
priv struct FuncTypeSig {
  params : Array[FuncParam]
  result_opcode : Int?
} derive(Eq)

///|
priv struct ImportEntry {
  name : String
  desc : Bytes
}

///|
priv struct TypeEntry {
  bytes : Bytes
  func_sig : FuncTypeSig?
}

///|
priv struct ExportEntry {
  name : String
  sort_tag : Int
  idx : Int
  desc : Bytes?
}

///|
priv struct NamedBinding {
  name : String
  idx : Int
}

///|
priv struct CoreInstanceEntry {
  module_idx : Int
}

///|
priv struct AliasEntry {
  kind : Int
  instance_idx : Int
  name : String
}

///|
priv struct CoreAliasBinding {
  kind : Int
  instance_idx : Int
  name : String
  idx : Int
}

///|
priv struct ComponentBuildState {
  types : Array[TypeEntry]
  imports : Array[ImportEntry]
  exports : Array[ExportEntry]
  nested_components : Array[Bytes]
  core_modules : Array[Bytes]
  core_instances : Array[CoreInstanceEntry]
  aliases : Array[AliasEntry]
  canons : Array[Bytes]
  type_names : Array[NamedBinding]
  core_module_names : Array[NamedBinding]
  core_instance_names : Array[NamedBinding]
  func_names : Array[NamedBinding]
  core_alias_bindings : Array[CoreAliasBinding]
  mut next_func_idx : Int
  mut next_core_module_idx : Int
  mut next_core_instance_idx : Int
  mut next_core_func_idx : Int
  mut next_core_memory_idx : Int
}

///|
fn ComponentBuildState::new() -> ComponentBuildState {
  {
    types: [],
    imports: [],
    exports: [],
    nested_components: [],
    core_modules: [],
    core_instances: [],
    aliases: [],
    canons: [],
    type_names: [],
    core_module_names: [],
    core_instance_names: [],
    func_names: [],
    core_alias_bindings: [],
    next_func_idx: 0,
    next_core_module_idx: 0,
    next_core_instance_idx: 0,
    next_core_func_idx: 0,
    next_core_memory_idx: 0,
  }
}

///|
priv struct ByteBuf {
  bytes : Array[Byte]
}

///|
fn ByteBuf::new() -> ByteBuf {
  { bytes: [] }
}

///|
fn ByteBuf::push_u8(self : ByteBuf, value : Int) -> Unit {
  self.bytes.push(value.to_byte())
}

///|
fn ByteBuf::push_bytes(self : ByteBuf, data : Bytes) -> Unit {
  for byte in data {
    self.bytes.push(byte)
  }
}

///|
fn ByteBuf::push_uleb_u32(self : ByteBuf, value : Int) -> Unit {
  let mut remaining = value
  while true {
    let byte_value = remaining & 0x7f
    remaining = remaining >> 7
    if remaining != 0 {
      self.push_u8(byte_value | 0x80)
    } else {
      self.push_u8(byte_value)
      return
    }
  }
}

///|
fn ByteBuf::push_utf8_name(
  self : ByteBuf,
  name : String,
) -> Unit raise ComponentTextError {
  let bytes : Array[Byte] = []
  for ch in name {
    let code = ch.to_int()
    if code < 0 || code > 0x7f {
      raise Unsupported("only ASCII identifiers are supported for now")
    }
    bytes.push(code.to_byte())
  }
  self.push_uleb_u32(bytes.length())
  for byte in bytes {
    self.bytes.push(byte)
  }
}

///|
fn ByteBuf::to_bytes(self : ByteBuf) -> Bytes {
  Bytes::from_array(self.bytes)
}

///|
fn expr_head_atom(expr : SExpr) -> String? {
  if expr is List(items) {
    if items.length() > 0 {
      if items[0] is Atom(name) {
        return Some(name)
      }
    }
  }
  None
}

///|
fn parse_decimal_index(atom : String) -> Int? {
  if atom.length() == 0 {
    return None
  }
  let mut value = 0
  for ch in atom {
    if ch < '0' || ch > '9' {
      return None
    }
    value = value * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(value)
}

///|
fn lookup_named_index(bindings : Array[NamedBinding], name : String) -> Int? {
  for binding in bindings {
    if binding.name == name {
      return Some(binding.idx)
    }
  }
  None
}

///|
fn bind_named_index(
  bindings : Array[NamedBinding],
  name_opt : String?,
  idx : Int,
) -> Unit {
  if name_opt is Some(name) {
    bindings.push({ name, idx })
  }
}

///|
fn parse_name_text(
  expr : SExpr,
  context : String,
) -> String raise ComponentTextError {
  if expr is Str(text) {
    return text
  }
  if expr is Atom(text) {
    return text
  }
  raise Unsupported("\{context} must be a string or atom")
}

///|
fn parse_optional_identifier(field : Array[SExpr], at : Int) -> String? {
  if at < field.length() {
    if field[at] is Atom(name) && name.has_prefix("$") {
      return Some(name)
    }
  }
  None
}

///|
fn resolve_reference(
  expr : SExpr,
  bindings : Array[NamedBinding],
  context : String,
) -> Int raise ComponentTextError {
  if expr is Atom(text) {
    if text.has_prefix("$") {
      if lookup_named_index(bindings, text) is Some(idx) {
        return idx
      }
      return 1_000_000
    }
    if parse_decimal_index(text) is Some(idx) {
      return idx
    }
    raise Unsupported("unsupported \{context} reference '\{text}'")
  }
  raise Unsupported("unsupported \{context} reference")
}

///|
fn int_array_to_bytes(values : Array[Int]) -> Bytes {
  let bytes : Array[Byte] = []
  for value in values {
    bytes.push((value & 0xff).to_byte())
  }
  Bytes::from_array(bytes)
}

///|
fn escape_wat_string(text : String) -> String {
  let out = StringBuilder::new()
  out.write_char('"')
  for ch in text {
    if ch == '"' {
      out.write_string("\\\"")
    } else if ch == '\\' {
      out.write_string("\\\\")
    } else if ch == '\n' {
      out.write_string("\\n")
    } else if ch == '\r' {
      out.write_string("\\r")
    } else if ch == '\t' {
      out.write_string("\\t")
    } else {
      out.write_char(ch)
    }
  }
  out.write_char('"')
  out.to_string()
}

///|
fn sexpr_to_wat(expr : SExpr) -> String {
  match expr {
    Atom(text) => text
    Str(text) => escape_wat_string(text)
    List(items) => {
      let out = StringBuilder::new()
      out.write_char('(')
      for i in 0..<items.length() {
        if i > 0 {
          out.write_char(' ')
        }
        out.write_string(sexpr_to_wat(items[i]))
      }
      out.write_char(')')
      out.to_string()
    }
  }
}

///|
fn prim_type_opcode(name : String) -> Int? {
  match name {
    "bool" => Some(0x7f)
    "s8" => Some(0x7e)
    "u8" => Some(0x7d)
    "s16" => Some(0x7c)
    "u16" => Some(0x7b)
    "s32" => Some(0x7a)
    "u32" => Some(0x79)
    "s64" => Some(0x78)
    "u64" => Some(0x77)
    "f32" => Some(0x76)
    "f64" => Some(0x75)
    "char" => Some(0x74)
    "string" | "str" => Some(0x73)
    _ => None
  }
}

///|
fn parse_valtype(expr : SExpr) -> Int raise ComponentTextError {
  if expr is Atom(name) {
    if prim_type_opcode(name) is Some(opcode) {
      return opcode
    }
    raise Unsupported("unsupported value type '\{name}'")
  }
  raise Unsupported("unsupported non-atom value type")
}

///|
fn parse_func_sig(desc : Array[SExpr]) -> FuncTypeSig raise ComponentTextError {
  let params : Array[FuncParam] = []
  let mut result_opcode : Int? = None
  let mut index = 1
  if index < desc.length() {
    if desc[index] is Atom(name) && name.has_prefix("$") {
      index += 1
    }
  }
  while index < desc.length() {
    let field = desc[index]
    index += 1
    if field is List(items) {
      if items.length() == 0 {
        raise Unsupported("empty func field")
      }
      if items[0] is Atom("param") {
        if items.length() == 2 {
          let type_opcode = parse_valtype(items[1])
          params.push({ label: "p\{params.length()}", type_opcode })
          continue
        }
        if items.length() == 3 {
          let label = if items[1] is Str(name) {
            name
          } else if items[1] is Atom(name) {
            name
          } else {
            raise Unsupported("unsupported param label")
          }
          let type_opcode = parse_valtype(items[2])
          params.push({ label, type_opcode })
          continue
        }
        raise Unsupported("unsupported param field")
      }
      if items[0] is Atom("result") {
        if result_opcode is Some(_) {
          raise Unsupported("multiple result fields are not supported")
        }
        if items.length() == 2 {
          result_opcode = Some(parse_valtype(items[1]))
          continue
        }
        raise Unsupported("unsupported result field")
      }
      raise Unsupported("unsupported func field")
    }
    raise Unsupported("unsupported func declaration item")
  }
  { params, result_opcode }
}

///|
fn encode_func_typedef(sig : FuncTypeSig) -> Bytes raise ComponentTextError {
  let payload = ByteBuf::new()
  payload.push_u8(0x40)
  payload.push_uleb_u32(sig.params.length())
  for param in sig.params {
    payload.push_utf8_name(param.label)
    payload.push_u8(param.type_opcode)
  }
  if sig.result_opcode is Some(opcode) {
    payload.push_u8(0x00)
    payload.push_u8(opcode)
  } else {
    payload.push_u8(0x01)
    payload.push_u8(0x00)
  }
  payload.to_bytes()
}

///|
fn add_type_entry(
  state : ComponentBuildState,
  type_bytes : Bytes,
  func_sig : FuncTypeSig?,
  name_opt : String?,
) -> Int {
  let idx = state.types.length()
  state.types.push({ bytes: type_bytes, func_sig })
  bind_named_index(state.type_names, name_opt, idx)
  idx
}

///|
fn ensure_func_type(
  state : ComponentBuildState,
  sig : FuncTypeSig,
) -> Int raise ComponentTextError {
  for type_index in 0..<state.types.length() {
    let entry = state.types[type_index]
    if entry.func_sig is Some(existing) && existing == sig {
      return type_index
    }
  }
  add_type_entry(state, encode_func_typedef(sig), Some(sig), None)
}

///|
fn parse_type_use(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if field.length() != 2 {
    raise Unsupported("type use must be `(type <index-or-id>)`")
  }
  resolve_reference(field[1], state.type_names, "type")
}

///|
fn parse_import_func_desc(
  desc : Array[SExpr],
  state : ComponentBuildState,
) -> (String?, Int) raise ComponentTextError {
  let mut func_name : String? = None
  let mut type_use : Int? = None
  let filtered : Array[SExpr] = [Atom("func")]

  let mut start = 1
  if parse_optional_identifier(desc, 1) is Some(name) {
    func_name = Some(name)
    filtered.push(Atom(name))
    start = 2
  }
  for i in start..<desc.length() {
    let item = desc[i]
    if item is List(items) && items.length() > 0 && items[0] is Atom("type") {
      type_use = Some(parse_type_use(items, state))
      continue
    }
    filtered.push(item)
  }
  if type_use is Some(idx) {
    return (func_name, idx)
  }
  let sig = parse_func_sig(filtered)
  (func_name, ensure_func_type(state, sig))
}

///|
fn parse_import(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  if field.length() != 3 {
    raise Unsupported("import form currently expects exactly one descriptor")
  }
  let name = parse_name_text(field[1], "import name")
  let desc = if field[2] is List(items) {
    items
  } else {
    raise Unsupported("import descriptor must be a list")
  }
  if desc.length() == 0 {
    raise Unsupported("empty import descriptor")
  }
  if desc[0] is Atom("func") {
    let (func_name, type_idx) = parse_import_func_desc(desc, state)
    state.imports.push({
      name,
      desc: {
        let b = ByteBuf::new()
        b.push_u8(0x01)
        b.push_uleb_u32(type_idx)
        b.to_bytes()
      },
    })
    let func_idx = state.next_func_idx
    state.next_func_idx += 1
    bind_named_index(state.func_names, func_name, func_idx)
    return
  }
  raise Unsupported("unsupported import descriptor")
}

///|
fn encode_type_section(entries : Array[TypeEntry]) -> Bytes {
  let payload = ByteBuf::new()
  payload.push_uleb_u32(entries.length())
  for entry in entries {
    payload.push_bytes(entry.bytes)
  }
  payload.to_bytes()
}

///|
fn encode_import_section(
  imports : Array[ImportEntry],
) -> Bytes raise ComponentTextError {
  let payload = ByteBuf::new()
  payload.push_uleb_u32(imports.length())
  for import_item in imports {
    payload.push_u8(0x00)
    payload.push_utf8_name(import_item.name)
    payload.push_bytes(import_item.desc)
  }
  payload.to_bytes()
}

///|
fn encode_export_section(
  exports : Array[ExportEntry],
) -> Bytes raise ComponentTextError {
  let payload = ByteBuf::new()
  payload.push_uleb_u32(exports.length())
  for export_item in exports {
    payload.push_u8(0x00)
    payload.push_utf8_name(export_item.name)
    payload.push_u8(export_item.sort_tag)
    payload.push_uleb_u32(export_item.idx)
    if export_item.desc is Some(desc) {
      payload.push_u8(0x01)
      payload.push_bytes(desc)
    } else {
      payload.push_u8(0x00)
    }
  }
  payload.to_bytes()
}

///|
fn encode_core_instance_section(instances : Array[CoreInstanceEntry]) -> Bytes {
  let payload = ByteBuf::new()
  payload.push_uleb_u32(instances.length())
  for inst in instances {
    payload.push_u8(0x00)
    payload.push_uleb_u32(inst.module_idx)
    payload.push_uleb_u32(0)
  }
  payload.to_bytes()
}

///|
fn encode_alias_section(
  aliases : Array[AliasEntry],
) -> Bytes raise ComponentTextError {
  let payload = ByteBuf::new()
  payload.push_uleb_u32(aliases.length())
  for alias_entry in aliases {
    payload.push_u8(0x00)
    payload.push_u8(alias_entry.kind)
    payload.push_u8(0x01)
    payload.push_uleb_u32(alias_entry.instance_idx)
    payload.push_utf8_name(alias_entry.name)
  }
  payload.to_bytes()
}

///|
fn encode_canon_section(canon_entries : Array[Bytes]) -> Bytes {
  let payload = ByteBuf::new()
  payload.push_uleb_u32(canon_entries.length())
  for entry in canon_entries {
    payload.push_bytes(entry)
  }
  payload.to_bytes()
}

///|
fn parse_type_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  if field.length() < 2 {
    raise Unsupported("type declaration is missing a body")
  }
  let name_opt = parse_optional_identifier(field, 1)
  let body_index = if name_opt is Some(_) { 2 } else { 1 }
  if body_index >= field.length() {
    raise Unsupported("type declaration is missing a body")
  }
  let body = field[body_index]
  if body is List(items) {
    if items.length() > 0 && items[0] is Atom("func") {
      let sig = parse_func_sig(items)
      add_type_entry(state, encode_func_typedef(sig), Some(sig), name_opt)
      |> ignore
      return
    }
  }
  if body is Atom(name) {
    if prim_type_opcode(name) is Some(opcode) {
      let payload = ByteBuf::new()
      payload.push_u8(opcode)
      add_type_entry(state, payload.to_bytes(), None, name_opt) |> ignore
      return
    }
  }
  raise Unsupported("unsupported type declaration")
}

///|
fn parse_core_alias_binding(
  state : ComponentBuildState,
  kind : Int,
  instance_idx : Int,
  export_name : String,
) -> Int raise ComponentTextError {
  for binding in state.core_alias_bindings {
    if binding.kind == kind &&
      binding.instance_idx == instance_idx &&
      binding.name == export_name {
      return binding.idx
    }
  }
  let idx = if kind == 0x00 {
    let idx = state.next_core_func_idx
    state.next_core_func_idx += 1
    idx
  } else if kind == 0x02 {
    let idx = state.next_core_memory_idx
    state.next_core_memory_idx += 1
    idx
  } else {
    raise Unsupported("unsupported core alias kind \{kind}")
  }
  state.aliases.push({ kind, instance_idx, name: export_name })
  state.core_alias_bindings.push({ kind, instance_idx, name: export_name, idx })
  idx
}

///|
fn parse_core_func_ref(
  expr : SExpr,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  let items = if expr is List(items) {
    items
  } else {
    raise Unsupported("expected `(core func <instance> <export>)`")
  }
  let mut start = 0
  if items.length() >= 2 && items[0] is Atom("core") && items[1] is Atom("func") {
    start = 2
  } else if items.length() >= 1 && items[0] is Atom("func") {
    start = 1
  } else {
    raise Unsupported("unsupported function reference")
  }
  if start + 2 != items.length() {
    raise Unsupported("function reference must have instance and export name")
  }
  let instance_idx = resolve_reference(
    items[start],
    state.core_instance_names,
    "core instance",
  )
  let export_name = parse_name_text(items[start + 1], "core export name")
  parse_core_alias_binding(state, 0x00, instance_idx, export_name)
}

///|
fn parse_memory_opt(
  opt_items : Array[SExpr],
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if opt_items.length() != 3 {
    raise Unsupported("memory option must be `(memory <instance> <export>)`")
  }
  let instance_idx = resolve_reference(
    opt_items[1],
    state.core_instance_names,
    "core instance",
  )
  let export_name = parse_name_text(opt_items[2], "memory export name")
  parse_core_alias_binding(state, 0x02, instance_idx, export_name)
}

///|
fn parse_canon_lift(
  canon_items : Array[SExpr],
  state : ComponentBuildState,
  type_idx : Int,
) -> Bytes raise ComponentTextError {
  if canon_items.length() < 3 {
    raise Unsupported("`canon lift` requires a core function reference")
  }
  let core_func_idx = parse_core_func_ref(canon_items[2], state)
  let opt_body = ByteBuf::new()
  let mut opt_count = 0
  for i in 3..<canon_items.length() {
    let opt_items = if canon_items[i] is List(items) {
      items
    } else {
      raise Unsupported("canonical options must be lists")
    }
    if opt_items.length() == 0 {
      raise Unsupported("empty canonical option")
    }
    if opt_items[0] is Atom("memory") {
      let mem_idx = parse_memory_opt(opt_items, state)
      opt_body.push_u8(0x03)
      opt_body.push_uleb_u32(mem_idx)
      opt_count += 1
      continue
    }
    if opt_items[0] is Atom("realloc") {
      if opt_items.length() != 3 {
        raise Unsupported(
          "realloc option must be `(realloc <instance> <export>)`",
        )
      }
      let instance_idx = resolve_reference(
        opt_items[1],
        state.core_instance_names,
        "core instance",
      )
      let export_name = parse_name_text(opt_items[2], "realloc export name")
      let func_idx = parse_core_alias_binding(
        state, 0x00, instance_idx, export_name,
      )
      opt_body.push_u8(0x04)
      opt_body.push_uleb_u32(func_idx)
      opt_count += 1
      continue
    }
    if opt_items[0] is Atom("post-return") {
      let post_func_idx = if opt_items.length() == 2 && opt_items[1] is List(_) {
        parse_core_func_ref(opt_items[1], state)
      } else if opt_items.length() == 3 {
        let instance_idx = resolve_reference(
          opt_items[1],
          state.core_instance_names,
          "core instance",
        )
        let export_name = parse_name_text(
          opt_items[2],
          "post-return export name",
        )
        parse_core_alias_binding(state, 0x00, instance_idx, export_name)
      } else {
        raise Unsupported(
          "post-return option must be `(post-return (func ...))` or `(post-return <instance> <export>)`",
        )
      }
      opt_body.push_u8(0x05)
      opt_body.push_uleb_u32(post_func_idx)
      opt_count += 1
      continue
    }
    if opt_items.length() == 1 && opt_items[0] is Atom(name) {
      if name == "string-encoding=utf8" {
        opt_body.push_u8(0x00)
        opt_count += 1
        continue
      }
      if name == "string-encoding=utf16" {
        opt_body.push_u8(0x01)
        opt_count += 1
        continue
      }
      if name == "string-encoding=latin1+utf16" {
        opt_body.push_u8(0x02)
        opt_count += 1
        continue
      }
    }
    raise Unsupported("unsupported canonical option")
  }

  let out = ByteBuf::new()
  out.push_u8(0x00)
  out.push_u8(0x00)
  out.push_uleb_u32(core_func_idx)
  out.push_uleb_u32(opt_count)
  out.push_bytes(opt_body.to_bytes())
  out.push_uleb_u32(type_idx)
  out.to_bytes()
}

///|
fn parse_func_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  let name_opt = parse_optional_identifier(field, 1)
  let mut index = if name_opt is Some(_) { 2 } else { 1 }
  let exports : Array[String] = []
  let sig_items : Array[SExpr] = [Atom("func")]
  if name_opt is Some(name) {
    sig_items.push(Atom(name))
  }
  let mut type_idx_opt : Int? = None
  let mut canon_items_opt : Array[SExpr]? = None

  while index < field.length() {
    let item = field[index]
    index += 1
    let list = if item is List(items) {
      items
    } else {
      raise Unsupported("unsupported function declaration item")
    }
    if list.length() == 0 {
      raise Unsupported("empty function declaration item")
    }
    if list[0] is Atom("export") {
      if list.length() != 2 {
        raise Unsupported("function export must be `(export <name>)`")
      }
      exports.push(parse_name_text(list[1], "function export name"))
      continue
    }
    if list[0] is Atom("type") {
      type_idx_opt = Some(parse_type_use(list, state))
      continue
    }
    if list[0] is Atom("canon") {
      canon_items_opt = Some(list)
      continue
    }
    sig_items.push(item)
  }

  let type_idx = if type_idx_opt is Some(type_idx) {
    type_idx
  } else {
    let sig = parse_func_sig(sig_items)
    ensure_func_type(state, sig)
  }

  let canon_items = match canon_items_opt {
    Some(items) => items
    None =>
      raise Unsupported(
        "function body currently requires a canonical declaration",
      )
  }
  if canon_items.length() < 2 || !(canon_items[0] is Atom("canon")) {
    raise Unsupported("unsupported canonical declaration")
  }
  if !(canon_items[1] is Atom("lift")) {
    raise Unsupported("only `canon lift` is supported in function declarations")
  }

  let func_idx = state.next_func_idx
  state.next_func_idx += 1
  bind_named_index(state.func_names, name_opt, func_idx)

  let canon_bytes = parse_canon_lift(canon_items, state, type_idx)
  state.canons.push(canon_bytes)

  for export_name in exports {
    state.exports.push({
      name: export_name,
      sort_tag: 0x01,
      idx: func_idx,
      desc: None,
    })
  }
}

///|
fn parse_export_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  if field.length() != 3 {
    raise Unsupported("export form expects `(export <name> <desc>)`")
  }
  let name = parse_name_text(field[1], "export name")
  let desc = if field[2] is List(items) {
    items
  } else {
    raise Unsupported("export descriptor must be a list")
  }
  if desc.length() < 2 {
    raise Unsupported("export descriptor is incomplete")
  }
  if desc[0] is Atom("func") {
    let idx = resolve_reference(desc[1], state.func_names, "function")
    state.exports.push({ name, sort_tag: 0x01, idx, desc: None })
    return
  }
  raise Unsupported("unsupported export descriptor")
}

///|
fn parse_core_module_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  let name_opt = parse_optional_identifier(field, 2)
  let start = if name_opt is Some(_) { 3 } else { 2 }
  let module_items : Array[SExpr] = [Atom("module")]
  for i in start..<field.length() {
    module_items.push(field[i])
  }
  let module_text = sexpr_to_wat(List(module_items))
  let mod = @wat.parse(module_text) catch {
    e => raise ParseError("failed to parse core module: \{e}")
  }
  let bytes = int_array_to_bytes(@cwasm.encode(mod))
  state.core_modules.push(bytes)
  let idx = state.next_core_module_idx
  state.next_core_module_idx += 1
  bind_named_index(state.core_module_names, name_opt, idx)
}

///|
fn parse_core_instance_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  if field.length() < 3 {
    raise Unsupported("core instance declaration is incomplete")
  }
  let name_opt = parse_optional_identifier(field, 2)
  let expr_index = if name_opt is Some(_) { 3 } else { 2 }
  if expr_index >= field.length() {
    raise Unsupported("core instance declaration is missing an expression")
  }
  let expr = if field[expr_index] is List(items) {
    items
  } else {
    raise Unsupported("core instance expression must be a list")
  }
  if expr.length() < 2 || !(expr[0] is Atom("instantiate")) {
    raise Unsupported("only `(instantiate ...)` core instances are supported")
  }
  if expr.length() > 2 {
    raise Unsupported(
      "core instance instantiate arguments are not supported yet",
    )
  }
  let module_idx = resolve_reference(
    expr[1],
    state.core_module_names,
    "core module",
  )
  state.core_instances.push({ module_idx, })
  let idx = state.next_core_instance_idx
  state.next_core_instance_idx += 1
  bind_named_index(state.core_instance_names, name_opt, idx)
}

///|
fn parse_core_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  if field.length() < 2 {
    raise Unsupported("empty core declaration")
  }
  if field[1] is Atom("module") {
    parse_core_module_field(field, state)
    return
  }
  if field[1] is Atom("instance") {
    parse_core_instance_field(field, state)
    return
  }
  raise Unsupported("unsupported core declaration")
}

///|
fn append_section(output : ByteBuf, section_id : Int, payload : Bytes) -> Unit {
  output.push_u8(section_id)
  output.push_uleb_u32(payload.length())
  output.push_bytes(payload)
}

///|
fn compile_component_expr(
  expr : Array[SExpr],
) -> Bytes raise ComponentTextError {
  if expr.length() == 0 {
    raise ParseError("empty list is not a component")
  }
  if !(expr[0] is Atom("component")) {
    raise ParseError("expected (component ...)")
  }

  let mut field_index = 1
  if field_index < expr.length() {
    if expr[field_index] is Atom(name) && name.has_prefix("$") {
      field_index += 1
    }
  }

  let state = ComponentBuildState::new()

  for index in field_index..<expr.length() {
    let field_expr = expr[index]
    let field = if field_expr is List(items) {
      items
    } else {
      raise Unsupported("component fields must be lists")
    }
    if field.length() == 0 {
      raise Unsupported("empty component field")
    }
    if field[0] is Atom("import") {
      parse_import(field, state)
      continue
    }
    if field[0] is Atom("component") {
      state.nested_components.push(compile_component_expr(field))
      continue
    }
    if field[0] is Atom("type") {
      parse_type_field(field, state)
      continue
    }
    if field[0] is Atom("core") {
      parse_core_field(field, state)
      continue
    }
    if field[0] is Atom("func") {
      parse_func_field(field, state)
      continue
    }
    if field[0] is Atom("export") {
      parse_export_field(field, state)
      continue
    }
    let head_name = match expr_head_atom(field_expr) {
      Some(name) => name
      None => "<unknown>"
    }
    raise Unsupported("unsupported component field '\{head_name}'")
  }

  let out = ByteBuf::new()
  out.push_u8(0x00)
  out.push_u8(0x61)
  out.push_u8(0x73)
  out.push_u8(0x6d)
  out.push_u8(0x0d)
  out.push_u8(0x00)
  out.push_u8(0x01)
  out.push_u8(0x00)

  for core_module in state.core_modules {
    append_section(out, 1, core_module)
  }
  if state.core_instances.length() > 0 {
    append_section(out, 2, encode_core_instance_section(state.core_instances))
  }
  for nested in state.nested_components {
    append_section(out, 4, nested)
  }
  if state.aliases.length() > 0 {
    append_section(out, 6, encode_alias_section(state.aliases))
  }
  if state.types.length() > 0 {
    append_section(out, 7, encode_type_section(state.types))
  }
  if state.canons.length() > 0 {
    append_section(out, 8, encode_canon_section(state.canons))
  }
  if state.imports.length() > 0 {
    append_section(out, 10, encode_import_section(state.imports))
  }
  if state.exports.length() > 0 {
    append_section(out, 11, encode_export_section(state.exports))
  }

  out.to_bytes()
}

///|
fn keep_wbtest_imports_used() -> Unit {
  if false {
    let empty = Bytes::from_array([])
    ignore(@component.sniff_binary_kind(empty))
    ignore(@component_model.ComponentValidationConfig::new(true))
  }
}

///|
pub fn parse_component_wat(input : String) -> Bytes raise ComponentTextError {
  keep_wbtest_imports_used()
  let reader = TextReader::new(input)
  let root = parse_sexpr(reader)
  reader.skip_ws_and_comments()
  if !reader.is_eof() {
    raise ParseError("trailing tokens after component form")
  }
  if root is List(items) {
    compile_component_expr(items)
  } else {
    raise ParseError("expected a single (component ...) form")
  }
}
