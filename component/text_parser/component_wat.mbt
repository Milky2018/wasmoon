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
priv enum ValTypeEncoding {
  Prim(Int)
  TypeIdx(Int)
} derive(Eq)

///|
priv struct FuncParam {
  label : String
  ty : ValTypeEncoding
} derive(Eq)

///|
priv struct FuncTypeSig {
  params : Array[FuncParam]
  result_ty : ValTypeEncoding?
  is_async : Bool
} derive(Eq)

///|
priv struct ImportEntry {
  name : String
  desc : Bytes
}

///|
priv struct TypeEntry {
  idx : Int
  bytes : Bytes
  func_sig : FuncTypeSig?
}

///|
priv struct CoreTypeEntry {
  idx : Int
  bytes : Bytes
}

///|
priv struct ExportEntry {
  name : String
  sort_tag : Int
  core_kind : Int?
  idx : Int
  desc : Bytes?
}

///|
priv struct NamedBinding {
  name : String
  idx : Int
}

///|
priv struct CoreAliasBinding {
  kind : Int
  instance_idx : Int
  name : String
  idx : Int
}

///|
priv struct SectionChunk {
  section_id : Int
  payload : Bytes
}

///|
priv struct CoreSortRef {
  name : String
  kind : Int
  idx : Int
}

///|
priv struct AliasSortSpec {
  sort_tag : Int
  core_kind : Int?
  name_opt : String?
}

///|
priv enum CoreInstanceExprEntry {
  Instantiate(Int, Array[CoreSortRef])
  InlineExports(Array[CoreSortRef])
}

///|
priv struct CoreInstanceEntry {
  expr : CoreInstanceExprEntry
}

///|
priv struct SortRef {
  name : String
  sort_tag : Int
  core_kind : Int?
  idx : Int
}

///|
priv enum InstanceExprEntry {
  Instantiate(Int, Array[SortRef])
  InlineExports(Array[SortRef])
}

///|
priv struct InstanceEntry {
  expr : InstanceExprEntry
}

///|
priv struct ComponentBuildState {
  types : Array[TypeEntry]
  imports : Array[ImportEntry]
  exports : Array[ExportEntry]
  nested_components : Array[Bytes]
  core_types : Array[CoreTypeEntry]
  sections_ordered : Array[SectionChunk]
  type_names : Array[NamedBinding]
  core_type_names : Array[NamedBinding]
  core_module_names : Array[NamedBinding]
  core_instance_names : Array[NamedBinding]
  component_names : Array[NamedBinding]
  instance_names : Array[NamedBinding]
  func_names : Array[NamedBinding]
  core_func_names : Array[NamedBinding]
  core_table_names : Array[NamedBinding]
  core_memory_names : Array[NamedBinding]
  core_global_names : Array[NamedBinding]
  core_tag_names : Array[NamedBinding]
  core_alias_bindings : Array[CoreAliasBinding]
  outer_type_scopes : Array[Array[NamedBinding]]
  outer_core_type_scopes : Array[Array[NamedBinding]]
  outer_component_scopes : Array[Array[NamedBinding]]
  outer_core_module_scopes : Array[Array[NamedBinding]]
  mut next_type_idx : Int
  mut next_func_idx : Int
  mut next_core_type_idx : Int
  mut next_core_module_idx : Int
  mut next_core_instance_idx : Int
  mut next_component_idx : Int
  mut next_instance_idx : Int
  mut next_core_func_idx : Int
  mut next_core_table_idx : Int
  mut next_core_memory_idx : Int
  mut next_core_global_idx : Int
  mut next_core_tag_idx : Int
}

///|
fn ComponentBuildState::new(
  outer_type_scopes : Array[Array[NamedBinding]],
  outer_core_type_scopes : Array[Array[NamedBinding]],
  outer_component_scopes : Array[Array[NamedBinding]],
  outer_core_module_scopes : Array[Array[NamedBinding]],
) -> ComponentBuildState {
  {
    types: [],
    imports: [],
    exports: [],
    nested_components: [],
    core_types: [],
    sections_ordered: [],
    type_names: [],
    core_type_names: [],
    core_module_names: [],
    core_instance_names: [],
    component_names: [],
    instance_names: [],
    func_names: [],
    core_func_names: [],
    core_table_names: [],
    core_memory_names: [],
    core_global_names: [],
    core_tag_names: [],
    core_alias_bindings: [],
    outer_type_scopes,
    outer_core_type_scopes,
    outer_component_scopes,
    outer_core_module_scopes,
    next_type_idx: 0,
    next_func_idx: 0,
    next_core_type_idx: 0,
    next_core_module_idx: 0,
    next_core_instance_idx: 0,
    next_component_idx: 0,
    next_instance_idx: 0,
    next_core_func_idx: 0,
    next_core_table_idx: 0,
    next_core_memory_idx: 0,
    next_core_global_idx: 0,
    next_core_tag_idx: 0,
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
fn ByteBuf::push_sleb_i32(self : ByteBuf, value : Int) -> Unit {
  let mut remaining = value
  let mut has_more = true
  while has_more {
    let mut byte_value = remaining & 0x7f
    remaining = remaining >> 7
    let sign_bit_set = (byte_value & 0x40) != 0
    if (remaining == 0 && !sign_bit_set) || (remaining == -1 && sign_bit_set) {
      has_more = false
    } else {
      byte_value = byte_value | 0x80
    }
    self.push_u8(byte_value)
  }
}

///|
fn ByteBuf::push_utf8_name(self : ByteBuf, name : String) -> Unit {
  let bytes : Array[Byte] = []
  for ch in name {
    let cp = ch.to_int()
    if cp < 0x80 {
      bytes.push(cp.to_byte())
    } else if cp < 0x800 {
      bytes.push((0xC0 | (cp >> 6)).to_byte())
      bytes.push((0x80 | (cp & 0x3F)).to_byte())
    } else if cp < 0x10000 {
      bytes.push((0xE0 | (cp >> 12)).to_byte())
      bytes.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      bytes.push((0xF0 | (cp >> 18)).to_byte())
      bytes.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
      bytes.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 | (cp & 0x3F)).to_byte())
    }
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
  let mut i = bindings.length()
  while i > 0 {
    i -= 1
    let binding = bindings[i]
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
fn copy_named_bindings(bindings : Array[NamedBinding]) -> Array[NamedBinding] {
  let out : Array[NamedBinding] = []
  for binding in bindings {
    out.push({ name: binding.name, idx: binding.idx })
  }
  out
}

///|
fn add_unique_ref_name(names : Array[String], name : String) -> Unit {
  for existing in names {
    if existing == name {
      return
    }
  }
  names.push(name)
}

///|
fn collect_dollar_atom_names(expr : SExpr, names : Array[String]) -> Unit {
  if expr is Atom(name) {
    if name.has_prefix("$") {
      add_unique_ref_name(names, name)
    }
    return
  }
  if expr is List(items) {
    for item in items {
      collect_dollar_atom_names(item, names)
    }
  }
}

///|
fn collect_inline_ref_names(desc : Array[SExpr], start : Int) -> Array[String] {
  let names : Array[String] = []
  for i in start..<desc.length() {
    collect_dollar_atom_names(desc[i], names)
  }
  names
}

///|
fn contains_ref_name(names : Array[String], name : String) -> Bool {
  for candidate in names {
    if candidate == name {
      return true
    }
  }
  false
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
  if expr is List(items) {
    if items.length() == 2 && items[0] is Atom("interface") {
      if items[1] is Str(text) {
        return text
      }
      if items[1] is Atom(text) {
        return text
      }
      raise Unsupported("\{context} interface name must be a string or atom")
    }
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
      raise Unsupported("unknown \{context} reference '\{text}'")
    }
    if parse_decimal_index(text) is Some(idx) {
      return idx
    }
    raise Unsupported("unsupported \{context} reference '\{text}'")
  }
  raise Unsupported("unsupported \{context} reference")
}

///|
fn resolve_type_reference(
  expr : SExpr,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if expr is Atom(name) && name.has_prefix("$") {
    if lookup_named_index(state.type_names, name) is Some(idx) {
      return idx
    }
    for depth in 0..<state.outer_type_scopes.length() {
      if lookup_named_index(state.outer_type_scopes[depth], name)
        is Some(outer_idx) {
        let alias_idx = allocate_alias_index(state, 0x03, None, Some(name))
        push_ordered_section(
          state,
          6,
          encode_alias_outer_decl(0x03, None, depth + 1, outer_idx),
        )
        return alias_idx
      }
    }
  }
  resolve_reference(expr, state.type_names, "type")
}

///|
fn resolve_component_reference(
  expr : SExpr,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if expr is Atom(name) && name.has_prefix("$") {
    if lookup_named_index(state.component_names, name) is Some(idx) {
      return idx
    }
    for depth in 0..<state.outer_component_scopes.length() {
      if lookup_named_index(state.outer_component_scopes[depth], name)
        is Some(outer_idx) {
        let alias_idx = allocate_alias_index(state, 0x04, None, Some(name))
        push_ordered_section(
          state,
          6,
          encode_alias_outer_decl(0x04, None, depth + 1, outer_idx),
        )
        return alias_idx
      }
    }
    raise Unsupported("unknown component reference '\{name}'")
  }
  resolve_reference(expr, state.component_names, "component")
}

///|
fn resolve_core_type_reference(
  expr : SExpr,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if expr is Atom(name) && name.has_prefix("$") {
    if lookup_named_index(state.core_type_names, name) is Some(idx) {
      return idx
    }
    for depth in 0..<state.outer_core_type_scopes.length() {
      if lookup_named_index(state.outer_core_type_scopes[depth], name)
        is Some(outer_idx) {
        let alias_idx = allocate_alias_index(
          state,
          0x00,
          Some(0x05),
          Some(name),
        )
        push_ordered_section(
          state,
          6,
          encode_alias_outer_decl(0x00, Some(0x05), depth + 1, outer_idx),
        )
        return alias_idx
      }
    }
    raise Unsupported("unknown core type reference '\{name}'")
  }
  resolve_reference(expr, state.core_type_names, "core type")
}

///|
fn resolve_core_module_reference(
  expr : SExpr,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if expr is Atom(name) && name.has_prefix("$") {
    if lookup_named_index(state.core_module_names, name) is Some(idx) {
      return idx
    }
    for depth in 0..<state.outer_core_module_scopes.length() {
      if lookup_named_index(state.outer_core_module_scopes[depth], name)
        is Some(outer_idx) {
        let alias_idx = allocate_alias_index(
          state,
          0x00,
          Some(0x11),
          Some(name),
        )
        push_ordered_section(
          state,
          6,
          encode_alias_outer_decl(0x00, Some(0x11), depth + 1, outer_idx),
        )
        return alias_idx
      }
    }
    raise Unsupported("unknown core module reference '\{name}'")
  }
  resolve_reference(expr, state.core_module_names, "core module")
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
    "f32" | "float32" => Some(0x76)
    "f64" | "float64" => Some(0x75)
    "char" => Some(0x74)
    "string" | "str" => Some(0x73)
    _ => None
  }
}

///|
fn push_valtype_encoding(payload : ByteBuf, ty : ValTypeEncoding) -> Unit {
  match ty {
    Prim(opcode) => payload.push_u8(opcode)
    TypeIdx(idx) => payload.push_uleb_u32(idx)
  }
}

///|
fn parse_valtype(
  expr : SExpr,
  state : ComponentBuildState,
) -> ValTypeEncoding raise ComponentTextError {
  if expr is Atom(name) {
    if prim_type_opcode(name) is Some(opcode) {
      return Prim(opcode)
    }
    if name.has_prefix("$") || parse_decimal_index(name) is Some(_) {
      let idx = resolve_type_reference(expr, state)
      return TypeIdx(idx)
    }
    raise Unsupported("unsupported value type '\{name}'")
  }
  if expr is List(items) {
    if items.length() == 2 && items[0] is Atom("type") {
      return TypeIdx(resolve_type_reference(items[1], state))
    }
    if items.length() == 2 && items[0] is Atom("list") {
      let elem = parse_valtype(items[1], state)
      let payload = ByteBuf::new()
      payload.push_u8(0x70)
      push_valtype_encoding(payload, elem)
      let idx = ensure_type_bytes(state, payload.to_bytes())
      return TypeIdx(idx)
    }
    if items.length() == 2 && items[0] is Atom("option") {
      let inner = parse_valtype(items[1], state)
      let payload = ByteBuf::new()
      payload.push_u8(0x6b)
      push_valtype_encoding(payload, inner)
      let idx = ensure_type_bytes(state, payload.to_bytes())
      return TypeIdx(idx)
    }
    if items.length() == 2 && items[0] is Atom("own") {
      let target_idx = resolve_type_reference(items[1], state)
      let payload = ByteBuf::new()
      payload.push_u8(0x69)
      payload.push_uleb_u32(target_idx)
      let idx = ensure_type_bytes(state, payload.to_bytes())
      return TypeIdx(idx)
    }
    if items.length() == 2 && items[0] is Atom("borrow") {
      let target_idx = resolve_type_reference(items[1], state)
      let payload = ByteBuf::new()
      payload.push_u8(0x68)
      payload.push_uleb_u32(target_idx)
      let idx = ensure_type_bytes(state, payload.to_bytes())
      return TypeIdx(idx)
    }
    if items.length() > 0 && items[0] is Atom("record") {
      return TypeIdx(
        ensure_type_bytes(state, parse_record_type_bytes(items, state)),
      )
    }
    if items.length() > 0 && items[0] is Atom("variant") {
      return TypeIdx(
        ensure_type_bytes(state, parse_variant_type_bytes(items, state)),
      )
    }
    if items.length() > 0 && items[0] is Atom("tuple") {
      return TypeIdx(
        ensure_type_bytes(state, parse_tuple_type_bytes(items, state)),
      )
    }
    if items.length() > 0 && items[0] is Atom("flags") {
      return TypeIdx(
        ensure_type_bytes(state, parse_flags_or_enum_type_bytes(0x6e, items)),
      )
    }
    if items.length() > 0 && items[0] is Atom("enum") {
      return TypeIdx(
        ensure_type_bytes(state, parse_flags_or_enum_type_bytes(0x6d, items)),
      )
    }
    if items.length() > 0 && items[0] is Atom("result") {
      return TypeIdx(
        ensure_type_bytes(state, parse_result_type_bytes(items, state)),
      )
    }
    if items.length() > 0 && items[0] is Atom("future") {
      return TypeIdx(
        ensure_type_bytes(
          state,
          parse_future_or_stream_type_bytes(0x65, items, state),
        ),
      )
    }
    if items.length() > 0 && items[0] is Atom("stream") {
      return TypeIdx(
        ensure_type_bytes(
          state,
          parse_future_or_stream_type_bytes(0x66, items, state),
        ),
      )
    }
    raise Unsupported("unsupported non-atom value type")
  }
  raise Unsupported("unsupported non-atom value type")
}

///|
fn parse_func_sig(
  desc : Array[SExpr],
  state : ComponentBuildState,
) -> FuncTypeSig raise ComponentTextError {
  let params : Array[FuncParam] = []
  let mut result_ty : ValTypeEncoding? = None
  let mut is_async = false
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
          let ty = parse_valtype(items[1], state)
          params.push({ label: "p\{params.length()}", ty })
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
          let ty = parse_valtype(items[2], state)
          params.push({ label, ty })
          continue
        }
        raise Unsupported("unsupported param field")
      }
      if items[0] is Atom("result") {
        if result_ty is Some(_) {
          raise Unsupported("multiple result fields are not supported")
        }
        if items.length() == 2 {
          result_ty = Some(parse_valtype(items[1], state))
          continue
        }
        raise Unsupported("unsupported result field")
      }
      raise Unsupported("unsupported func field")
    }
    if field is Atom("async") {
      is_async = true
      continue
    }
    raise Unsupported("unsupported func declaration item")
  }
  { params, result_ty, is_async }
}

///|
fn encode_func_typedef(sig : FuncTypeSig) -> Bytes {
  let payload = ByteBuf::new()
  payload.push_u8(if sig.is_async { 0x43 } else { 0x40 })
  payload.push_uleb_u32(sig.params.length())
  for param in sig.params {
    payload.push_utf8_name(param.label)
    push_valtype_encoding(payload, param.ty)
  }
  if sig.result_ty is Some(ty) {
    payload.push_u8(0x00)
    push_valtype_encoding(payload, ty)
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
  let idx = state.next_type_idx
  state.next_type_idx += 1
  state.types.push({ idx, bytes: type_bytes, func_sig })
  push_ordered_section(state, 7, type_bytes)
  bind_named_index(state.type_names, name_opt, idx)
  idx
}

///|
fn ensure_func_type(state : ComponentBuildState, sig : FuncTypeSig) -> Int {
  for type_index in 0..<state.types.length() {
    let entry = state.types[type_index]
    if entry.func_sig is Some(existing) && existing == sig {
      return entry.idx
    }
  }
  add_type_entry(state, encode_func_typedef(sig), Some(sig), None)
}

///|
fn ensure_type_bytes(state : ComponentBuildState, type_bytes : Bytes) -> Int {
  for i in 0..<state.types.length() {
    if state.types[i].bytes == type_bytes {
      return state.types[i].idx
    }
  }
  add_type_entry(state, type_bytes, None, None)
}

///|
fn ensure_core_type_bytes(
  state : ComponentBuildState,
  type_bytes : Bytes,
) -> Int {
  for i in 0..<state.core_types.length() {
    if state.core_types[i].bytes == type_bytes {
      return state.core_types[i].idx
    }
  }
  let idx = state.next_core_type_idx
  state.next_core_type_idx += 1
  state.core_types.push({ idx, bytes: type_bytes })
  push_ordered_section(state, 3, type_bytes)
  idx
}

///|
fn ensure_empty_component_type(state : ComponentBuildState) -> Int {
  let payload = ByteBuf::new()
  payload.push_u8(0x41)
  payload.push_uleb_u32(0)
  ensure_type_bytes(state, payload.to_bytes())
}

///|
fn ensure_empty_instance_type(state : ComponentBuildState) -> Int {
  let payload = ByteBuf::new()
  payload.push_u8(0x42)
  payload.push_uleb_u32(0)
  ensure_type_bytes(state, payload.to_bytes())
}

///|
fn ensure_empty_core_module_type(state : ComponentBuildState) -> Int {
  let payload = ByteBuf::new()
  payload.push_u8(0x50)
  payload.push_u8(0x00)
  ensure_core_type_bytes(state, payload.to_bytes())
}

///|
fn parse_type_use(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if field.length() != 2 {
    raise Unsupported("type use must be `(type <index-or-id>)`")
  }
  resolve_type_reference(field[1], state)
}

///|
fn parse_core_type_use(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if field.length() != 2 {
    raise Unsupported("core type use must be `(type <index-or-id>)`")
  }
  let ref_expr = field[1]
  if ref_expr is Atom(name) && name.has_prefix("$") {
    if lookup_named_index(state.core_type_names, name) is Some(idx) {
      return idx
    }
    for depth in 0..<state.outer_core_type_scopes.length() {
      if lookup_named_index(state.outer_core_type_scopes[depth], name)
        is Some(outer_idx) {
        let alias_idx = allocate_alias_index(
          state,
          0x00,
          Some(0x05),
          Some(name),
        )
        push_ordered_section(
          state,
          6,
          encode_alias_outer_decl(0x00, Some(0x05), depth + 1, outer_idx),
        )
        return alias_idx
      }
    }
    raise Unsupported("unknown core type reference '\{name}'")
  }
  resolve_reference(ref_expr, state.core_type_names, "core type")
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
  let sig = parse_func_sig(filtered, state)
  (func_name, ensure_func_type(state, sig))
}

///|
fn resolve_inline_type_ref(
  expr : SExpr,
  state : ComponentBuildState,
  local_type_names : Array[NamedBinding],
) -> Int raise ComponentTextError {
  if expr is Atom(name) && name.has_prefix("$") {
    if lookup_named_index(local_type_names, name) is Some(idx) {
      return idx
    }
  }
  resolve_type_reference(expr, state)
}

///|
fn parse_type_use_inline(
  field : Array[SExpr],
  state : ComponentBuildState,
  local_type_names : Array[NamedBinding],
) -> Int raise ComponentTextError {
  if field.length() != 2 {
    raise Unsupported("type use must be `(type <index-or-id>)`")
  }
  resolve_inline_type_ref(field[1], state, local_type_names)
}

///|
fn parse_type_bound_bytes_inline(
  bound_expr : SExpr,
  state : ComponentBuildState,
  local_type_names : Array[NamedBinding],
) -> Bytes raise ComponentTextError {
  let bound = if bound_expr is List(items) {
    items
  } else {
    raise Unsupported("type bound must be a list")
  }
  if bound.length() == 2 && bound[0] is Atom("eq") {
    let idx = resolve_inline_type_ref(bound[1], state, local_type_names)
    let bytes = ByteBuf::new()
    bytes.push_u8(0x00)
    bytes.push_uleb_u32(idx)
    return bytes.to_bytes()
  }
  if bound.length() == 2 &&
    bound[0] is Atom("sub") &&
    bound[1] is Atom("resource") {
    return Bytes::from_array([0x01])
  }
  raise Unsupported("unsupported type bound")
}

///|
fn parse_inline_valtype_encoding(
  expr : SExpr,
  state : ComponentBuildState,
  decls : ByteBuf,
  local_type_count : Int,
  local_type_names : Array[NamedBinding],
) -> (ValTypeEncoding, Int, Int) raise ComponentTextError {
  if expr is Atom(name) {
    if prim_type_opcode(name) is Some(opcode) {
      return (Prim(opcode), local_type_count, 0)
    }
    if name.has_prefix("$") || parse_decimal_index(name) is Some(_) {
      return (
        TypeIdx(resolve_inline_type_ref(expr, state, local_type_names)),
        local_type_count,
        0,
      )
    }
    raise Unsupported("unsupported value type '\{name}'")
  }
  if expr is List(items) {
    if items.length() == 2 && items[0] is Atom("type") {
      return (
        TypeIdx(resolve_inline_type_ref(items[1], state, local_type_names)),
        local_type_count,
        0,
      )
    }
    if items.length() == 2 && items[0] is Atom("own") {
      let payload = ByteBuf::new()
      payload.push_u8(0x69)
      payload.push_uleb_u32(
        resolve_inline_type_ref(items[1], state, local_type_names),
      )
      decls.push_u8(0x01)
      decls.push_bytes(payload.to_bytes())
      return (TypeIdx(local_type_count), local_type_count + 1, 1)
    }
    if items.length() == 2 && items[0] is Atom("borrow") {
      let payload = ByteBuf::new()
      payload.push_u8(0x68)
      payload.push_uleb_u32(
        resolve_inline_type_ref(items[1], state, local_type_names),
      )
      decls.push_u8(0x01)
      decls.push_bytes(payload.to_bytes())
      return (TypeIdx(local_type_count), local_type_count + 1, 1)
    }
    if items.length() == 2 && items[0] is Atom("list") {
      let (inner, next_count, inner_decl_count) = parse_inline_valtype_encoding(
        items[1],
        state,
        decls,
        local_type_count,
        local_type_names,
      )
      let payload = ByteBuf::new()
      payload.push_u8(0x70)
      push_valtype_encoding(payload, inner)
      decls.push_u8(0x01)
      decls.push_bytes(payload.to_bytes())
      return (TypeIdx(next_count), next_count + 1, inner_decl_count + 1)
    }
    if items.length() == 2 && items[0] is Atom("option") {
      let (inner, next_count, inner_decl_count) = parse_inline_valtype_encoding(
        items[1],
        state,
        decls,
        local_type_count,
        local_type_names,
      )
      let payload = ByteBuf::new()
      payload.push_u8(0x6b)
      push_valtype_encoding(payload, inner)
      decls.push_u8(0x01)
      decls.push_bytes(payload.to_bytes())
      return (TypeIdx(next_count), next_count + 1, inner_decl_count + 1)
    }
    if items.length() > 0 && items[0] is Atom("tuple") {
      let payload = ByteBuf::new()
      payload.push_u8(0x6f)
      payload.push_uleb_u32(items.length() - 1)
      let mut next_count = local_type_count
      let mut total_decl_count = 0
      for i in 1..<items.length() {
        let (elem, next_next_count, elem_decl_count) = parse_inline_valtype_encoding(
          items[i],
          state,
          decls,
          next_count,
          local_type_names,
        )
        next_count = next_next_count
        total_decl_count += elem_decl_count
        push_valtype_encoding(payload, elem)
      }
      decls.push_u8(0x01)
      decls.push_bytes(payload.to_bytes())
      return (TypeIdx(next_count), next_count + 1, total_decl_count + 1)
    }
    if items.length() > 0 && items[0] is Atom("result") {
      let mut ok_ty : ValTypeEncoding? = None
      let mut err_ty : ValTypeEncoding? = None
      let mut next_count = local_type_count
      let mut total_decl_count = 0
      for i in 1..<items.length() {
        if items[i] is List(parts) &&
          parts.length() == 2 &&
          parts[0] is Atom("error") {
          if err_ty is Some(_) {
            raise Unsupported("result error type must appear at most once")
          }
          let (ty, next_next_count, ty_decl_count) = parse_inline_valtype_encoding(
            parts[1],
            state,
            decls,
            next_count,
            local_type_names,
          )
          next_count = next_next_count
          total_decl_count += ty_decl_count
          err_ty = Some(ty)
          continue
        }
        if ok_ty is Some(_) {
          raise Unsupported("result ok type must appear at most once")
        }
        let (ty, next_next_count, ty_decl_count) = parse_inline_valtype_encoding(
          items[i],
          state,
          decls,
          next_count,
          local_type_names,
        )
        next_count = next_next_count
        total_decl_count += ty_decl_count
        ok_ty = Some(ty)
      }
      let payload = ByteBuf::new()
      payload.push_u8(0x6a)
      if ok_ty is Some(ty) {
        payload.push_u8(0x01)
        push_valtype_encoding(payload, ty)
      } else {
        payload.push_u8(0x00)
      }
      if err_ty is Some(ty) {
        payload.push_u8(0x01)
        push_valtype_encoding(payload, ty)
      } else {
        payload.push_u8(0x00)
      }
      decls.push_u8(0x01)
      decls.push_bytes(payload.to_bytes())
      return (TypeIdx(next_count), next_count + 1, total_decl_count + 1)
    }
    if items.length() > 0 && items[0] is Atom("future") {
      let payload = ByteBuf::new()
      payload.push_u8(0x65)
      if items.length() == 1 {
        payload.push_u8(0x00)
        decls.push_u8(0x01)
        decls.push_bytes(payload.to_bytes())
        return (TypeIdx(local_type_count), local_type_count + 1, 1)
      }
      if items.length() != 2 {
        raise Unsupported("future type takes at most one payload type")
      }
      let (inner, next_count, inner_decl_count) = parse_inline_valtype_encoding(
        items[1],
        state,
        decls,
        local_type_count,
        local_type_names,
      )
      payload.push_u8(0x01)
      push_valtype_encoding(payload, inner)
      decls.push_u8(0x01)
      decls.push_bytes(payload.to_bytes())
      return (TypeIdx(next_count), next_count + 1, inner_decl_count + 1)
    }
    if items.length() > 0 && items[0] is Atom("stream") {
      let payload = ByteBuf::new()
      payload.push_u8(0x66)
      if items.length() == 1 {
        payload.push_u8(0x00)
        decls.push_u8(0x01)
        decls.push_bytes(payload.to_bytes())
        return (TypeIdx(local_type_count), local_type_count + 1, 1)
      }
      if items.length() != 2 {
        raise Unsupported("stream type takes at most one payload type")
      }
      let (inner, next_count, inner_decl_count) = parse_inline_valtype_encoding(
        items[1],
        state,
        decls,
        local_type_count,
        local_type_names,
      )
      payload.push_u8(0x01)
      push_valtype_encoding(payload, inner)
      decls.push_u8(0x01)
      decls.push_bytes(payload.to_bytes())
      return (TypeIdx(next_count), next_count + 1, inner_decl_count + 1)
    }
    raise Unsupported("unsupported non-atom value type")
  }
  raise Unsupported("unsupported non-atom value type")
}

///|
fn parse_inline_func_sig(
  desc : Array[SExpr],
  state : ComponentBuildState,
  decls : ByteBuf,
  local_type_count : Int,
  local_type_names : Array[NamedBinding],
) -> (FuncTypeSig, Int, Int) raise ComponentTextError {
  let params : Array[FuncParam] = []
  let mut result_ty : ValTypeEncoding? = None
  let mut is_async = false
  let mut next_type_count = local_type_count
  let mut decl_count = 0
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
          let (ty, next_next_count, ty_decl_count) = parse_inline_valtype_encoding(
            items[1],
            state,
            decls,
            next_type_count,
            local_type_names,
          )
          next_type_count = next_next_count
          decl_count += ty_decl_count
          params.push({ label: "p\{params.length()}", ty })
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
          let (ty, next_next_count, ty_decl_count) = parse_inline_valtype_encoding(
            items[2],
            state,
            decls,
            next_type_count,
            local_type_names,
          )
          next_type_count = next_next_count
          decl_count += ty_decl_count
          params.push({ label, ty })
          continue
        }
        raise Unsupported("unsupported param field")
      }
      if items[0] is Atom("result") {
        if result_ty is Some(_) {
          raise Unsupported("multiple result fields are not supported")
        }
        if items.length() == 2 {
          let (ty, next_next_count, ty_decl_count) = parse_inline_valtype_encoding(
            items[1],
            state,
            decls,
            next_type_count,
            local_type_names,
          )
          next_type_count = next_next_count
          decl_count += ty_decl_count
          result_ty = Some(ty)
          continue
        }
        raise Unsupported("unsupported result field")
      }
      raise Unsupported("unsupported func field")
    }
    if field is Atom("async") {
      is_async = true
      continue
    }
    raise Unsupported("unsupported func declaration item")
  }
  ({ params, result_ty, is_async }, next_type_count, decl_count)
}

///|
fn parse_inline_type_decl(
  field : Array[SExpr],
  state : ComponentBuildState,
  local_type_names : Array[NamedBinding],
  decls : ByteBuf,
  local_type_count : Int,
) -> (String?, Bytes, Int, Int) raise ComponentTextError {
  let name_opt = parse_optional_identifier(field, 1)
  let body_index = if name_opt is Some(_) { 2 } else { 1 }
  let mut next_type_count = local_type_count
  let mut decl_count = 0
  if body_index >= field.length() {
    raise Unsupported("type declaration is missing a body")
  }
  let body = field[body_index]
  if body is Atom(name) {
    if prim_type_opcode(name) is Some(opcode) {
      return (
        name_opt,
        Bytes::from_array([opcode.to_byte()]),
        next_type_count,
        decl_count,
      )
    }
  }
  if body is List(items) {
    if items.length() == 0 {
      raise Unsupported("type declaration body is empty")
    }
    if items[0] is Atom("func") {
      let (sig, next_next_type_count, local_decl_count) = parse_inline_func_sig(
        items, state, decls, next_type_count, local_type_names,
      )
      next_type_count = next_next_type_count
      decl_count += local_decl_count
      return (name_opt, encode_func_typedef(sig), next_type_count, decl_count)
    }
    if items[0] is Atom("record") {
      let payload = ByteBuf::new()
      payload.push_u8(0x72)
      payload.push_uleb_u32(items.length() - 1)
      for i in 1..<items.length() {
        let field_items = if items[i] is List(parts) {
          parts
        } else {
          raise Unsupported("record field must be a list")
        }
        if field_items.length() < 3 || !(field_items[0] is Atom("field")) {
          raise Unsupported("record field must be `(field <name> <type>)`")
        }
        let label_index = if parse_optional_identifier(field_items, 1)
          is Some(_) {
          2
        } else {
          1
        }
        if label_index + 1 >= field_items.length() {
          raise Unsupported("record field is missing type")
        }
        let label = parse_name_text(
          field_items[label_index],
          "record field name",
        )
        let (ty, next_next_type_count, field_decl_count) = parse_inline_valtype_encoding(
          field_items[label_index + 1],
          state,
          decls,
          next_type_count,
          local_type_names,
        )
        next_type_count = next_next_type_count
        decl_count += field_decl_count
        payload.push_utf8_name(label)
        push_valtype_encoding(payload, ty)
      }
      return (name_opt, payload.to_bytes(), next_type_count, decl_count)
    }
    if items[0] is Atom("variant") {
      let payload = ByteBuf::new()
      let case_ids : Array[NamedBinding] = []
      payload.push_u8(0x71)
      payload.push_uleb_u32(items.length() - 1)
      for i in 1..<items.length() {
        let case_items = if items[i] is List(parts) {
          parts
        } else {
          raise Unsupported("variant case must be a list")
        }
        if case_items.length() < 2 || !(case_items[0] is Atom("case")) {
          raise Unsupported("variant case must start with `case`")
        }
        let case_id = parse_optional_identifier(case_items, 1)
        let label_index = if case_id is Some(_) { 2 } else { 1 }
        if label_index >= case_items.length() {
          raise Unsupported("variant case is missing name")
        }
        let label = parse_name_text(
          case_items[label_index],
          "variant case name",
        )
        let mut ty_opt : ValTypeEncoding? = None
        let mut refines_opt : SExpr? = None
        for j in (label_index + 1)..<case_items.length() {
          let item = case_items[j]
          if item is List(refines_items) &&
            refines_items.length() == 2 &&
            refines_items[0] is Atom("refines") {
            refines_opt = Some(refines_items[1])
            continue
          }
          if ty_opt is Some(_) {
            raise Unsupported("variant case payload must appear at most once")
          }
          let (ty, next_next_type_count, case_decl_count) = parse_inline_valtype_encoding(
            item, state, decls, next_type_count, local_type_names,
          )
          next_type_count = next_next_type_count
          decl_count += case_decl_count
          ty_opt = Some(ty)
        }
        payload.push_utf8_name(label)
        if ty_opt is Some(ty) {
          payload.push_u8(0x01)
          push_valtype_encoding(payload, ty)
        } else {
          payload.push_u8(0x00)
        }
        if refines_opt is Some(refines_expr) {
          payload.push_u8(0x01)
          payload.push_uleb_u32(
            resolve_variant_case_ref(refines_expr, case_ids),
          )
        } else {
          payload.push_u8(0x00)
        }
        bind_named_index(case_ids, case_id, i - 1)
      }
      return (name_opt, payload.to_bytes(), next_type_count, decl_count)
    }
    if items[0] is Atom("tuple") {
      let payload = ByteBuf::new()
      payload.push_u8(0x6f)
      payload.push_uleb_u32(items.length() - 1)
      for i in 1..<items.length() {
        let (ty, next_next_type_count, elem_decl_count) = parse_inline_valtype_encoding(
          items[i],
          state,
          decls,
          next_type_count,
          local_type_names,
        )
        next_type_count = next_next_type_count
        decl_count += elem_decl_count
        push_valtype_encoding(payload, ty)
      }
      return (name_opt, payload.to_bytes(), next_type_count, decl_count)
    }
    if items[0] is Atom("list") {
      if items.length() != 2 {
        raise Unsupported("list type must be `(list <valtype>)`")
      }
      let (elem, next_next_type_count, elem_decl_count) = parse_inline_valtype_encoding(
        items[1],
        state,
        decls,
        next_type_count,
        local_type_names,
      )
      next_type_count = next_next_type_count
      decl_count += elem_decl_count
      let payload = ByteBuf::new()
      payload.push_u8(0x70)
      push_valtype_encoding(payload, elem)
      return (name_opt, payload.to_bytes(), next_type_count, decl_count)
    }
    if items[0] is Atom("option") {
      if items.length() != 2 {
        raise Unsupported("option type must be `(option <valtype>)`")
      }
      let (inner, next_next_type_count, inner_decl_count) = parse_inline_valtype_encoding(
        items[1],
        state,
        decls,
        next_type_count,
        local_type_names,
      )
      next_type_count = next_next_type_count
      decl_count += inner_decl_count
      let payload = ByteBuf::new()
      payload.push_u8(0x6b)
      push_valtype_encoding(payload, inner)
      return (name_opt, payload.to_bytes(), next_type_count, decl_count)
    }
    if items[0] is Atom("result") {
      let mut ok : ValTypeEncoding? = None
      let mut err : ValTypeEncoding? = None
      for i in 1..<items.length() {
        let item = items[i]
        if item is List(parts) &&
          parts.length() == 2 &&
          parts[0] is Atom("error") {
          if err is Some(_) {
            raise Unsupported("result error type must appear at most once")
          }
          let (ty, next_next_type_count, err_decl_count) = parse_inline_valtype_encoding(
            parts[1],
            state,
            decls,
            next_type_count,
            local_type_names,
          )
          next_type_count = next_next_type_count
          decl_count += err_decl_count
          err = Some(ty)
          continue
        }
        if ok is Some(_) {
          raise Unsupported("result ok type must appear at most once")
        }
        let (ty, next_next_type_count, ok_decl_count) = parse_inline_valtype_encoding(
          item, state, decls, next_type_count, local_type_names,
        )
        next_type_count = next_next_type_count
        decl_count += ok_decl_count
        ok = Some(ty)
      }
      let payload = ByteBuf::new()
      payload.push_u8(0x6a)
      if ok is Some(ok_ty) {
        payload.push_u8(0x01)
        push_valtype_encoding(payload, ok_ty)
      } else {
        payload.push_u8(0x00)
      }
      if err is Some(err_ty) {
        payload.push_u8(0x01)
        push_valtype_encoding(payload, err_ty)
      } else {
        payload.push_u8(0x00)
      }
      return (name_opt, payload.to_bytes(), next_type_count, decl_count)
    }
    if items[0] is Atom("flags") {
      return (
        name_opt,
        parse_flags_or_enum_type_bytes(0x6e, items),
        next_type_count,
        decl_count,
      )
    }
    if items[0] is Atom("enum") {
      return (
        name_opt,
        parse_flags_or_enum_type_bytes(0x6d, items),
        next_type_count,
        decl_count,
      )
    }
    if items[0] is Atom("own") || items[0] is Atom("borrow") {
      if items.length() != 2 {
        raise Unsupported(
          "resource handle type must contain exactly one type reference",
        )
      }
      let payload = ByteBuf::new()
      payload.push_u8(if items[0] is Atom("own") { 0x69 } else { 0x68 })
      payload.push_uleb_u32(
        resolve_inline_type_ref(items[1], state, local_type_names),
      )
      return (name_opt, payload.to_bytes(), next_type_count, decl_count)
    }
    if items[0] is Atom("future") {
      let payload = ByteBuf::new()
      payload.push_u8(0x65)
      if items.length() == 1 {
        payload.push_u8(0x00)
      } else if items.length() == 2 {
        let (inner, next_next_type_count, inner_decl_count) = parse_inline_valtype_encoding(
          items[1],
          state,
          decls,
          next_type_count,
          local_type_names,
        )
        next_type_count = next_next_type_count
        decl_count += inner_decl_count
        payload.push_u8(0x01)
        push_valtype_encoding(payload, inner)
      } else {
        raise Unsupported("future/stream type takes at most one payload type")
      }
      return (name_opt, payload.to_bytes(), next_type_count, decl_count)
    }
    if items[0] is Atom("stream") {
      let payload = ByteBuf::new()
      payload.push_u8(0x66)
      if items.length() == 1 {
        payload.push_u8(0x00)
      } else if items.length() == 2 {
        let (inner, next_next_type_count, inner_decl_count) = parse_inline_valtype_encoding(
          items[1],
          state,
          decls,
          next_type_count,
          local_type_names,
        )
        next_type_count = next_next_type_count
        decl_count += inner_decl_count
        payload.push_u8(0x01)
        push_valtype_encoding(payload, inner)
      } else {
        raise Unsupported("future/stream type takes at most one payload type")
      }
      return (name_opt, payload.to_bytes(), next_type_count, decl_count)
    }
    if items[0] is Atom("resource") {
      return (
        name_opt,
        parse_resource_type_bytes(items, state),
        next_type_count,
        decl_count,
      )
    }
    if items[0] is Atom("component") {
      return (
        name_opt,
        build_inline_component_type_bytes_with_ambient(
          items, 1, state, local_type_names,
        ),
        next_type_count,
        decl_count,
      )
    }
    if items[0] is Atom("instance") {
      return (
        name_opt,
        build_inline_instance_type_bytes_with_ambient(
          items, 1, state, local_type_names,
        ),
        next_type_count,
        decl_count,
      )
    }
  }
  raise Unsupported("unsupported type declaration")
}

///|
fn parse_inline_externdesc_from_type_desc(
  desc : Array[SExpr],
  state : ComponentBuildState,
  decls : ByteBuf,
  local_type_count : Int,
  local_core_type_count : Int,
  local_type_names : Array[NamedBinding],
) -> (Bytes, Int, Int, Int) raise ComponentTextError {
  if desc.length() == 0 {
    raise Unsupported("empty type descriptor")
  }
  let mut type_count = local_type_count
  let mut core_type_count = local_core_type_count
  let mut decl_count = 0

  if desc[0] is Atom("func") {
    let mut type_use : Int? = None
    let filtered : Array[SExpr] = [Atom("func")]
    let mut start = 1
    if parse_optional_identifier(desc, 1) is Some(name) {
      filtered.push(Atom(name))
      start = 2
    }
    for i in start..<desc.length() {
      let item = desc[i]
      if item is List(items) && items.length() > 0 && items[0] is Atom("type") {
        if items.length() != 2 {
          raise Unsupported("type use must be `(type <index-or-id>)`")
        }
        type_use = Some(parse_type_use_inline(items, state, local_type_names))
        continue
      }
      filtered.push(item)
    }
    let type_idx = if type_use is Some(idx) && filtered.length() == 1 {
      idx
    } else {
      let (sig, next_type_count, local_decl_count) = parse_inline_func_sig(
        filtered, state, decls, type_count, local_type_names,
      )
      type_count = next_type_count
      decl_count += local_decl_count
      decls.push_u8(0x01)
      decls.push_bytes(encode_func_typedef(sig))
      decl_count += 1
      let idx = type_count
      type_count += 1
      idx
    }
    let b = ByteBuf::new()
    b.push_u8(0x01)
    b.push_uleb_u32(type_idx)
    return (b.to_bytes(), type_count, core_type_count, decl_count)
  }

  if desc[0] is Atom("type") {
    let name_opt = parse_optional_identifier(desc, 1)
    let bound_index = if name_opt is Some(_) { 2 } else { 1 }
    if bound_index >= desc.length() {
      raise Unsupported("type descriptor is missing bound")
    }
    if bound_index + 1 != desc.length() {
      raise Unsupported("type descriptor currently supports one bound")
    }
    let b = ByteBuf::new()
    b.push_u8(0x03)
    b.push_bytes(
      parse_type_bound_bytes_inline(desc[bound_index], state, local_type_names),
    )
    bind_named_index(local_type_names, name_opt, type_count)
    bind_named_index(state.type_names, name_opt, type_count)
    type_count += 1
    return (b.to_bytes(), type_count, core_type_count, decl_count)
  }

  if desc[0] is Atom("component") || desc[0] is Atom("instance") {
    let is_component = desc[0] is Atom("component")
    let name_opt = parse_optional_identifier(desc, 1)
    let index = if name_opt is Some(_) { 2 } else { 1 }
    let type_idx = if index < desc.length() {
      let type_field = if desc[index] is List(items) {
        items
      } else {
        raise Unsupported("import descriptor type annotation must be a list")
      }
      if type_field.length() == 0 ||
        !(type_field[0] is Atom("type")) ||
        index + 1 != desc.length() {
        let nested_type = if is_component {
          build_inline_component_type_bytes_with_ambient(
            desc, index, state, local_type_names,
          )
        } else {
          build_inline_instance_type_bytes_with_ambient(
            desc, index, state, local_type_names,
          )
        }
        decls.push_u8(0x01)
        decls.push_bytes(nested_type)
        decl_count += 1
        let idx = type_count
        type_count += 1
        idx
      } else {
        parse_type_use_inline(type_field, state, local_type_names)
      }
    } else {
      decls.push_u8(0x01)
      decls.push_u8(if is_component { 0x41 } else { 0x42 })
      decls.push_u8(0x00)
      decl_count += 1
      let idx = type_count
      type_count += 1
      idx
    }
    let b = ByteBuf::new()
    b.push_u8(if is_component { 0x04 } else { 0x05 })
    b.push_uleb_u32(type_idx)
    return (b.to_bytes(), type_count, core_type_count, decl_count)
  }

  if desc.length() >= 2 && desc[0] is Atom("core") && desc[1] is Atom("module") {
    let name_opt = parse_optional_identifier(desc, 2)
    let index = if name_opt is Some(_) { 3 } else { 2 }
    let type_idx = if index < desc.length() {
      let type_field = if desc[index] is List(items) {
        items
      } else {
        raise Unsupported("core module type annotation must be a list")
      }
      if type_field.length() == 0 ||
        !(type_field[0] is Atom("type")) ||
        index + 1 != desc.length() {
        decls.push_u8(0x00)
        decls.push_bytes(parse_core_module_type_bytes(desc, index, state))
        decl_count += 1
        let idx = core_type_count
        core_type_count += 1
        idx
      } else {
        if type_field.length() != 2 {
          raise Unsupported("core type use must be `(type <index-or-id>)`")
        }
        if type_field[1] is Atom(name) && name.has_prefix("$") {
          let outer_type_idx = parse_core_type_use(type_field, state)
          decls.push_u8(0x02)
          decls.push_bytes(
            encode_alias_outer_decl(0x00, Some(0x05), 1, outer_type_idx),
          )
          decl_count += 1
          let idx = core_type_count
          core_type_count += 1
          idx
        } else {
          parse_core_type_use(type_field, state)
        }
      }
    } else {
      decls.push_u8(0x00)
      decls.push_u8(0x50)
      decls.push_u8(0x00)
      decl_count += 1
      let idx = core_type_count
      core_type_count += 1
      idx
    }
    let b = ByteBuf::new()
    b.push_u8(0x00)
    b.push_u8(0x11)
    b.push_uleb_u32(type_idx)
    return (b.to_bytes(), type_count, core_type_count, decl_count)
  }
  raise Unsupported("unsupported type descriptor")
}

///|
fn inline_externdesc_sort(
  desc : Array[SExpr],
) -> (Int, Int?, String?) raise ComponentTextError {
  if desc.length() == 0 {
    raise Unsupported("empty type descriptor")
  }
  if desc[0] is Atom("func") {
    return (0x01, None, parse_optional_identifier(desc, 1))
  }
  if desc[0] is Atom("type") {
    return (0x03, None, parse_optional_identifier(desc, 1))
  }
  if desc[0] is Atom("component") {
    return (0x04, None, parse_optional_identifier(desc, 1))
  }
  if desc[0] is Atom("instance") {
    return (0x05, None, parse_optional_identifier(desc, 1))
  }
  if desc.length() >= 2 && desc[0] is Atom("core") && desc[1] is Atom("module") {
    return (0x00, Some(0x11), parse_optional_identifier(desc, 2))
  }
  raise Unsupported("unsupported type descriptor")
}

///|
fn parse_inline_alias_decl(
  field : Array[SExpr],
  state : ComponentBuildState,
  local_type_names : Array[NamedBinding],
  local_instance_names : Array[NamedBinding],
  local_type_count : Int,
  local_core_type_count : Int,
  local_instance_count : Int,
) -> (Bytes, Int, Int, Int) raise ComponentTextError {
  if field.length() == 5 && field[1] is Atom("export") {
    let instance_idx = resolve_reference(
      field[2],
      local_instance_names,
      "instance",
    )
    let export_name = parse_name_text(field[3], "inline alias export name")
    let sort_spec = parse_alias_sort_spec(field[4])
    let mut next_local_type_count = local_type_count
    let mut next_local_core_type_count = local_core_type_count
    let mut next_local_instance_count = local_instance_count
    if sort_spec.sort_tag == 0x03 && sort_spec.core_kind is None {
      bind_named_index(
        local_type_names,
        sort_spec.name_opt,
        next_local_type_count,
      )
      bind_named_index(
        state.type_names,
        sort_spec.name_opt,
        next_local_type_count,
      )
      next_local_type_count += 1
    } else if sort_spec.sort_tag == 0x05 && sort_spec.core_kind is None {
      bind_named_index(
        local_instance_names,
        sort_spec.name_opt,
        next_local_instance_count,
      )
      next_local_instance_count += 1
    } else if sort_spec.sort_tag == 0x00 && sort_spec.core_kind is Some(0x05) {
      next_local_core_type_count += 1
    } else {
      raise Unsupported(
        "inline alias only supports instance/type/core type references",
      )
    }
    let alias_decl = encode_alias_instance_export_decl(
      sort_spec.sort_tag,
      sort_spec.core_kind,
      instance_idx,
      export_name,
    )
    return (
      alias_decl, next_local_type_count, next_local_core_type_count, next_local_instance_count,
    )
  }
  if field.length() == 5 && field[1] is Atom("outer") {
    let sort_spec = parse_alias_sort_spec(field[4])
    let is_type_alias = sort_spec.sort_tag == 0x03 &&
      sort_spec.core_kind is None
    let is_core_type_alias = sort_spec.sort_tag == 0x00 &&
      sort_spec.core_kind is Some(0x05)
    if !is_type_alias && !is_core_type_alias {
      raise Unsupported("inline alias only supports type/core type references")
    }
    let inferred_outer_count = if field[3] is Atom(target_name) &&
      target_name.has_prefix("$") {
      if is_type_alias {
        if lookup_named_index(state.type_names, target_name) is Some(_) {
          Some(1)
        } else {
          let mut found : Int? = None
          for depth in 0..<state.outer_type_scopes.length() {
            if lookup_named_index(state.outer_type_scopes[depth], target_name)
              is Some(_) {
              found = Some(depth + 2)
              break
            }
          }
          found
        }
      } else if lookup_named_index(state.core_type_names, target_name)
        is Some(_) {
        Some(1)
      } else {
        let mut found : Int? = None
        for depth in 0..<state.outer_core_type_scopes.length() {
          if lookup_named_index(
              state.outer_core_type_scopes[depth],
              target_name,
            )
            is Some(_) {
            found = Some(depth + 2)
            break
          }
        }
        found
      }
    } else {
      None
    }
    let count = if field[2] is Atom(count_atom) {
      if parse_decimal_index(count_atom) is Some(count) {
        count
      } else if count_atom.has_prefix("$") {
        match inferred_outer_count {
          Some(depth) => depth
          None => 0
        }
      } else {
        raise Unsupported("outer alias count must be a decimal index for now")
      }
    } else {
      raise Unsupported("outer alias count must be a decimal index for now")
    }
    let target_idx = if is_type_alias {
      if field[3] is Atom(target_name) && target_name.has_prefix("$") {
        if count == 1 &&
          lookup_named_index(state.type_names, target_name) is Some(idx) {
          idx
        } else if count > 1 &&
          count - 2 < state.outer_type_scopes.length() &&
          lookup_named_index(state.outer_type_scopes[count - 2], target_name)
          is Some(idx) {
          idx
        } else if lookup_named_index(local_type_names, target_name) is Some(idx) {
          idx
        } else {
          resolve_reference(field[3], state.type_names, "type")
        }
      } else {
        resolve_reference(field[3], local_type_names, "type")
      }
    } else if field[3] is Atom(target_name) && target_name.has_prefix("$") {
      if count == 1 &&
        lookup_named_index(state.core_type_names, target_name) is Some(idx) {
        idx
      } else if count > 1 &&
        count - 2 < state.outer_core_type_scopes.length() &&
        lookup_named_index(state.outer_core_type_scopes[count - 2], target_name)
        is Some(idx) {
        idx
      } else {
        resolve_reference(field[3], state.core_type_names, "core type")
      }
    } else {
      resolve_reference(field[3], state.core_type_names, "core type")
    }
    let mut next_local_type_count = local_type_count
    let mut next_local_core_type_count = local_core_type_count
    let next_local_instance_count = local_instance_count
    if is_type_alias {
      bind_named_index(
        local_type_names,
        sort_spec.name_opt,
        next_local_type_count,
      )
      bind_named_index(
        state.type_names,
        sort_spec.name_opt,
        next_local_type_count,
      )
      next_local_type_count += 1
    } else {
      next_local_core_type_count += 1
    }
    let alias_decl = encode_alias_outer_decl(
      sort_spec.sort_tag,
      sort_spec.core_kind,
      count,
      target_idx,
    )
    return (
      alias_decl, next_local_type_count, next_local_core_type_count, next_local_instance_count,
    )
  }
  raise Unsupported("unsupported inline alias declaration")
}

///|
fn build_inline_instance_type_bytes_with_ambient(
  desc : Array[SExpr],
  start : Int,
  state : ComponentBuildState,
  ambient_type_names : Array[NamedBinding],
) -> Bytes raise ComponentTextError {
  let saved_type_name_len = state.type_names.length()
  let ref_names = collect_inline_ref_names(desc, start)
  let decls = ByteBuf::new()
  let mut count = 0
  let mut local_type_count = 0
  let mut local_core_type_count = 0
  let local_type_names : Array[NamedBinding] = []
  let local_instance_names : Array[NamedBinding] = []
  let mut local_instance_count = 0
  let mut depth = state.outer_type_scopes.length()
  while depth > 0 {
    depth -= 1
    for binding in state.outer_type_scopes[depth] {
      if !contains_ref_name(ref_names, binding.name) {
        continue
      }
      decls.push_u8(0x02)
      decls.push_bytes(
        encode_alias_outer_decl(0x03, None, depth + 2, binding.idx),
      )
      count += 1
      bind_named_index(local_type_names, Some(binding.name), local_type_count)
      bind_named_index(state.type_names, Some(binding.name), local_type_count)
      local_type_count += 1
    }
  }
  for binding in ambient_type_names {
    if !contains_ref_name(ref_names, binding.name) {
      continue
    }
    decls.push_u8(0x02)
    decls.push_bytes(encode_alias_outer_decl(0x03, None, 1, binding.idx))
    count += 1
    bind_named_index(local_type_names, Some(binding.name), local_type_count)
    bind_named_index(state.type_names, Some(binding.name), local_type_count)
    local_type_count += 1
  }
  for i in start..<desc.length() {
    let field = if desc[i] is List(items) {
      items
    } else {
      raise Unsupported("inline instance descriptor entries must be lists")
    }
    if field.length() > 0 && field[0] is Atom("type") {
      let (type_name_opt, type_bytes, next_local_type_count, local_decl_count) = parse_inline_type_decl(
        field, state, local_type_names, decls, local_type_count,
      )
      local_type_count = next_local_type_count
      count += local_decl_count
      decls.push_u8(0x01)
      decls.push_bytes(type_bytes)
      count += 1
      bind_named_index(local_type_names, type_name_opt, local_type_count)
      bind_named_index(state.type_names, type_name_opt, local_type_count)
      local_type_count += 1
      continue
    }
    if field.length() > 0 && field[0] is Atom("core") {
      if field.length() < 3 || !(field[1] is Atom("type")) {
        raise Unsupported(
          "inline instance descriptor only supports core type declarations",
        )
      }
      let core_name_opt = parse_optional_identifier(field, 2)
      let body_index = if core_name_opt is Some(_) { 3 } else { 2 }
      if body_index >= field.length() || body_index + 1 != field.length() {
        raise Unsupported("inline core type declaration must define one body")
      }
      let body = if field[body_index] is List(items) {
        items
      } else {
        raise Unsupported("inline core type body must be a list")
      }
      if body.length() == 0 {
        raise Unsupported("inline core type declaration body is empty")
      }
      let core_type_bytes = if body[0] is Atom("module") {
        parse_core_module_type_bytes(body, 1, state)
      } else if body[0] is Atom("func") {
        parse_core_func_type_bytes(body, state.core_type_names)
      } else {
        raise Unsupported("unsupported inline core type declaration")
      }
      decls.push_u8(0x00)
      decls.push_bytes(core_type_bytes)
      count += 1
      local_core_type_count += 1
      continue
    }
    if field.length() > 0 && field[0] is Atom("alias") {
      let (
        alias_decl,
        next_local_type_count,
        next_local_core_type_count,
        next_local_instance_count,
      ) = parse_inline_alias_decl(
        field, state, local_type_names, local_instance_names, local_type_count, local_core_type_count,
        local_instance_count,
      )
      local_type_count = next_local_type_count
      local_core_type_count = next_local_core_type_count
      local_instance_count = next_local_instance_count
      decls.push_u8(0x02)
      decls.push_bytes(alias_decl)
      count += 1
      continue
    }
    if field.length() != 3 || !(field[0] is Atom("export")) {
      raise Unsupported(
        "inline instance descriptor only supports `(export <name> <type-desc>)` entries",
      )
    }
    let export_name = parse_name_text(field[1], "instance type export name")
    let export_desc = if field[2] is List(items) {
      items
    } else {
      raise Unsupported("instance type export descriptor must be a list")
    }
    let (desc_sort_tag, desc_core_kind, desc_name_opt) = inline_externdesc_sort(
      export_desc,
    )
    let (
      desc_bytes,
      next_local_type_count,
      next_local_core_type_count,
      local_decl_count,
    ) = parse_inline_externdesc_from_type_desc(
      export_desc, state, decls, local_type_count, local_core_type_count, local_type_names,
    )
    local_type_count = next_local_type_count
    local_core_type_count = next_local_core_type_count
    count += local_decl_count
    if desc_sort_tag == 0x05 && desc_core_kind is None {
      bind_named_index(
        local_instance_names, desc_name_opt, local_instance_count,
      )
      local_instance_count += 1
    }
    decls.push_u8(0x04)
    decls.push_u8(0x00)
    decls.push_utf8_name(export_name)
    decls.push_bytes(desc_bytes)
    count += 1
  }
  let payload = ByteBuf::new()
  payload.push_u8(0x42)
  payload.push_uleb_u32(count)
  payload.push_bytes(decls.to_bytes())
  let result = payload.to_bytes()
  while state.type_names.length() > saved_type_name_len {
    state.type_names.pop() |> ignore
  }
  result
}

///|
fn build_inline_instance_type_bytes(
  desc : Array[SExpr],
  start : Int,
  state : ComponentBuildState,
) -> Bytes raise ComponentTextError {
  let ambient_type_names = copy_named_bindings(state.type_names)
  build_inline_instance_type_bytes_with_ambient(
    desc, start, state, ambient_type_names,
  )
}

///|
fn build_inline_component_type_bytes_with_ambient(
  desc : Array[SExpr],
  start : Int,
  state : ComponentBuildState,
  ambient_type_names : Array[NamedBinding],
) -> Bytes raise ComponentTextError {
  let saved_type_name_len = state.type_names.length()
  let ref_names = collect_inline_ref_names(desc, start)
  let decls = ByteBuf::new()
  let mut count = 0
  let mut local_type_count = 0
  let mut local_core_type_count = 0
  let local_type_names : Array[NamedBinding] = []
  let local_instance_names : Array[NamedBinding] = []
  let mut local_instance_count = 0
  let mut depth = state.outer_type_scopes.length()
  while depth > 0 {
    depth -= 1
    for binding in state.outer_type_scopes[depth] {
      if !contains_ref_name(ref_names, binding.name) {
        continue
      }
      decls.push_u8(0x02)
      decls.push_bytes(
        encode_alias_outer_decl(0x03, None, depth + 2, binding.idx),
      )
      count += 1
      bind_named_index(local_type_names, Some(binding.name), local_type_count)
      bind_named_index(state.type_names, Some(binding.name), local_type_count)
      local_type_count += 1
    }
  }
  for binding in ambient_type_names {
    if !contains_ref_name(ref_names, binding.name) {
      continue
    }
    decls.push_u8(0x02)
    decls.push_bytes(encode_alias_outer_decl(0x03, None, 1, binding.idx))
    count += 1
    bind_named_index(local_type_names, Some(binding.name), local_type_count)
    bind_named_index(state.type_names, Some(binding.name), local_type_count)
    local_type_count += 1
  }
  for i in start..<desc.length() {
    let field = if desc[i] is List(items) {
      items
    } else {
      raise Unsupported("inline component descriptor entries must be lists")
    }
    if field.length() > 0 && field[0] is Atom("type") {
      let (type_name_opt, type_bytes, next_local_type_count, local_decl_count) = parse_inline_type_decl(
        field, state, local_type_names, decls, local_type_count,
      )
      local_type_count = next_local_type_count
      count += local_decl_count
      decls.push_u8(0x01)
      decls.push_bytes(type_bytes)
      count += 1
      bind_named_index(local_type_names, type_name_opt, local_type_count)
      bind_named_index(state.type_names, type_name_opt, local_type_count)
      local_type_count += 1
      continue
    }
    if field.length() > 0 && field[0] is Atom("core") {
      if field.length() < 3 || !(field[1] is Atom("type")) {
        raise Unsupported("unsupported inline component declaration")
      }
      let core_name_opt = parse_optional_identifier(field, 2)
      let body_index = if core_name_opt is Some(_) { 3 } else { 2 }
      if body_index >= field.length() || body_index + 1 != field.length() {
        raise Unsupported("inline core type declaration must define one body")
      }
      let body = if field[body_index] is List(items) {
        items
      } else {
        raise Unsupported("inline core type body must be a list")
      }
      if body.length() == 0 {
        raise Unsupported("inline core type declaration body is empty")
      }
      let core_type_bytes = if body[0] is Atom("module") {
        parse_core_module_type_bytes(body, 1, state)
      } else if body[0] is Atom("func") {
        parse_core_func_type_bytes(body, state.core_type_names)
      } else {
        raise Unsupported("unsupported inline core type declaration")
      }
      decls.push_u8(0x00)
      decls.push_bytes(core_type_bytes)
      count += 1
      local_core_type_count += 1
      continue
    }
    if field.length() > 0 && field[0] is Atom("alias") {
      let (
        alias_decl,
        next_local_type_count,
        next_local_core_type_count,
        next_local_instance_count,
      ) = parse_inline_alias_decl(
        field, state, local_type_names, local_instance_names, local_type_count, local_core_type_count,
        local_instance_count,
      )
      local_type_count = next_local_type_count
      local_core_type_count = next_local_core_type_count
      local_instance_count = next_local_instance_count
      decls.push_u8(0x02)
      decls.push_bytes(alias_decl)
      count += 1
      continue
    }
    if field.length() != 3 {
      raise Unsupported(
        "inline component descriptor entries must be `(import/export <name> <type-desc>)`",
      )
    }
    let is_import = if field[0] is Atom("import") {
      true
    } else if field[0] is Atom("export") {
      false
    } else {
      raise Unsupported("unsupported inline component declaration")
    }
    let field_name = parse_name_text(
      field[1],
      if is_import {
        "component type import name"
      } else {
        "component type export name"
      },
    )
    let field_desc = if field[2] is List(items) {
      items
    } else {
      raise Unsupported("component type declaration descriptor must be a list")
    }
    let (desc_sort_tag, desc_core_kind, desc_name_opt) = inline_externdesc_sort(
      field_desc,
    )
    let (
      desc_bytes,
      next_local_type_count,
      next_local_core_type_count,
      local_decl_count,
    ) = parse_inline_externdesc_from_type_desc(
      field_desc, state, decls, local_type_count, local_core_type_count, local_type_names,
    )
    local_type_count = next_local_type_count
    local_core_type_count = next_local_core_type_count
    count += local_decl_count
    if desc_sort_tag == 0x05 && desc_core_kind is None {
      bind_named_index(
        local_instance_names, desc_name_opt, local_instance_count,
      )
      local_instance_count += 1
    }
    decls.push_u8(if is_import { 0x03 } else { 0x04 })
    decls.push_u8(0x00)
    decls.push_utf8_name(field_name)
    decls.push_bytes(desc_bytes)
    count += 1
  }
  let payload = ByteBuf::new()
  payload.push_u8(0x41)
  payload.push_uleb_u32(count)
  payload.push_bytes(decls.to_bytes())
  let result = payload.to_bytes()
  while state.type_names.length() > saved_type_name_len {
    state.type_names.pop() |> ignore
  }
  result
}

///|
fn build_inline_component_type_bytes(
  desc : Array[SExpr],
  start : Int,
  state : ComponentBuildState,
) -> Bytes raise ComponentTextError {
  let ambient_type_names = copy_named_bindings(state.type_names)
  build_inline_component_type_bytes_with_ambient(
    desc, start, state, ambient_type_names,
  )
}

///|
fn parse_inline_instance_type(
  desc : Array[SExpr],
  start : Int,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  add_type_entry(
    state,
    build_inline_instance_type_bytes(desc, start, state),
    None,
    None,
  )
}

///|
fn parse_inline_component_type(
  desc : Array[SExpr],
  start : Int,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  add_type_entry(
    state,
    build_inline_component_type_bytes(desc, start, state),
    None,
    None,
  )
}

///|
fn parse_import(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  if field.length() < 2 || field.length() > 4 {
    raise Unsupported("import form currently expects exactly one descriptor")
  }
  let import_id_opt = parse_optional_identifier(field, 1)
  let name_index = if import_id_opt is Some(_) { 2 } else { 1 }
  let desc_index = name_index + 1
  if name_index >= field.length() || desc_index + 1 < field.length() {
    raise Unsupported("import form currently expects exactly one descriptor")
  }
  let name = parse_name_text(field[name_index], "import name")
  let desc = if desc_index >= field.length() {
    [Atom("func")]
  } else if field[desc_index] is List(items) {
    items
  } else {
    raise Unsupported("import descriptor must be a list")
  }
  if desc.length() == 0 {
    raise Unsupported("empty import descriptor")
  }
  if desc[0] is Atom("type") {
    let type_name_opt = parse_optional_identifier(desc, 1)
    let bound_index = if type_name_opt is Some(_) { 2 } else { 1 }
    if bound_index >= desc.length() {
      raise Unsupported("type import is missing bound")
    }
    if bound_index + 1 != desc.length() {
      raise Unsupported("type import currently supports one bound")
    }
    let bound_bytes = parse_type_bound_bytes(desc[bound_index], state)
    let import_entry : ImportEntry = {
      name,
      desc: {
        let b = ByteBuf::new()
        b.push_u8(0x03)
        b.push_bytes(bound_bytes)
        b.to_bytes()
      },
    }
    state.imports.push(import_entry)
    push_ordered_section(state, 10, encode_import_decl(import_entry))
    let type_idx = state.next_type_idx
    state.next_type_idx += 1
    bind_named_index(
      state.type_names,
      if type_name_opt is Some(_) {
        type_name_opt
      } else {
        import_id_opt
      },
      type_idx,
    )
    return
  }
  if desc[0] is Atom("func") {
    let (func_name, type_idx) = parse_import_func_desc(desc, state)
    let import_entry : ImportEntry = {
      name,
      desc: {
        let b = ByteBuf::new()
        b.push_u8(0x01)
        b.push_uleb_u32(type_idx)
        b.to_bytes()
      },
    }
    state.imports.push(import_entry)
    push_ordered_section(state, 10, encode_import_decl(import_entry))
    let func_idx = state.next_func_idx
    state.next_func_idx += 1
    bind_named_index(
      state.func_names,
      if func_name is Some(_) {
        func_name
      } else {
        import_id_opt
      },
      func_idx,
    )
    return
  }
  if desc[0] is Atom("component") || desc[0] is Atom("instance") {
    let is_component = desc[0] is Atom("component")
    let desc_name_opt = parse_optional_identifier(desc, 1)
    let index = if desc_name_opt is Some(_) { 2 } else { 1 }
    let type_idx = if index < desc.length() {
      let type_field = if desc[index] is List(items) {
        items
      } else {
        raise Unsupported("inline import descriptor entries must be lists")
      }
      if type_field.length() > 0 &&
        type_field[0] is Atom("type") &&
        index + 1 == desc.length() {
        parse_type_use(type_field, state)
      } else if is_component {
        parse_inline_component_type(desc, index, state)
      } else {
        parse_inline_instance_type(desc, index, state)
      }
    } else if is_component {
      ensure_empty_component_type(state)
    } else {
      ensure_empty_instance_type(state)
    }
    let import_entry : ImportEntry = {
      name,
      desc: {
        let b = ByteBuf::new()
        b.push_u8(if is_component { 0x04 } else { 0x05 })
        b.push_uleb_u32(type_idx)
        b.to_bytes()
      },
    }
    state.imports.push(import_entry)
    push_ordered_section(state, 10, encode_import_decl(import_entry))
    if is_component {
      let component_idx = state.next_component_idx
      state.next_component_idx += 1
      bind_named_index(
        state.component_names,
        if desc_name_opt is Some(_) {
          desc_name_opt
        } else {
          import_id_opt
        },
        component_idx,
      )
    } else {
      let instance_idx = state.next_instance_idx
      state.next_instance_idx += 1
      bind_named_index(
        state.instance_names,
        if desc_name_opt is Some(_) {
          desc_name_opt
        } else {
          import_id_opt
        },
        instance_idx,
      )
    }
    return
  }
  if desc.length() >= 2 && desc[0] is Atom("core") && desc[1] is Atom("module") {
    let desc_name_opt = parse_optional_identifier(desc, 2)
    let index = if desc_name_opt is Some(_) { 3 } else { 2 }
    let type_idx = if index < desc.length() {
      let first_field = if desc[index] is List(items) {
        items
      } else {
        raise Unsupported("core module import descriptor entries must be lists")
      }
      if first_field.length() > 0 &&
        first_field[0] is Atom("type") &&
        index + 1 == desc.length() {
        parse_core_type_use(first_field, state)
      } else {
        ensure_core_type_bytes(
          state,
          parse_core_module_type_bytes(desc, index, state),
        )
      }
    } else {
      ensure_empty_core_module_type(state)
    }
    let import_entry : ImportEntry = {
      name,
      desc: {
        let b = ByteBuf::new()
        b.push_u8(0x00)
        b.push_u8(0x11)
        b.push_uleb_u32(type_idx)
        b.to_bytes()
      },
    }
    state.imports.push(import_entry)
    push_ordered_section(state, 10, encode_import_decl(import_entry))
    let module_idx = state.next_core_module_idx
    state.next_core_module_idx += 1
    bind_named_index(
      state.core_module_names,
      if desc_name_opt is Some(_) {
        desc_name_opt
      } else {
        import_id_opt
      },
      module_idx,
    )
    return
  }
  raise Unsupported("unsupported import descriptor")
}

///|
fn encode_import_decl(import_item : ImportEntry) -> Bytes {
  let payload = ByteBuf::new()
  payload.push_u8(0x00)
  payload.push_utf8_name(import_item.name)
  payload.push_bytes(import_item.desc)
  payload.to_bytes()
}

///|
fn push_sort_prefix(
  payload : ByteBuf,
  sort_tag : Int,
  core_kind : Int?,
) -> Unit raise ComponentTextError {
  if sort_tag == 0x00 {
    payload.push_u8(0x00)
    if core_kind is Some(kind) {
      payload.push_u8(kind)
      return
    }
    raise Unsupported("core sort is missing kind")
  }
  payload.push_u8(sort_tag)
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
    push_sort_prefix(payload, export_item.sort_tag, export_item.core_kind)
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
fn push_export_decl(
  state : ComponentBuildState,
  export_item : ExportEntry,
) -> Unit raise ComponentTextError {
  state.exports.push(export_item)
  state.sections_ordered.push({
    section_id: 11,
    payload: encode_export_section([export_item]),
  })
}

///|
fn wrap_single_decl(decl : Bytes) -> Bytes {
  let payload = ByteBuf::new()
  payload.push_uleb_u32(1)
  payload.push_bytes(decl)
  payload.to_bytes()
}

///|
fn push_ordered_section(
  state : ComponentBuildState,
  section_id : Int,
  decl : Bytes,
) -> Unit {
  state.sections_ordered.push({ section_id, payload: wrap_single_decl(decl) })
}

///|
fn encode_core_instance_decl(entry : CoreInstanceEntry) -> Bytes {
  let payload = ByteBuf::new()
  match entry.expr {
    Instantiate(module_idx, args) => {
      payload.push_u8(0x00)
      payload.push_uleb_u32(module_idx)
      payload.push_uleb_u32(args.length())
      for arg in args {
        payload.push_utf8_name(arg.name)
        payload.push_u8(arg.kind)
        payload.push_uleb_u32(arg.idx)
      }
    }
    InlineExports(exports) => {
      payload.push_u8(0x01)
      payload.push_uleb_u32(exports.length())
      for export_item in exports {
        payload.push_utf8_name(export_item.name)
        payload.push_u8(export_item.kind)
        payload.push_uleb_u32(export_item.idx)
      }
    }
  }
  payload.to_bytes()
}

///|
fn encode_instance_decl(
  entry : InstanceEntry,
) -> Bytes raise ComponentTextError {
  let payload = ByteBuf::new()
  match entry.expr {
    Instantiate(component_idx, args) => {
      payload.push_u8(0x00)
      payload.push_uleb_u32(component_idx)
      payload.push_uleb_u32(args.length())
      for arg in args {
        payload.push_utf8_name(arg.name)
        push_sort_prefix(payload, arg.sort_tag, arg.core_kind)
        payload.push_uleb_u32(arg.idx)
      }
    }
    InlineExports(exports) => {
      payload.push_u8(0x01)
      payload.push_uleb_u32(exports.length())
      for export_item in exports {
        payload.push_u8(0x00)
        payload.push_utf8_name(export_item.name)
        push_sort_prefix(payload, export_item.sort_tag, export_item.core_kind)
        payload.push_uleb_u32(export_item.idx)
      }
    }
  }
  payload.to_bytes()
}

///|
fn encode_alias_core_export_decl(
  kind : Int,
  instance_idx : Int,
  name : String,
) -> Bytes {
  let payload = ByteBuf::new()
  payload.push_u8(0x00)
  payload.push_u8(kind)
  payload.push_u8(0x01)
  payload.push_uleb_u32(instance_idx)
  payload.push_utf8_name(name)
  payload.to_bytes()
}

///|
fn encode_alias_instance_export_decl(
  sort_tag : Int,
  core_kind : Int?,
  instance_idx : Int,
  name : String,
) -> Bytes raise ComponentTextError {
  let payload = ByteBuf::new()
  push_sort_prefix(payload, sort_tag, core_kind)
  payload.push_u8(0x00)
  payload.push_uleb_u32(instance_idx)
  payload.push_utf8_name(name)
  payload.to_bytes()
}

///|
fn encode_alias_outer_decl(
  sort_tag : Int,
  core_kind : Int?,
  count : Int,
  idx : Int,
) -> Bytes raise ComponentTextError {
  let payload = ByteBuf::new()
  if sort_tag == 0x00 && core_kind is Some(0x05) {
    payload.push_u8(0x00)
    payload.push_u8(0x10)
  } else {
    push_sort_prefix(payload, sort_tag, core_kind)
  }
  payload.push_u8(0x02)
  payload.push_uleb_u32(count)
  payload.push_uleb_u32(idx)
  payload.to_bytes()
}

///|
fn encode_module_type_alias_outer_core_type_decl(
  count : Int,
  idx : Int,
) -> Bytes {
  let payload = ByteBuf::new()
  payload.push_u8(0x10)
  payload.push_u8(0x01)
  payload.push_uleb_u32(count)
  payload.push_uleb_u32(idx)
  payload.to_bytes()
}

///|
fn parse_type_bound_bytes(
  bound_expr : SExpr,
  state : ComponentBuildState,
) -> Bytes raise ComponentTextError {
  let bound = if bound_expr is List(items) {
    items
  } else {
    raise Unsupported("type bound must be a list")
  }
  if bound.length() == 2 && bound[0] is Atom("eq") {
    let idx = resolve_reference(bound[1], state.type_names, "type")
    let bytes = ByteBuf::new()
    bytes.push_u8(0x00)
    bytes.push_uleb_u32(idx)
    return bytes.to_bytes()
  }
  if bound.length() == 2 &&
    bound[0] is Atom("sub") &&
    bound[1] is Atom("resource") {
    return Bytes::from_array([0x01])
  }
  raise Unsupported("unsupported type bound")
}

///|
fn parse_record_type_bytes(
  body : Array[SExpr],
  state : ComponentBuildState,
) -> Bytes raise ComponentTextError {
  let payload = ByteBuf::new()
  payload.push_u8(0x72)
  payload.push_uleb_u32(body.length() - 1)
  for i in 1..<body.length() {
    let field_items = if body[i] is List(items) {
      items
    } else {
      raise Unsupported("record field must be a list")
    }
    if field_items.length() < 3 || !(field_items[0] is Atom("field")) {
      raise Unsupported("record field must be `(field <name> <type>)`")
    }
    let name_index = if parse_optional_identifier(field_items, 1) is Some(_) {
      2
    } else {
      1
    }
    if name_index + 1 >= field_items.length() {
      raise Unsupported("record field is missing type")
    }
    let label = parse_name_text(field_items[name_index], "record field name")
    let ty = parse_valtype(field_items[name_index + 1], state)
    payload.push_utf8_name(label)
    push_valtype_encoding(payload, ty)
  }
  payload.to_bytes()
}

///|
fn resolve_variant_case_ref(
  expr : SExpr,
  case_ids : Array[NamedBinding],
) -> Int raise ComponentTextError {
  if expr is Atom(text) {
    if text.has_prefix("$") {
      if lookup_named_index(case_ids, text) is Some(idx) {
        return idx
      }
      raise Unsupported("unknown variant case '\{text}'")
    }
    if parse_decimal_index(text) is Some(idx) {
      return idx
    }
  }
  raise Unsupported("variant case refine must be an index or identifier")
}

///|
fn parse_variant_type_bytes(
  body : Array[SExpr],
  state : ComponentBuildState,
) -> Bytes raise ComponentTextError {
  let payload = ByteBuf::new()
  let case_ids : Array[NamedBinding] = []
  payload.push_u8(0x71)
  payload.push_uleb_u32(body.length() - 1)
  for i in 1..<body.length() {
    let case_items = if body[i] is List(items) {
      items
    } else {
      raise Unsupported("variant case must be a list")
    }
    if case_items.length() < 2 || !(case_items[0] is Atom("case")) {
      raise Unsupported("variant case must start with `case`")
    }
    let case_id = parse_optional_identifier(case_items, 1)
    let label_index = if case_id is Some(_) { 2 } else { 1 }
    if label_index >= case_items.length() {
      raise Unsupported("variant case is missing name")
    }
    let label = parse_name_text(case_items[label_index], "variant case name")
    let mut ty_opt : ValTypeEncoding? = None
    let mut refines_opt : SExpr? = None
    for j in (label_index + 1)..<case_items.length() {
      let item = case_items[j]
      if item is List(refines_items) &&
        refines_items.length() == 2 &&
        refines_items[0] is Atom("refines") {
        refines_opt = Some(refines_items[1])
        continue
      }
      if ty_opt is Some(_) {
        raise Unsupported("variant case payload must appear at most once")
      }
      ty_opt = Some(parse_valtype(item, state))
    }
    payload.push_utf8_name(label)
    if ty_opt is Some(ty) {
      payload.push_u8(0x01)
      push_valtype_encoding(payload, ty)
    } else {
      payload.push_u8(0x00)
    }
    if refines_opt is Some(refines_expr) {
      payload.push_u8(0x01)
      payload.push_uleb_u32(resolve_variant_case_ref(refines_expr, case_ids))
    } else {
      payload.push_u8(0x00)
    }
    bind_named_index(case_ids, case_id, i - 1)
  }
  payload.to_bytes()
}

///|
fn parse_tuple_type_bytes(
  body : Array[SExpr],
  state : ComponentBuildState,
) -> Bytes raise ComponentTextError {
  let payload = ByteBuf::new()
  payload.push_u8(0x6f)
  payload.push_uleb_u32(body.length() - 1)
  for i in 1..<body.length() {
    let ty = parse_valtype(body[i], state)
    push_valtype_encoding(payload, ty)
  }
  payload.to_bytes()
}

///|
fn parse_flags_or_enum_type_bytes(
  opcode : Int,
  body : Array[SExpr],
) -> Bytes raise ComponentTextError {
  let payload = ByteBuf::new()
  payload.push_u8(opcode)
  payload.push_uleb_u32(body.length() - 1)
  for i in 1..<body.length() {
    payload.push_utf8_name(parse_name_text(body[i], "case name"))
  }
  payload.to_bytes()
}

///|
fn parse_result_type_bytes(
  body : Array[SExpr],
  state : ComponentBuildState,
) -> Bytes raise ComponentTextError {
  let mut ok : ValTypeEncoding? = None
  let mut err : ValTypeEncoding? = None
  for i in 1..<body.length() {
    let item = body[i]
    if item is List(parts) && parts.length() == 2 && parts[0] is Atom("error") {
      if err is Some(_) {
        raise Unsupported("result error type must appear at most once")
      }
      err = Some(parse_valtype(parts[1], state))
      continue
    }
    if ok is Some(_) {
      raise Unsupported("result ok type must appear at most once")
    }
    ok = Some(parse_valtype(item, state))
  }
  let payload = ByteBuf::new()
  payload.push_u8(0x6a)
  if ok is Some(ok_ty) {
    payload.push_u8(0x01)
    push_valtype_encoding(payload, ok_ty)
  } else {
    payload.push_u8(0x00)
  }
  if err is Some(err_ty) {
    payload.push_u8(0x01)
    push_valtype_encoding(payload, err_ty)
  } else {
    payload.push_u8(0x00)
  }
  payload.to_bytes()
}

///|
fn parse_future_or_stream_type_bytes(
  opcode : Int,
  body : Array[SExpr],
  state : ComponentBuildState,
) -> Bytes raise ComponentTextError {
  if body.length() > 2 {
    raise Unsupported("future/stream type takes at most one payload type")
  }
  let payload = ByteBuf::new()
  payload.push_u8(opcode)
  if body.length() == 1 {
    payload.push_u8(0x00)
  } else {
    payload.push_u8(0x01)
    push_valtype_encoding(payload, parse_valtype(body[1], state))
  }
  payload.to_bytes()
}

///|
fn parse_resource_type_bytes(
  body : Array[SExpr],
  state : ComponentBuildState,
) -> Bytes raise ComponentTextError {
  if body.length() < 2 {
    raise Unsupported("resource type is missing `(rep ...)`")
  }
  let rep_field = if body[1] is List(items) {
    items
  } else {
    raise Unsupported("resource `(rep ...)` must be a list")
  }
  if rep_field.length() != 2 || !(rep_field[0] is Atom("rep")) {
    raise Unsupported("resource representation must be `(rep <corevaltype>)`")
  }
  let rep = parse_core_valtype_opcode(rep_field[1])
  let mut dtor_idx : Int? = None
  for i in 2..<body.length() {
    let field = if body[i] is List(items) {
      items
    } else {
      raise Unsupported("resource option must be a list")
    }
    if field.length() == 2 && field[0] is Atom("dtor") {
      dtor_idx = Some(parse_core_func_ref(field[1], state))
      continue
    }
    raise Unsupported("unsupported resource type option")
  }
  let payload = ByteBuf::new()
  payload.push_u8(0x3f)
  payload.push_u8(rep)
  if dtor_idx is Some(idx) {
    payload.push_u8(0x01)
    payload.push_uleb_u32(idx)
  } else {
    payload.push_u8(0x00)
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
  let mut body_index = if name_opt is Some(_) { 2 } else { 1 }
  let exports : Array[String] = []
  while body_index < field.length() {
    if field[body_index] is List(items) &&
      items.length() == 2 &&
      items[0] is Atom("export") {
      exports.push(parse_name_text(items[1], "type export name"))
      body_index += 1
      continue
    }
    break
  }
  if body_index >= field.length() {
    raise Unsupported("type declaration is missing a body")
  }
  if body_index + 1 != field.length() {
    raise Unsupported("type declaration currently supports one body expression")
  }

  let push_type_exports = fn(type_idx : Int) -> Unit raise ComponentTextError {
    for export_name in exports {
      push_export_decl(state, {
        name: export_name,
        sort_tag: 0x03,
        core_kind: None,
        idx: type_idx,
        desc: None,
      })
      finalize_export(state, 0x03, None, None)
    }
  }
  let body = field[body_index]
  if body is List(items) {
    if items.length() == 0 {
      raise Unsupported("type declaration body is empty")
    }
    let head = if items[0] is Atom(name) {
      name
    } else {
      raise Unsupported("type declaration head must be an atom")
    }
    if head == "func" {
      let sig = parse_func_sig(items, state)
      let type_idx = add_type_entry(
        state,
        encode_func_typedef(sig),
        Some(sig),
        name_opt,
      )
      push_type_exports(type_idx)
      return
    }
    if head == "record" {
      let type_idx = add_type_entry(
        state,
        parse_record_type_bytes(items, state),
        None,
        name_opt,
      )
      push_type_exports(type_idx)
      return
    }
    if head == "variant" {
      let type_idx = add_type_entry(
        state,
        parse_variant_type_bytes(items, state),
        None,
        name_opt,
      )
      push_type_exports(type_idx)
      return
    }
    if head == "tuple" {
      let type_idx = add_type_entry(
        state,
        parse_tuple_type_bytes(items, state),
        None,
        name_opt,
      )
      push_type_exports(type_idx)
      return
    }
    if head == "list" {
      if items.length() != 2 {
        raise Unsupported("list type must be `(list <valtype>)`")
      }
      let payload = ByteBuf::new()
      payload.push_u8(0x70)
      push_valtype_encoding(payload, parse_valtype(items[1], state))
      let type_idx = add_type_entry(state, payload.to_bytes(), None, name_opt)
      push_type_exports(type_idx)
      return
    }
    if head == "option" {
      if items.length() != 2 {
        raise Unsupported("option type must be `(option <valtype>)`")
      }
      let payload = ByteBuf::new()
      payload.push_u8(0x6b)
      push_valtype_encoding(payload, parse_valtype(items[1], state))
      let type_idx = add_type_entry(state, payload.to_bytes(), None, name_opt)
      push_type_exports(type_idx)
      return
    }
    if head == "result" {
      let type_idx = add_type_entry(
        state,
        parse_result_type_bytes(items, state),
        None,
        name_opt,
      )
      push_type_exports(type_idx)
      return
    }
    if head == "flags" {
      let type_idx = add_type_entry(
        state,
        parse_flags_or_enum_type_bytes(0x6e, items),
        None,
        name_opt,
      )
      push_type_exports(type_idx)
      return
    }
    if head == "enum" {
      let type_idx = add_type_entry(
        state,
        parse_flags_or_enum_type_bytes(0x6d, items),
        None,
        name_opt,
      )
      push_type_exports(type_idx)
      return
    }
    if head == "own" || head == "borrow" {
      if items.length() != 2 {
        raise Unsupported("\{head} type must be `(\{head} <type>)`")
      }
      let payload = ByteBuf::new()
      payload.push_u8(if head == "own" { 0x69 } else { 0x68 })
      payload.push_uleb_u32(
        resolve_reference(items[1], state.type_names, "type"),
      )
      let type_idx = add_type_entry(state, payload.to_bytes(), None, name_opt)
      push_type_exports(type_idx)
      return
    }
    if head == "future" {
      let type_idx = add_type_entry(
        state,
        parse_future_or_stream_type_bytes(0x65, items, state),
        None,
        name_opt,
      )
      push_type_exports(type_idx)
      return
    }
    if head == "stream" {
      let type_idx = add_type_entry(
        state,
        parse_future_or_stream_type_bytes(0x66, items, state),
        None,
        name_opt,
      )
      push_type_exports(type_idx)
      return
    }
    if head == "resource" {
      let type_idx = add_type_entry(
        state,
        parse_resource_type_bytes(items, state),
        None,
        name_opt,
      )
      push_type_exports(type_idx)
      return
    }
    if head == "component" {
      let type_idx = add_type_entry(
        state,
        build_inline_component_type_bytes(items, 1, state),
        None,
        name_opt,
      )
      push_type_exports(type_idx)
      return
    }
    if head == "instance" {
      let type_idx = add_type_entry(
        state,
        build_inline_instance_type_bytes(items, 1, state),
        None,
        name_opt,
      )
      push_type_exports(type_idx)
      return
    }
  }
  if body is Atom(name) {
    if prim_type_opcode(name) is Some(opcode) {
      let payload = ByteBuf::new()
      payload.push_u8(opcode)
      let type_idx = add_type_entry(state, payload.to_bytes(), None, name_opt)
      push_type_exports(type_idx)
      return
    }
  }
  raise Unsupported("unsupported type declaration")
}

///|
fn parse_alias_sort_spec(
  expr : SExpr,
) -> AliasSortSpec raise ComponentTextError {
  let sort_items = if expr is List(items) {
    items
  } else {
    raise Unsupported("alias sort descriptor must be a list")
  }
  if sort_items.length() == 0 {
    raise Unsupported("alias sort descriptor is empty")
  }
  if sort_items[0] is Atom("core") {
    if sort_items.length() < 2 {
      raise Unsupported("core alias sort descriptor is incomplete")
    }
    let core_kind = if sort_items[1] is Atom(sort_name) {
      if parse_core_sort_kind(sort_name) is Some(kind) {
        kind
      } else {
        raise Unsupported("unsupported core alias sort '\{sort_name}'")
      }
    } else {
      raise Unsupported("core alias sort must be an atom")
    }
    return {
      sort_tag: 0x00,
      core_kind: Some(core_kind),
      name_opt: parse_optional_identifier(sort_items, 2),
    }
  }
  let sort_tag = if sort_items[0] is Atom(sort_name) {
    if parse_component_sort_tag(sort_name) is Some(tag) {
      tag
    } else {
      raise Unsupported("unsupported alias sort '\{sort_name}'")
    }
  } else {
    raise Unsupported("alias sort must be an atom")
  }
  {
    sort_tag,
    core_kind: None,
    name_opt: parse_optional_identifier(sort_items, 1),
  }
}

///|
fn bind_alias_name(
  state : ComponentBuildState,
  sort_tag : Int,
  core_kind : Int?,
  name_opt : String?,
  idx : Int,
) -> Unit raise ComponentTextError {
  if sort_tag == 0x00 {
    let kind = match core_kind {
      Some(kind) => kind
      None => raise Unsupported("core alias is missing kind")
    }
    match kind {
      0x00 => bind_named_index(state.core_func_names, name_opt, idx)
      0x01 => bind_named_index(state.core_table_names, name_opt, idx)
      0x02 => bind_named_index(state.core_memory_names, name_opt, idx)
      0x03 => bind_named_index(state.core_global_names, name_opt, idx)
      0x04 => bind_named_index(state.core_tag_names, name_opt, idx)
      0x05 => bind_named_index(state.core_type_names, name_opt, idx)
      0x11 => bind_named_index(state.core_module_names, name_opt, idx)
      0x12 => bind_named_index(state.core_instance_names, name_opt, idx)
      _ => ()
    }
    return
  }
  match sort_tag {
    0x01 => bind_named_index(state.func_names, name_opt, idx)
    0x03 => bind_named_index(state.type_names, name_opt, idx)
    0x04 => bind_named_index(state.component_names, name_opt, idx)
    0x05 => bind_named_index(state.instance_names, name_opt, idx)
    _ => ()
  }
}

///|
fn allocate_alias_index(
  state : ComponentBuildState,
  sort_tag : Int,
  core_kind : Int?,
  alias_name_opt : String?,
) -> Int raise ComponentTextError {
  let idx = if sort_tag == 0x00 {
    let kind = match core_kind {
      Some(kind) => kind
      None => raise Unsupported("core alias is missing kind")
    }
    match kind {
      0x00 => {
        let idx = state.next_core_func_idx
        state.next_core_func_idx += 1
        idx
      }
      0x01 => {
        let idx = state.next_core_table_idx
        state.next_core_table_idx += 1
        idx
      }
      0x02 => {
        let idx = state.next_core_memory_idx
        state.next_core_memory_idx += 1
        idx
      }
      0x03 => {
        let idx = state.next_core_global_idx
        state.next_core_global_idx += 1
        idx
      }
      0x04 => {
        let idx = state.next_core_tag_idx
        state.next_core_tag_idx += 1
        idx
      }
      0x05 => {
        let idx = state.next_core_type_idx
        state.next_core_type_idx += 1
        idx
      }
      0x11 => {
        let idx = state.next_core_module_idx
        state.next_core_module_idx += 1
        idx
      }
      0x12 => {
        let idx = state.next_core_instance_idx
        state.next_core_instance_idx += 1
        idx
      }
      _ => raise Unsupported("unsupported core alias kind \{kind}")
    }
  } else {
    match sort_tag {
      0x01 => {
        let idx = state.next_func_idx
        state.next_func_idx += 1
        idx
      }
      0x03 => {
        let idx = state.next_type_idx
        state.next_type_idx += 1
        idx
      }
      0x04 => {
        let idx = state.next_component_idx
        state.next_component_idx += 1
        idx
      }
      0x05 => {
        let idx = state.next_instance_idx
        state.next_instance_idx += 1
        idx
      }
      _ => raise Unsupported("unsupported alias sort tag \{sort_tag}")
    }
  }
  bind_alias_name(state, sort_tag, core_kind, alias_name_opt, idx)
  idx
}

///|
fn parse_core_alias_binding(
  state : ComponentBuildState,
  kind : Int,
  instance_idx : Int,
  export_name : String,
  alias_name_opt : String?,
) -> Int raise ComponentTextError {
  for binding in state.core_alias_bindings {
    if binding.kind == kind &&
      binding.instance_idx == instance_idx &&
      binding.name == export_name {
      bind_alias_name(state, 0x00, Some(kind), alias_name_opt, binding.idx)
      return binding.idx
    }
  }
  let idx = allocate_alias_index(state, 0x00, Some(kind), alias_name_opt)
  let alias_decl = encode_alias_core_export_decl(
    kind, instance_idx, export_name,
  )
  push_ordered_section(state, 6, alias_decl)
  state.core_alias_bindings.push({ kind, instance_idx, name: export_name, idx })
  idx
}

///|
fn parse_core_func_ref(
  expr : SExpr,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if expr is Atom(_) {
    return resolve_reference(expr, state.core_func_names, "core func")
  }
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
  if start + 1 == items.length() {
    return resolve_reference(items[start], state.core_func_names, "core func")
  }
  if start + 2 != items.length() {
    raise Unsupported(
      "function reference must be `<func>` or `<instance> <export>`",
    )
  }
  let instance_idx = resolve_reference(
    items[start],
    state.core_instance_names,
    "core instance",
  )
  let export_name = parse_name_text(items[start + 1], "core export name")
  parse_core_alias_binding(state, 0x00, instance_idx, export_name, None)
}

///|
fn parse_core_memory_ref(
  expr : SExpr,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if expr is Atom(_) {
    return resolve_reference(expr, state.core_memory_names, "core memory")
  }
  let sort_ref = parse_core_sort_ref(expr, state)
  if sort_ref.kind != 0x02 {
    raise Unsupported("expected core memory reference")
  }
  sort_ref.idx
}

///|
fn parse_core_func_ref_expr(
  expr : SExpr,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if expr is Atom(_) {
    resolve_reference(expr, state.core_func_names, "core func")
  } else {
    parse_core_func_ref(expr, state)
  }
}

///|
fn parse_component_func_ref(
  expr : SExpr,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if expr is Atom(_) {
    return resolve_reference(expr, state.func_names, "function")
  }
  let sort_ref = parse_component_sort_ref(expr, state)
  if sort_ref.sort_tag != 0x01 || sort_ref.core_kind is Some(_) {
    raise Unsupported("expected component function reference")
  }
  sort_ref.idx
}

///|
fn parse_canon_option(
  option_expr : SExpr,
  state : ComponentBuildState,
  option_bytes : ByteBuf,
) -> Unit raise ComponentTextError {
  if option_expr is Atom(atom_name) {
    if atom_name == "string-encoding=utf8" {
      option_bytes.push_u8(0x00)
      return
    }
    if atom_name == "string-encoding=utf16" {
      option_bytes.push_u8(0x01)
      return
    }
    if atom_name == "string-encoding=latin1+utf16" {
      option_bytes.push_u8(0x02)
      return
    }
    if atom_name == "async" {
      option_bytes.push_u8(0x06)
      return
    }
    raise Unsupported("unsupported canonical option")
  }
  let option_items = if option_expr is List(items) {
    items
  } else {
    raise Unsupported("unsupported canonical option")
  }
  if option_items.length() == 0 {
    raise Unsupported("empty canonical option")
  }
  if option_items[0] is Atom("memory") {
    if option_items.length() != 2 && option_items.length() != 3 {
      raise Unsupported("memory option must be `(memory <memory-ref>)`")
    }
    let memory_idx = if option_items.length() == 2 {
      parse_core_memory_ref(option_items[1], state)
    } else {
      let instance_idx = resolve_reference(
        option_items[1],
        state.core_instance_names,
        "core instance",
      )
      let export_name = parse_name_text(option_items[2], "memory export name")
      parse_core_alias_binding(state, 0x02, instance_idx, export_name, None)
    }
    option_bytes.push_u8(0x03)
    option_bytes.push_uleb_u32(memory_idx)
    return
  }
  if option_items[0] is Atom("realloc") {
    if option_items.length() != 2 && option_items.length() != 3 {
      raise Unsupported("realloc option must be `(realloc <core-func-ref>)`")
    }
    let func_idx = if option_items.length() == 2 {
      parse_core_func_ref_expr(option_items[1], state)
    } else {
      let instance_idx = resolve_reference(
        option_items[1],
        state.core_instance_names,
        "core instance",
      )
      let export_name = parse_name_text(option_items[2], "realloc export name")
      parse_core_alias_binding(state, 0x00, instance_idx, export_name, None)
    }
    option_bytes.push_u8(0x04)
    option_bytes.push_uleb_u32(func_idx)
    return
  }
  if option_items[0] is Atom("post-return") {
    if option_items.length() != 2 && option_items.length() != 3 {
      raise Unsupported(
        "post-return option must be `(post-return <core-func-ref>)`",
      )
    }
    let func_idx = if option_items.length() == 2 {
      parse_core_func_ref_expr(option_items[1], state)
    } else {
      let instance_idx = resolve_reference(
        option_items[1],
        state.core_instance_names,
        "core instance",
      )
      let export_name = parse_name_text(
        option_items[2],
        "post-return export name",
      )
      parse_core_alias_binding(state, 0x00, instance_idx, export_name, None)
    }
    option_bytes.push_u8(0x05)
    option_bytes.push_uleb_u32(func_idx)
    return
  }
  if option_items[0] is Atom("callback") {
    if option_items.length() != 2 {
      raise Unsupported("callback option must be `(callback <core-func-ref>)`")
    }
    let callback_idx = parse_core_func_ref_expr(option_items[1], state)
    option_bytes.push_u8(0x07)
    option_bytes.push_uleb_u32(callback_idx)
    return
  }
  if option_items.length() == 1 && option_items[0] is Atom(single_name) {
    parse_canon_option(Atom(single_name), state, option_bytes)
    return
  }
  raise Unsupported("unsupported canonical option")
}

///|
fn parse_canon_options(
  canon_items : Array[SExpr],
  start : Int,
  end_exclusive : Int,
  state : ComponentBuildState,
) -> (Int, Bytes) raise ComponentTextError {
  let option_bytes = ByteBuf::new()
  let mut option_count = 0
  for i in start..<end_exclusive {
    parse_canon_option(canon_items[i], state, option_bytes)
    option_count += 1
  }
  (option_count, option_bytes.to_bytes())
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
  let (option_count, option_payload) = parse_canon_options(
    canon_items,
    3,
    canon_items.length(),
    state,
  )
  let out = ByteBuf::new()
  out.push_u8(0x00)
  out.push_u8(0x00)
  out.push_uleb_u32(core_func_idx)
  out.push_uleb_u32(option_count)
  out.push_bytes(option_payload)
  out.push_uleb_u32(type_idx)
  out.to_bytes()
}

///|
fn parse_canon_lower(
  canon_items : Array[SExpr],
  state : ComponentBuildState,
  options_end : Int,
) -> Bytes raise ComponentTextError {
  if canon_items.length() < 3 {
    raise Unsupported("`canon lower` requires a function reference")
  }
  let func_idx = parse_component_func_ref(canon_items[2], state)
  let (option_count, option_payload) = parse_canon_options(
    canon_items, 3, options_end, state,
  )
  let out = ByteBuf::new()
  out.push_u8(0x01)
  out.push_u8(0x00)
  out.push_uleb_u32(func_idx)
  out.push_uleb_u32(option_count)
  out.push_bytes(option_payload)
  out.to_bytes()
}

///|
fn canon_prim_sleb(opcode : Int) -> Int raise ComponentTextError {
  match opcode {
    0x7f => -1
    0x7e => -2
    0x7d => -3
    0x7c => -4
    0x7b => -5
    0x7a => -6
    0x79 => -7
    0x78 => -8
    0x77 => -9
    0x76 => -10
    0x75 => -11
    0x74 => -12
    0x73 => -13
    _ => raise Unsupported("unsupported canonical result primitive type")
  }
}

///|
fn push_canon_valtype(
  out : ByteBuf,
  ty : ValTypeEncoding,
) -> Unit raise ComponentTextError {
  match ty {
    Prim(opcode) => out.push_sleb_i32(canon_prim_sleb(opcode))
    TypeIdx(idx) => out.push_sleb_i32(idx)
  }
}

///|
fn parse_canon_result(
  result_field : SExpr,
  state : ComponentBuildState,
) -> Bytes raise ComponentTextError {
  let result_items = if result_field is List(items) {
    items
  } else {
    raise Unsupported("task.return result must be a list")
  }
  if result_items.length() == 0 || !(result_items[0] is Atom("result")) {
    raise Unsupported("task.return result must be `(result [<valtype>])`")
  }
  let value_index = if result_items.length() >= 3 &&
    parse_optional_identifier(result_items, 1) is Some(_) {
    2
  } else {
    1
  }
  let out = ByteBuf::new()
  if value_index >= result_items.length() {
    out.push_u8(0x01)
    out.push_u8(0x00)
    return out.to_bytes()
  }
  if value_index + 1 != result_items.length() {
    raise Unsupported("task.return supports at most one result value type")
  }
  out.push_u8(0x00)
  push_canon_valtype(out, parse_valtype(result_items[value_index], state))
  out.to_bytes()
}

///|
fn parse_component_type_ref(
  expr : SExpr,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if expr is List(items) && items.length() == 2 && items[0] is Atom("type") {
    return resolve_type_reference(items[1], state)
  }
  resolve_type_reference(expr, state)
}

///|
fn parse_core_type_ref(
  expr : SExpr,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if expr is Atom(_) {
    return resolve_reference(expr, state.core_type_names, "core type")
  }
  let sort_ref = parse_core_sort_ref(expr, state)
  if sort_ref.kind != 0x05 {
    raise Unsupported("expected core type reference")
  }
  sort_ref.idx
}

///|
fn parse_core_table_ref(
  expr : SExpr,
  state : ComponentBuildState,
) -> Int raise ComponentTextError {
  if expr is Atom(_) {
    return resolve_reference(expr, state.core_table_names, "core table")
  }
  let sort_ref = parse_core_sort_ref(expr, state)
  if sort_ref.kind != 0x01 {
    raise Unsupported("expected core table reference")
  }
  sort_ref.idx
}

///|
fn parse_canon_bool_flag(expr : SExpr) -> Bool raise ComponentTextError {
  if expr is Atom(flag_name) {
    if flag_name == "async" || flag_name == "cancellable" {
      return true
    }
  }
  raise Unsupported("canonical flag must be `async` or `cancellable`")
}

///|
fn parse_trailing_core_func_target(
  canon_items : Array[SExpr],
  allow_target : Bool,
) -> (Int, String?) raise ComponentTextError {
  if !allow_target || canon_items.length() < 3 {
    return (canon_items.length(), None)
  }
  let last = canon_items[canon_items.length() - 1]
  let target_items = if last is List(items) {
    items
  } else {
    return (canon_items.length(), None)
  }
  if target_items.length() < 2 ||
    !(target_items[0] is Atom("core")) ||
    !(target_items[1] is Atom("func")) {
    return (canon_items.length(), None)
  }
  let name_opt = parse_optional_identifier(target_items, 2)
  let expected_length = if name_opt is Some(_) { 3 } else { 2 }
  if target_items.length() != expected_length {
    raise Unsupported(
      "canonical core function target must be `(core func [$id])`",
    )
  }
  (canon_items.length() - 1, name_opt)
}

///|
fn parse_canon_decl(
  canon_items : Array[SExpr],
  state : ComponentBuildState,
  allow_target : Bool,
) -> (Bytes, Bool, String?) raise ComponentTextError {
  if canon_items.length() < 2 || !(canon_items[0] is Atom("canon")) {
    raise Unsupported("unsupported canonical declaration")
  }
  let (decl_end, target_name_opt) = parse_trailing_core_func_target(
    canon_items, allow_target,
  )
  let op_name = if canon_items[1] is Atom(name) {
    name
  } else {
    raise Unsupported("canonical operator must be an atom")
  }
  if op_name == "lower" {
    let decl = parse_canon_lower(canon_items, state, decl_end)
    return (decl, true, target_name_opt)
  }
  if op_name == "resource.new" ||
    op_name == "resource.drop" ||
    op_name == "resource.rep" {
    if decl_end != 3 {
      raise Unsupported("\{op_name} must be `(\{op_name} <type-ref>)`")
    }
    let type_idx = parse_component_type_ref(canon_items[2], state)
    let decl = ByteBuf::new()
    decl.push_u8(
      if op_name == "resource.new" {
        0x02
      } else if op_name == "resource.drop" {
        0x03
      } else {
        0x04
      },
    )
    decl.push_uleb_u32(type_idx)
    return (decl.to_bytes(), true, target_name_opt)
  }
  if op_name == "task.cancel" {
    if decl_end != 2 {
      raise Unsupported("task.cancel does not accept arguments")
    }
    return (Bytes::from_array([0x05]), true, target_name_opt)
  }
  if op_name == "subtask.cancel" {
    let mut is_async = false
    if decl_end == 3 {
      is_async = parse_canon_bool_flag(canon_items[2])
    } else if decl_end != 2 {
      raise Unsupported("subtask.cancel accepts at most one `async` flag")
    }
    let decl = ByteBuf::new()
    decl.push_u8(0x06)
    decl.push_u8(if is_async { 0x01 } else { 0x00 })
    return (decl.to_bytes(), true, target_name_opt)
  }
  if op_name == "task.return" {
    let mut index = 2
    let mut result_bytes = Bytes::from_array([0x01, 0x00])
    if index < decl_end &&
      canon_items[index] is List(items) &&
      items.length() > 0 &&
      items[0] is Atom("result") {
      result_bytes = parse_canon_result(canon_items[index], state)
      index += 1
    }
    let (option_count, option_payload) = parse_canon_options(
      canon_items, index, decl_end, state,
    )
    let decl = ByteBuf::new()
    decl.push_u8(0x09)
    decl.push_bytes(result_bytes)
    decl.push_uleb_u32(option_count)
    decl.push_bytes(option_payload)
    return (decl.to_bytes(), true, target_name_opt)
  }
  if op_name == "context.get" || op_name == "context.set" {
    if decl_end != 4 {
      raise Unsupported(
        "\{op_name} must be `(\{op_name} <corevaltype> <index>)`",
      )
    }
    let decl = ByteBuf::new()
    decl.push_u8(if op_name == "context.get" { 0x0a } else { 0x0b })
    decl.push_u8(parse_core_valtype_opcode(canon_items[2]))
    decl.push_uleb_u32(parse_u32_literal(canon_items[3], "context index"))
    return (decl.to_bytes(), true, target_name_opt)
  }
  if op_name == "thread.index" {
    if decl_end != 2 {
      raise Unsupported("thread.index does not accept arguments")
    }
    return (Bytes::from_array([0x26]), true, target_name_opt)
  }
  if op_name == "thread.resume-later" {
    if decl_end != 2 {
      raise Unsupported("thread.resume-later does not accept arguments")
    }
    return (Bytes::from_array([0x2a]), true, target_name_opt)
  }
  if op_name == "thread.new-indirect" {
    if decl_end != 4 {
      raise Unsupported(
        "thread.new-indirect must be `(thread.new-indirect <core-type> <core-table>)`",
      )
    }
    let decl = ByteBuf::new()
    decl.push_u8(0x27)
    decl.push_uleb_u32(parse_core_type_ref(canon_items[2], state))
    decl.push_uleb_u32(parse_core_table_ref(canon_items[3], state))
    return (decl.to_bytes(), true, target_name_opt)
  }
  if op_name == "thread.yield" ||
    op_name == "thread.yield-to" ||
    op_name == "thread.switch-to" ||
    op_name == "thread.suspend" {
    let mut flag = false
    if decl_end == 3 {
      flag = parse_canon_bool_flag(canon_items[2])
    } else if decl_end != 2 {
      raise Unsupported("\{op_name} accepts at most one flag")
    }
    let decl = ByteBuf::new()
    decl.push_u8(
      if op_name == "thread.yield" {
        0x0c
      } else if op_name == "thread.yield-to" {
        0x2b
      } else if op_name == "thread.switch-to" {
        0x28
      } else {
        0x29
      },
    )
    decl.push_u8(if flag { 0x01 } else { 0x00 })
    return (decl.to_bytes(), true, target_name_opt)
  }
  if op_name == "waitable-set.new" {
    if decl_end != 2 {
      raise Unsupported("waitable-set.new does not accept arguments")
    }
    return (Bytes::from_array([0x1f]), true, target_name_opt)
  }
  if op_name == "waitable-set.drop" {
    if decl_end != 2 {
      raise Unsupported("waitable-set.drop does not accept arguments")
    }
    return (Bytes::from_array([0x22]), true, target_name_opt)
  }
  if op_name == "waitable.join" {
    if decl_end != 2 {
      raise Unsupported("waitable.join does not accept arguments")
    }
    return (Bytes::from_array([0x23]), true, target_name_opt)
  }
  if op_name == "waitable-set.wait" || op_name == "waitable-set.poll" {
    let mut cancellable = false
    let mut memory_idx_opt : Int? = None
    for i in 2..<decl_end {
      let arg = canon_items[i]
      if arg is Atom(_) {
        cancellable = parse_canon_bool_flag(arg)
        continue
      }
      let arg_items = if arg is List(items) {
        items
      } else {
        raise Unsupported("unsupported waitable-set option")
      }
      if arg_items.length() > 0 && arg_items[0] is Atom("memory") {
        let option_payload = ByteBuf::new()
        parse_canon_option(arg, state, option_payload)
        if option_payload.bytes.length() < 2 || option_payload.bytes[0] != 0x03 {
          raise Unsupported("waitable-set memory option is invalid")
        }
        let memory_ref = if arg_items.length() == 2 {
          parse_core_memory_ref(arg_items[1], state)
        } else if arg_items.length() == 3 {
          let instance_idx = resolve_reference(
            arg_items[1],
            state.core_instance_names,
            "core instance",
          )
          let export_name = parse_name_text(arg_items[2], "memory export name")
          parse_core_alias_binding(state, 0x02, instance_idx, export_name, None)
        } else {
          raise Unsupported("memory option must be `(memory <memory-ref>)`")
        }
        memory_idx_opt = Some(memory_ref)
        continue
      }
      raise Unsupported("unsupported waitable-set option")
    }
    let memory_idx = match memory_idx_opt {
      Some(idx) => idx
      None => raise Unsupported("\{op_name} requires a memory option")
    }
    let decl = ByteBuf::new()
    decl.push_u8(if op_name == "waitable-set.wait" { 0x20 } else { 0x21 })
    decl.push_u8(if cancellable { 0x01 } else { 0x00 })
    decl.push_uleb_u32(memory_idx)
    return (decl.to_bytes(), true, target_name_opt)
  }
  if op_name == "subtask.drop" {
    if decl_end != 2 {
      raise Unsupported("subtask.drop does not accept arguments")
    }
    return (Bytes::from_array([0x0d]), true, target_name_opt)
  }
  if op_name == "stream.new" ||
    op_name == "stream.drop-readable" ||
    op_name == "stream.drop-writable" ||
    op_name == "future.new" ||
    op_name == "future.drop-readable" ||
    op_name == "future.drop-writable" {
    if decl_end != 3 {
      raise Unsupported("\{op_name} must be `(\{op_name} <type-ref>)`")
    }
    let type_idx = parse_component_type_ref(canon_items[2], state)
    let decl = ByteBuf::new()
    decl.push_u8(
      if op_name == "stream.new" {
        0x0e
      } else if op_name == "stream.drop-readable" {
        0x13
      } else if op_name == "stream.drop-writable" {
        0x14
      } else if op_name == "future.new" {
        0x15
      } else if op_name == "future.drop-readable" {
        0x1a
      } else {
        0x1b
      },
    )
    decl.push_uleb_u32(type_idx)
    return (decl.to_bytes(), true, target_name_opt)
  }
  if op_name == "stream.read" ||
    op_name == "stream.write" ||
    op_name == "future.read" ||
    op_name == "future.write" {
    if decl_end < 3 {
      raise Unsupported("\{op_name} requires a type reference")
    }
    let type_idx = parse_component_type_ref(canon_items[2], state)
    let (option_count, option_payload) = parse_canon_options(
      canon_items, 3, decl_end, state,
    )
    let decl = ByteBuf::new()
    decl.push_u8(
      if op_name == "stream.read" {
        0x0f
      } else if op_name == "stream.write" {
        0x10
      } else if op_name == "future.read" {
        0x16
      } else {
        0x17
      },
    )
    decl.push_uleb_u32(type_idx)
    decl.push_uleb_u32(option_count)
    decl.push_bytes(option_payload)
    return (decl.to_bytes(), true, target_name_opt)
  }
  if op_name == "stream.cancel-read" ||
    op_name == "stream.cancel-write" ||
    op_name == "future.cancel-read" ||
    op_name == "future.cancel-write" {
    if decl_end < 3 || decl_end > 4 {
      raise Unsupported("\{op_name} must be `(\{op_name} <type-ref> [async])`")
    }
    let type_idx = parse_component_type_ref(canon_items[2], state)
    let is_async = if decl_end == 4 {
      parse_canon_bool_flag(canon_items[3])
    } else {
      false
    }
    let decl = ByteBuf::new()
    decl.push_u8(
      if op_name == "stream.cancel-read" {
        0x11
      } else if op_name == "stream.cancel-write" {
        0x12
      } else if op_name == "future.cancel-read" {
        0x18
      } else {
        0x19
      },
    )
    decl.push_uleb_u32(type_idx)
    decl.push_u8(if is_async { 0x01 } else { 0x00 })
    return (decl.to_bytes(), true, target_name_opt)
  }
  raise Unsupported("unsupported canonical declaration")
}

///|
fn bump_sort_index_after_export(
  state : ComponentBuildState,
  sort_tag : Int,
  core_kind : Int?,
) -> Unit raise ComponentTextError {
  if sort_tag == 0x00 {
    let kind = match core_kind {
      Some(kind) => kind
      None => raise Unsupported("core export is missing sort kind")
    }
    match kind {
      0x00 => state.next_core_func_idx += 1
      0x01 => state.next_core_table_idx += 1
      0x02 => state.next_core_memory_idx += 1
      0x03 => state.next_core_global_idx += 1
      0x04 => state.next_core_tag_idx += 1
      0x05 => state.next_core_type_idx += 1
      0x11 => state.next_core_module_idx += 1
      0x12 => state.next_core_instance_idx += 1
      _ => raise Unsupported("unsupported core export sort")
    }
    return
  }
  match sort_tag {
    0x01 => state.next_func_idx += 1
    0x03 => state.next_type_idx += 1
    0x04 => state.next_component_idx += 1
    0x05 => state.next_instance_idx += 1
    _ => raise Unsupported("unsupported export sort")
  }
}

///|
fn current_sort_index_for_export(
  state : ComponentBuildState,
  sort_tag : Int,
  core_kind : Int?,
) -> Int raise ComponentTextError {
  if sort_tag == 0x00 {
    let kind = match core_kind {
      Some(kind) => kind
      None => raise Unsupported("core export is missing sort kind")
    }
    return match kind {
      0x00 => state.next_core_func_idx
      0x01 => state.next_core_table_idx
      0x02 => state.next_core_memory_idx
      0x03 => state.next_core_global_idx
      0x04 => state.next_core_tag_idx
      0x05 => state.next_core_type_idx
      0x11 => state.next_core_module_idx
      0x12 => state.next_core_instance_idx
      _ => raise Unsupported("unsupported core export sort")
    }
  }
  match sort_tag {
    0x01 => state.next_func_idx
    0x03 => state.next_type_idx
    0x04 => state.next_component_idx
    0x05 => state.next_instance_idx
    _ => raise Unsupported("unsupported export sort")
  }
}

///|
fn finalize_export(
  state : ComponentBuildState,
  sort_tag : Int,
  core_kind : Int?,
  export_id_opt : String?,
) -> Unit raise ComponentTextError {
  if export_id_opt is Some(name) {
    let export_idx = current_sort_index_for_export(state, sort_tag, core_kind)
    bind_alias_name(state, sort_tag, core_kind, Some(name), export_idx)
  }
  bump_sort_index_after_export(state, sort_tag, core_kind)
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
  let mut import_name_opt : SExpr? = None
  let mut alias_items_opt : Array[SExpr]? = None

  while index < field.length() {
    let item = field[index]
    index += 1
    if item is Atom("async") {
      sig_items.push(item)
      continue
    }
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
    if list[0] is Atom("import") {
      if list.length() != 2 {
        raise Unsupported("function import must be `(import <name>)`")
      }
      import_name_opt = Some(list[1])
      continue
    }
    if list[0] is Atom("alias") {
      alias_items_opt = Some(list)
      continue
    }
    sig_items.push(item)
  }

  if import_name_opt is Some(import_name) {
    if canon_items_opt is Some(_) {
      raise Unsupported("imported function cannot contain canonical body")
    }
    let desc : Array[SExpr] = [Atom("func")]
    if name_opt is Some(name) {
      desc.push(Atom(name))
    }
    if type_idx_opt is Some(type_idx) {
      desc.push(List([Atom("type"), Atom(type_idx.to_string())]))
    }
    let start = if name_opt is Some(_) { 2 } else { 1 }
    for i in start..<sig_items.length() {
      desc.push(sig_items[i])
    }
    parse_import([Atom("import"), import_name, List(desc)], state)
    return
  }

  if alias_items_opt is Some(alias_items) {
    if canon_items_opt is Some(_) || type_idx_opt is Some(_) {
      raise Unsupported(
        "function alias cannot combine with type/canonical body",
      )
    }
    if alias_items.length() != 4 || !(alias_items[1] is Atom("export")) {
      raise Unsupported(
        "function alias must be `(alias export <instance> <name>)`",
      )
    }
    let instance_idx = resolve_reference(
      alias_items[2],
      state.instance_names,
      "instance",
    )
    let export_name = parse_name_text(
      alias_items[3],
      "function alias export name",
    )
    let func_idx = allocate_alias_index(state, 0x01, None, name_opt)
    let alias_decl = encode_alias_instance_export_decl(
      0x01,
      None,
      instance_idx,
      export_name,
    )
    push_ordered_section(state, 6, alias_decl)
    for export_name in exports {
      push_export_decl(state, {
        name: export_name,
        sort_tag: 0x01,
        core_kind: None,
        idx: func_idx,
        desc: None,
      })
      bump_sort_index_after_export(state, 0x01, None)
    }
    return
  }

  let type_idx = if type_idx_opt is Some(type_idx) {
    type_idx
  } else {
    let sig = parse_func_sig(sig_items, state)
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
  push_ordered_section(state, 8, canon_bytes)

  for export_name in exports {
    push_export_decl(state, {
      name: export_name,
      sort_tag: 0x01,
      core_kind: None,
      idx: func_idx,
      desc: None,
    })
    bump_sort_index_after_export(state, 0x01, None)
  }
}

///|
fn parse_export_ascribed_desc(
  ascribed_expr_opt : SExpr?,
  sort_tag : Int,
  core_kind : Int?,
  state : ComponentBuildState,
) -> Bytes? raise ComponentTextError {
  let ascribed_expr = match ascribed_expr_opt {
    Some(expr) => expr
    None => return None
  }
  let ascribed = if ascribed_expr is List(items) {
    items
  } else {
    raise Unsupported("export ascribed descriptor must be a list")
  }
  if ascribed.length() == 0 {
    raise Unsupported("export ascribed descriptor is empty")
  }
  if sort_tag == 0x01 {
    if !(ascribed[0] is Atom("func")) {
      raise Unsupported("function export ascription must be `(func ...)`")
    }
    let mut type_idx_opt : Int? = None
    let mut start = 1
    if parse_optional_identifier(ascribed, 1) is Some(_) {
      start = 2
    }
    let sig_items : Array[SExpr] = [Atom("func")]
    for i in start..<ascribed.length() {
      let item = ascribed[i]
      if item is List(type_items) &&
        type_items.length() > 0 &&
        type_items[0] is Atom("type") {
        type_idx_opt = Some(parse_type_use(type_items, state))
      } else {
        sig_items.push(item)
      }
    }
    let type_idx = if type_idx_opt is Some(type_idx) {
      type_idx
    } else {
      ensure_func_type(state, parse_func_sig(sig_items, state))
    }
    let payload = ByteBuf::new()
    payload.push_u8(0x01)
    payload.push_uleb_u32(type_idx)
    return Some(payload.to_bytes())
  }
  if sort_tag == 0x04 || sort_tag == 0x05 {
    let is_component = sort_tag == 0x04
    if is_component {
      if !(ascribed[0] is Atom("component")) {
        raise Unsupported(
          "component export ascription must be `(component ...)`",
        )
      }
    } else if !(ascribed[0] is Atom("instance")) {
      raise Unsupported("instance export ascription must be `(instance ...)`")
    }
    let name_opt = parse_optional_identifier(ascribed, 1)
    let index = if name_opt is Some(_) { 2 } else { 1 }
    let type_idx = if index < ascribed.length() {
      let type_field = if ascribed[index] is List(items) {
        items
      } else {
        raise Unsupported("ascribed descriptor entries must be lists")
      }
      if type_field.length() > 0 &&
        type_field[0] is Atom("type") &&
        index + 1 == ascribed.length() {
        parse_type_use(type_field, state)
      } else if is_component {
        parse_inline_component_type(ascribed, index, state)
      } else {
        parse_inline_instance_type(ascribed, index, state)
      }
    } else if is_component {
      ensure_empty_component_type(state)
    } else {
      ensure_empty_instance_type(state)
    }
    let payload = ByteBuf::new()
    payload.push_u8(if is_component { 0x04 } else { 0x05 })
    payload.push_uleb_u32(type_idx)
    return Some(payload.to_bytes())
  }
  if sort_tag == 0x03 {
    if !(ascribed[0] is Atom("type")) {
      raise Unsupported("type export ascription must be `(type <bound>)`")
    }
    let bound_index = if parse_optional_identifier(ascribed, 1) is Some(_) {
      2
    } else {
      1
    }
    if bound_index >= ascribed.length() || bound_index + 1 != ascribed.length() {
      raise Unsupported("type export ascription must provide one bound")
    }
    let payload = ByteBuf::new()
    payload.push_u8(0x03)
    payload.push_bytes(parse_type_bound_bytes(ascribed[bound_index], state))
    return Some(payload.to_bytes())
  }
  if sort_tag == 0x00 {
    if core_kind is Some(kind) {
      raise Unsupported(
        "core export ascription for sort \{kind} is not supported yet",
      )
    }
    raise Unsupported("core export ascription is not supported yet")
  }
  raise Unsupported("unsupported export ascription")
}

///|
fn parse_export_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  if field.length() < 2 || field.length() > 5 {
    raise Unsupported(
      "export form expects `(export <name> <desc> [<ascribed>])`",
    )
  }
  let export_id_opt = parse_optional_identifier(field, 1)
  let name_index = if export_id_opt is Some(_) { 2 } else { 1 }
  let desc_index = name_index + 1
  if desc_index + 1 < field.length() - 1 {
    raise Unsupported(
      "export form expects `(export <name> <desc> [<ascribed>])`",
    )
  }
  let name = parse_name_text(field[name_index], "export name")
  if desc_index >= field.length() {
    if state.next_component_idx > 0 {
      push_export_decl(state, {
        name,
        sort_tag: 0x04,
        core_kind: None,
        idx: state.next_component_idx - 1,
        desc: None,
      })
      finalize_export(state, 0x04, None, export_id_opt)
      return
    }
    if state.next_instance_idx > 0 {
      push_export_decl(state, {
        name,
        sort_tag: 0x05,
        core_kind: None,
        idx: state.next_instance_idx - 1,
        desc: None,
      })
      finalize_export(state, 0x05, None, export_id_opt)
      return
    }
    if state.next_func_idx > 0 {
      push_export_decl(state, {
        name,
        sort_tag: 0x01,
        core_kind: None,
        idx: state.next_func_idx - 1,
        desc: None,
      })
      finalize_export(state, 0x01, None, export_id_opt)
      return
    }
    if state.next_type_idx > 0 {
      push_export_decl(state, {
        name,
        sort_tag: 0x03,
        core_kind: None,
        idx: state.next_type_idx - 1,
        desc: None,
      })
      finalize_export(state, 0x03, None, export_id_opt)
      return
    }
    if state.next_core_module_idx > 0 {
      push_export_decl(state, {
        name,
        sort_tag: 0x00,
        core_kind: Some(0x11),
        idx: state.next_core_module_idx - 1,
        desc: None,
      })
      finalize_export(state, 0x00, Some(0x11), export_id_opt)
      return
    }
    let empty_component = Bytes::from_array([
      0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00,
    ])
    state.sections_ordered.push({ section_id: 4, payload: empty_component })
    let component_idx = state.next_component_idx
    state.next_component_idx += 1
    push_export_decl(state, {
      name,
      sort_tag: 0x04,
      core_kind: None,
      idx: component_idx,
      desc: None,
    })
    finalize_export(state, 0x04, None, export_id_opt)
    return
  }
  let desc = if field[desc_index] is List(items) {
    items
  } else {
    raise Unsupported("export descriptor must be a list")
  }
  let ascribed_expr_opt = if desc_index + 1 < field.length() {
    Some(field[desc_index + 1])
  } else {
    None
  }
  if desc.length() < 2 {
    raise Unsupported("export descriptor is incomplete")
  }
  if desc[0] is Atom("func") ||
    desc[0] is Atom("component") ||
    desc[0] is Atom("instance") {
    let (sort_tag, context) = if desc[0] is Atom("func") {
      (0x01, "function")
    } else if desc[0] is Atom("component") {
      (0x04, "component")
    } else {
      (0x05, "instance")
    }
    if desc.length() == 2 {
      let idx = resolve_alias_sort_index(desc[1], state, sort_tag, None)
      push_export_decl(state, {
        name,
        sort_tag,
        core_kind: None,
        idx,
        desc: parse_export_ascribed_desc(
          ascribed_expr_opt,
          sort_tag,
          None,
          state,
        ),
      })
      finalize_export(state, sort_tag, None, export_id_opt)
      return
    }
    let mut current_instance_idx = resolve_reference(
      desc[1],
      state.instance_names,
      "instance",
    )
    let mut resolved_idx = -1
    for i in 2..<desc.length() {
      let export_name = parse_name_text(desc[i], "\{context} export name")
      let is_last = i == desc.length() - 1
      let alias_sort_tag = if is_last { sort_tag } else { 0x05 }
      let alias_idx = allocate_alias_index(state, alias_sort_tag, None, None)
      let alias_decl = encode_alias_instance_export_decl(
        alias_sort_tag,
        None,
        current_instance_idx,
        export_name,
      )
      push_ordered_section(state, 6, alias_decl)
      current_instance_idx = alias_idx
      if is_last {
        resolved_idx = alias_idx
      }
    }
    if resolved_idx < 0 {
      raise Unsupported("invalid export projection")
    }
    push_export_decl(state, {
      name,
      sort_tag,
      core_kind: None,
      idx: resolved_idx,
      desc: parse_export_ascribed_desc(ascribed_expr_opt, sort_tag, None, state),
    })
    finalize_export(state, sort_tag, None, export_id_opt)
    return
  }
  if desc[0] is Atom("type") {
    let idx = if desc.length() == 2 {
      resolve_alias_sort_index(desc[1], state, 0x03, None)
    } else {
      let mut current_instance_idx = resolve_reference(
        desc[1],
        state.instance_names,
        "instance",
      )
      let mut resolved_idx = -1
      for i in 2..<desc.length() {
        let export_name = parse_name_text(desc[i], "type export name")
        let alias_sort_tag = if i + 1 == desc.length() { 0x03 } else { 0x05 }
        let alias_idx = allocate_alias_index(state, alias_sort_tag, None, None)
        let alias_decl = encode_alias_instance_export_decl(
          alias_sort_tag,
          None,
          current_instance_idx,
          export_name,
        )
        push_ordered_section(state, 6, alias_decl)
        current_instance_idx = alias_idx
        if i + 1 == desc.length() {
          resolved_idx = alias_idx
        }
      }
      if resolved_idx < 0 {
        raise Unsupported("invalid type export projection")
      }
      resolved_idx
    }
    push_export_decl(state, {
      name,
      sort_tag: 0x03,
      core_kind: None,
      idx,
      desc: parse_export_ascribed_desc(ascribed_expr_opt, 0x03, None, state),
    })
    finalize_export(state, 0x03, None, export_id_opt)
    return
  }
  if desc[0] is Atom("core") {
    if desc.length() < 3 {
      raise Unsupported("core export descriptor is incomplete")
    }
    let core_kind = if desc[1] is Atom("module") {
      0x11
    } else if desc[1] is Atom("func") {
      0x00
    } else if desc[1] is Atom("table") {
      0x01
    } else if desc[1] is Atom("memory") {
      0x02
    } else if desc[1] is Atom("global") {
      0x03
    } else if desc[1] is Atom("tag") {
      0x04
    } else if desc[1] is Atom("type") {
      0x05
    } else {
      raise Unsupported("unsupported core export descriptor")
    }
    if desc.length() == 3 {
      let idx = resolve_alias_sort_index(desc[2], state, 0x00, Some(core_kind))
      push_export_decl(state, {
        name,
        sort_tag: 0x00,
        core_kind: Some(core_kind),
        idx,
        desc: parse_export_ascribed_desc(
          ascribed_expr_opt,
          0x00,
          Some(core_kind),
          state,
        ),
      })
      finalize_export(state, 0x00, Some(core_kind), export_id_opt)
      return
    }
    let mut current_instance_idx = resolve_reference(
      desc[2],
      state.instance_names,
      "instance",
    )
    let mut resolved_idx = -1
    for i in 3..<desc.length() {
      let export_name = parse_name_text(desc[i], "core export name")
      let is_last = i == desc.length() - 1
      let alias_sort_tag = if is_last { 0x00 } else { 0x05 }
      let alias_core_kind = if is_last { Some(core_kind) } else { None }
      let alias_idx = allocate_alias_index(
        state,
        alias_sort_tag,
        alias_core_kind,
        None,
      )
      let alias_decl = encode_alias_instance_export_decl(
        alias_sort_tag, alias_core_kind, current_instance_idx, export_name,
      )
      push_ordered_section(state, 6, alias_decl)
      current_instance_idx = alias_idx
      if is_last {
        resolved_idx = alias_idx
      }
    }
    if resolved_idx < 0 {
      raise Unsupported("invalid core export projection")
    }
    push_export_decl(state, {
      name,
      sort_tag: 0x00,
      core_kind: Some(core_kind),
      idx: resolved_idx,
      desc: parse_export_ascribed_desc(
        ascribed_expr_opt,
        0x00,
        Some(core_kind),
        state,
      ),
    })
    finalize_export(state, 0x00, Some(core_kind), export_id_opt)
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
  if start < field.length() {
    if start + 1 == field.length() {
      let single = if field[start] is List(items) { items } else { [] }
      if single.length() == 2 && single[0] is Atom("import") {
        let desc : Array[SExpr] = [Atom("core"), Atom("module")]
        if name_opt is Some(name) {
          desc.push(Atom(name))
        }
        parse_import([Atom("import"), single[1], List(desc)], state)
        return
      }
    }
  }

  let module_body : Array[SExpr] = []
  let export_names : Array[String] = []
  for i in start..<field.length() {
    let item = field[i]
    if item is List(items) && items.length() == 2 && items[0] is Atom("export") {
      export_names.push(parse_name_text(items[1], "core module export name"))
      continue
    }
    module_body.push(item)
  }
  let module_items : Array[SExpr] = [Atom("module")]
  for item in module_body {
    module_items.push(item)
  }
  let module_text = sexpr_to_wat(List(module_items))
  let mod = @wat.parse(module_text) catch {
    e => raise ParseError("failed to parse core module: \{e}")
  }
  let bytes = int_array_to_bytes(@cwasm.encode(mod))
  state.sections_ordered.push({ section_id: 1, payload: bytes })
  let idx = state.next_core_module_idx
  state.next_core_module_idx += 1
  bind_named_index(state.core_module_names, name_opt, idx)
  for export_name in export_names {
    push_export_decl(state, {
      name: export_name,
      sort_tag: 0x00,
      core_kind: Some(0x11),
      idx,
      desc: None,
    })
    finalize_export(state, 0x00, Some(0x11), None)
  }
}

///|
fn parse_core_valtype_opcode(expr : SExpr) -> Int raise ComponentTextError {
  if expr is Atom(name) {
    match name {
      "i32" => 0x7f
      "i64" => 0x7e
      "f32" => 0x7d
      "f64" => 0x7c
      "v128" => 0x7b
      "funcref" => 0x70
      "externref" => 0x6f
      _ => raise Unsupported("unsupported core value type '\{name}'")
    }
  } else {
    raise Unsupported("unsupported core value type")
  }
}

///|
fn parse_core_heap_type_sleb(
  expr : SExpr,
  core_type_names : Array[NamedBinding],
) -> Int raise ComponentTextError {
  if expr is Atom(name) {
    if name.has_prefix("$") {
      if lookup_named_index(core_type_names, name) is Some(idx) {
        return idx
      }
      raise Unsupported("unknown core type reference '\{name}'")
    }
    if parse_decimal_index(name) is Some(idx) {
      return idx
    }
    match name {
      "func" | "funcref" => return -16
      "extern" | "externref" => return -17
      "any" => return -18
      "eq" => return -19
      "i31" => return -20
      "struct" => return -21
      "array" => return -22
      "none" => return -15
      "nofunc" => return -13
      "noextern" => return -14
      "exn" => return -23
      "noexn" => return -12
      _ => raise Unsupported("unsupported core heap type '\{name}'")
    }
  }
  raise Unsupported("unsupported core heap type")
}

///|
fn push_core_valtype_encoding(
  payload : ByteBuf,
  expr : SExpr,
  core_type_names : Array[NamedBinding],
) -> Unit raise ComponentTextError {
  if expr is Atom(name) {
    match name {
      "i32" => payload.push_u8(0x7f)
      "i64" => payload.push_u8(0x7e)
      "f32" => payload.push_u8(0x7d)
      "f64" => payload.push_u8(0x7c)
      "v128" => payload.push_u8(0x7b)
      "funcref" => payload.push_u8(0x70)
      "externref" => payload.push_u8(0x6f)
      _ => raise Unsupported("unsupported core value type '\{name}'")
    }
    return
  }
  if expr is List(items) {
    if items.length() == 2 && items[0] is Atom("ref") {
      payload.push_u8(0x64)
      payload.push_sleb_i32(
        parse_core_heap_type_sleb(items[1], core_type_names),
      )
      return
    }
    if items.length() == 3 &&
      items[0] is Atom("ref") &&
      items[1] is Atom("null") {
      payload.push_u8(0x63)
      payload.push_sleb_i32(
        parse_core_heap_type_sleb(items[2], core_type_names),
      )
      return
    }
  }
  raise Unsupported("unsupported core value type")
}

///|
fn parse_core_func_type_bytes(
  items : Array[SExpr],
  core_type_names : Array[NamedBinding],
) -> Bytes raise ComponentTextError {
  let params = ByteBuf::new()
  let results = ByteBuf::new()
  let mut param_count = 0
  let mut result_count = 0
  let mut index = 1
  if index < items.length() {
    if items[index] is Atom(name) && name.has_prefix("$") {
      index += 1
    }
  }
  while index < items.length() {
    let field = if items[index] is List(field_items) {
      field_items
    } else {
      raise Unsupported("unsupported core func type field")
    }
    index += 1
    if field.length() == 0 {
      raise Unsupported("empty core func type field")
    }
    if field[0] is Atom("param") {
      let mut start = 1
      if start < field.length() {
        if field[start] is Atom(name) && name.has_prefix("$") {
          start += 1
        }
      }
      if start >= field.length() {
        raise Unsupported("core param field is missing type")
      }
      for i in start..<field.length() {
        push_core_valtype_encoding(params, field[i], core_type_names)
        param_count += 1
      }
      continue
    }
    if field[0] is Atom("result") {
      if field.length() < 2 {
        raise Unsupported("core result field is missing type")
      }
      for i in 1..<field.length() {
        push_core_valtype_encoding(results, field[i], core_type_names)
        result_count += 1
      }
      continue
    }
    raise Unsupported("unsupported core func type field")
  }

  let payload = ByteBuf::new()
  payload.push_u8(0x60)
  payload.push_uleb_u32(param_count)
  payload.push_bytes(params.to_bytes())
  payload.push_uleb_u32(result_count)
  payload.push_bytes(results.to_bytes())
  payload.to_bytes()
}

///|
fn parse_u32_literal(
  expr : SExpr,
  context : String,
) -> Int raise ComponentTextError {
  if expr is Atom(text) {
    if parse_decimal_index(text) is Some(value) {
      return value
    }
  }
  raise Unsupported("\{context} must be a non-negative integer literal")
}

///|
fn parse_core_extern_type_for_module_type(
  desc : Array[SExpr],
  decls : ByteBuf,
  func_type_count : Int,
  func_type_names : Array[NamedBinding],
) -> (Bytes, Int, Int) raise ComponentTextError {
  if desc.length() == 0 {
    raise Unsupported("core module extern type descriptor is empty")
  }
  let mut next_func_type_count = func_type_count
  let mut decl_count = 0
  let b = ByteBuf::new()
  let head = if desc[0] is Atom(name) {
    name
  } else {
    raise Unsupported("core module extern type must start with a sort atom")
  }

  if head == "func" {
    let mut type_use_opt : Int? = None
    let filtered : Array[SExpr] = [Atom("func")]
    let mut start = 1
    if parse_optional_identifier(desc, 1) is Some(_) {
      start = 2
    }
    for i in start..<desc.length() {
      let item = desc[i]
      if item is List(type_items) &&
        type_items.length() == 2 &&
        type_items[0] is Atom("type") {
        let idx = if type_items[1] is Atom(name) && name.has_prefix("$") {
          if lookup_named_index(func_type_names, name) is Some(idx) {
            idx
          } else {
            raise Unsupported("unknown core func type reference '\{name}'")
          }
        } else {
          parse_u32_literal(type_items[1], "core func type index")
        }
        type_use_opt = Some(idx)
        continue
      }
      filtered.push(item)
    }
    let type_idx = if type_use_opt is Some(type_idx) {
      if filtered.length() == 1 {
        type_idx
      } else {
        let func_type_bytes = parse_core_func_type_bytes(
          filtered, func_type_names,
        )
        decls.push_u8(0x01)
        decls.push_bytes(func_type_bytes)
        decl_count += 1
        let idx = next_func_type_count
        next_func_type_count += 1
        idx
      }
    } else {
      let func_type_bytes = parse_core_func_type_bytes(
        filtered, func_type_names,
      )
      decls.push_u8(0x01)
      decls.push_bytes(func_type_bytes)
      decl_count += 1
      let idx = next_func_type_count
      next_func_type_count += 1
      idx
    }
    b.push_u8(0x00)
    b.push_uleb_u32(type_idx)
    return (b.to_bytes(), next_func_type_count, decl_count)
  }

  if head == "table" {
    let mut start = 1
    if parse_optional_identifier(desc, 1) is Some(_) {
      start = 2
    }
    if start + 1 >= desc.length() {
      raise Unsupported(
        "core table type must be `(table <min> [<max>] <elemtype>)`",
      )
    }
    let elem_ty = parse_core_valtype_opcode(desc[desc.length() - 1])
    if elem_ty != 0x70 && elem_ty != 0x6f {
      raise Unsupported("core table elemtype must be `funcref` or `externref`")
    }
    let nlimits = desc.length() - start - 1
    let min = parse_u32_literal(desc[start], "table minimum")
    let max_opt = if nlimits == 2 {
      Some(parse_u32_literal(desc[start + 1], "table maximum"))
    } else if nlimits == 1 {
      None
    } else {
      raise Unsupported(
        "core table type must be `(table <min> [<max>] <elemtype>)`",
      )
    }
    b.push_u8(0x01)
    b.push_u8(elem_ty)
    b.push_u8(if max_opt is Some(_) { 0x01 } else { 0x00 })
    b.push_uleb_u32(min)
    if max_opt is Some(max) {
      b.push_uleb_u32(max)
    }
    return (b.to_bytes(), next_func_type_count, decl_count)
  }

  if head == "memory" {
    let mut start = 1
    if parse_optional_identifier(desc, 1) is Some(_) {
      start = 2
    }
    if start >= desc.length() {
      raise Unsupported("core memory type must be `(memory <min> [<max>])`")
    }
    let mut end = desc.length()
    let shared = if end > start && desc[end - 1] is Atom("shared") {
      end -= 1
      true
    } else {
      false
    }
    let nlimits = end - start
    let min = parse_u32_literal(desc[start], "memory minimum")
    let max_opt = if nlimits == 2 {
      Some(parse_u32_literal(desc[start + 1], "memory maximum"))
    } else if nlimits == 1 {
      None
    } else {
      raise Unsupported("core memory type must be `(memory <min> [<max>])`")
    }
    b.push_u8(0x02)
    let mut flags = if max_opt is Some(_) { 0x01 } else { 0x00 }
    if shared {
      flags = flags | 0x02
    }
    b.push_u8(flags)
    b.push_uleb_u32(min)
    if max_opt is Some(max) {
      b.push_uleb_u32(max)
    }
    return (b.to_bytes(), next_func_type_count, decl_count)
  }

  if head == "global" {
    let mut start = 1
    if parse_optional_identifier(desc, 1) is Some(_) {
      start = 2
    }
    if start >= desc.length() {
      raise Unsupported("core global type must be `(global <valtype>)`")
    }
    let (val_opcode, mutability) = if desc[start] is List(items) {
      if items.length() == 2 && items[0] is Atom("mut") {
        (parse_core_valtype_opcode(items[1]), 0x01)
      } else {
        raise Unsupported(
          "core global mutability must be `(global (mut <valtype>))`",
        )
      }
    } else {
      (parse_core_valtype_opcode(desc[start]), 0x00)
    }
    if start + 1 != desc.length() {
      raise Unsupported("core global type must be `(global <valtype>)`")
    }
    b.push_u8(0x03)
    b.push_u8(val_opcode)
    b.push_u8(mutability)
    return (b.to_bytes(), next_func_type_count, decl_count)
  }

  if head == "tag" {
    let mut start = 1
    if parse_optional_identifier(desc, 1) is Some(_) {
      start = 2
    }
    let type_idx = if start < desc.length() &&
      desc[start] is List(items) &&
      items.length() > 0 &&
      items[0] is Atom("type") {
      if items.length() != 2 {
        raise Unsupported("core tag type use must be `(type <index>)`")
      }
      parse_u32_literal(items[1], "core tag type index")
    } else {
      let func_items : Array[SExpr] = [Atom("func")]
      for i in start..<desc.length() {
        func_items.push(desc[i])
      }
      let func_type_bytes = parse_core_func_type_bytes(
        func_items, func_type_names,
      )
      decls.push_u8(0x01)
      decls.push_bytes(func_type_bytes)
      decl_count += 1
      let idx = next_func_type_count
      next_func_type_count += 1
      idx
    }
    b.push_u8(0x04)
    b.push_uleb_u32(type_idx)
    return (b.to_bytes(), next_func_type_count, decl_count)
  }

  raise Unsupported("unsupported core module extern type '\{head}'")
}

///|
fn parse_core_module_type_bytes(
  items : Array[SExpr],
  start : Int,
  state : ComponentBuildState,
) -> Bytes raise ComponentTextError {
  let decls = ByteBuf::new()
  let mut decl_count = 0
  let mut func_type_count = 0
  let func_type_names : Array[NamedBinding] = []

  for i in start..<items.length() {
    let field = if items[i] is List(field_items) {
      field_items
    } else {
      raise Unsupported("core module type declaration must be a list")
    }
    if field.length() == 0 {
      raise Unsupported("core module type declaration is empty")
    }
    if field[0] is Atom("alias") {
      if field.length() == 5 && field[1] is Atom("outer") {
        let sort_spec = parse_alias_sort_spec(field[4])
        let is_core_type_alias = (
            sort_spec.sort_tag == 0x03 && sort_spec.core_kind is None
          ) ||
          (sort_spec.sort_tag == 0x00 && sort_spec.core_kind is Some(0x05))
        if !is_core_type_alias {
          raise Unsupported("core module type alias must target `(type ...)`")
        }
        let inferred_outer_count = if field[3] is Atom(target_name) &&
          target_name.has_prefix("$") {
          if lookup_named_index(state.core_type_names, target_name) is Some(_) {
            Some(1)
          } else {
            let mut found : Int? = None
            for depth in 0..<state.outer_core_type_scopes.length() {
              if lookup_named_index(
                  state.outer_core_type_scopes[depth],
                  target_name,
                )
                is Some(_) {
                found = Some(depth + 2)
                break
              }
            }
            found
          }
        } else {
          None
        }
        let count = if field[2] is Atom(count_atom) {
          if parse_decimal_index(count_atom) is Some(count) {
            count
          } else if count_atom.has_prefix("$") {
            match inferred_outer_count {
              Some(depth) => depth
              None => 0
            }
          } else {
            raise Unsupported(
              "outer alias count must be a decimal index for now",
            )
          }
        } else {
          raise Unsupported("outer alias count must be a decimal index for now")
        }
        let target_idx = if field[3] is Atom(target_name) &&
          target_name.has_prefix("$") {
          if count == 1 &&
            lookup_named_index(state.core_type_names, target_name) is Some(idx) {
            idx
          } else if count > 1 &&
            count - 2 < state.outer_core_type_scopes.length() &&
            lookup_named_index(
              state.outer_core_type_scopes[count - 2],
              target_name,
            )
            is Some(idx) {
            idx
          } else if lookup_named_index(func_type_names, target_name)
            is Some(idx) {
            idx
          } else {
            resolve_reference(field[3], state.core_type_names, "core type")
          }
        } else {
          resolve_reference(field[3], func_type_names, "core type")
        }
        decls.push_u8(0x02)
        decls.push_bytes(
          encode_module_type_alias_outer_core_type_decl(count, target_idx),
        )
        decl_count += 1
        bind_named_index(func_type_names, sort_spec.name_opt, func_type_count)
        func_type_count += 1
        continue
      }
      raise Unsupported("unsupported core module type declaration")
    }
    if field[0] is Atom("import") {
      if field.length() != 4 {
        raise Unsupported(
          "core module type import must be `(import <module> <name> <type>)`",
        )
      }
      let mod_name = parse_name_text(field[1], "core module type import module")
      let import_name = parse_name_text(
        field[2],
        "core module type import name",
      )
      let type_desc = if field[3] is List(type_items) {
        type_items
      } else {
        raise Unsupported("core module type import descriptor must be a list")
      }
      let (extern_type, next_func_type_count, extra_decl_count) = parse_core_extern_type_for_module_type(
        type_desc, decls, func_type_count, func_type_names,
      )
      func_type_count = next_func_type_count
      decl_count += extra_decl_count
      decls.push_u8(0x00)
      decls.push_utf8_name(mod_name)
      decls.push_utf8_name(import_name)
      decls.push_bytes(extern_type)
      decl_count += 1
      continue
    }
    if field[0] is Atom("type") {
      let name_opt = parse_optional_identifier(field, 1)
      let body_index = if name_opt is Some(_) { 2 } else { 1 }
      if body_index >= field.length() || body_index + 1 != field.length() {
        raise Unsupported(
          "core module type declaration must define one type body",
        )
      }
      let body = if field[body_index] is List(type_items) {
        type_items
      } else {
        raise Unsupported("core module type body must be a list")
      }
      if body.length() == 0 || !(body[0] is Atom("func")) {
        raise Unsupported("unsupported core module type declaration")
      }
      let func_type_bytes = parse_core_func_type_bytes(body, func_type_names)
      decls.push_u8(0x01)
      decls.push_bytes(func_type_bytes)
      decl_count += 1
      let type_idx = func_type_count
      func_type_count += 1
      bind_named_index(func_type_names, name_opt, type_idx)
      continue
    }
    if field[0] is Atom("export") {
      if field.length() != 3 {
        raise Unsupported(
          "core module type export must be `(export <name> <type>)`",
        )
      }
      let export_name = parse_name_text(
        field[1],
        "core module type export name",
      )
      let type_desc = if field[2] is List(type_items) {
        type_items
      } else {
        raise Unsupported("core module type export descriptor must be a list")
      }
      let (extern_type, next_func_type_count, extra_decl_count) = parse_core_extern_type_for_module_type(
        type_desc, decls, func_type_count, func_type_names,
      )
      func_type_count = next_func_type_count
      decl_count += extra_decl_count
      decls.push_u8(0x03)
      decls.push_utf8_name(export_name)
      decls.push_bytes(extern_type)
      decl_count += 1
      continue
    }
    raise Unsupported("unsupported core module type declaration")
  }

  let payload = ByteBuf::new()
  payload.push_u8(0x50)
  payload.push_uleb_u32(decl_count)
  payload.push_bytes(decls.to_bytes())
  payload.to_bytes()
}

///|
fn parse_core_type_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  if field.length() < 3 {
    raise Unsupported("core type declaration is incomplete")
  }
  let name_opt = parse_optional_identifier(field, 2)
  let body_index = if name_opt is Some(_) { 3 } else { 2 }
  if body_index >= field.length() {
    raise Unsupported("core type declaration is missing a body")
  }
  let body = if field[body_index] is List(items) {
    items
  } else {
    raise Unsupported("core type declaration body must be a list")
  }
  if body.length() == 0 {
    raise Unsupported("core type declaration body is empty")
  }
  let bytes = if body[0] is Atom("module") {
    parse_core_module_type_bytes(body, 1, state)
  } else if body[0] is Atom("func") {
    parse_core_func_type_bytes(body, state.core_type_names)
  } else {
    raise Unsupported("unsupported core type declaration")
  }

  let idx = ensure_core_type_bytes(state, bytes)
  bind_named_index(state.core_type_names, name_opt, idx)
}

///|
fn parse_component_sort_tag(sort_name : String) -> Int? {
  match sort_name {
    "func" => Some(0x01)
    "value" => Some(0x02)
    "type" => Some(0x03)
    "component" => Some(0x04)
    "instance" => Some(0x05)
    _ => None
  }
}

///|
fn parse_component_sort_ref(
  expr : SExpr,
  state : ComponentBuildState,
) -> SortRef raise ComponentTextError {
  let items = if expr is List(items) {
    items
  } else {
    raise Unsupported("component sort reference must be a list")
  }
  if items.length() < 2 {
    raise Unsupported("component sort reference is incomplete")
  }
  if items[0] is Atom("core") {
    if items.length() < 3 {
      raise Unsupported("core sort reference is incomplete")
    }
    let core_sort = if items[1] is Atom(sort_name) {
      if parse_core_sort_kind(sort_name) is Some(kind) {
        kind
      } else {
        raise Unsupported("unsupported core sort '\{sort_name}'")
      }
    } else {
      raise Unsupported("core sort name must be an atom")
    }
    let idx = if items.length() == 3 {
      match core_sort {
        0x00 => resolve_reference(items[2], state.core_func_names, "core func")
        0x01 =>
          resolve_reference(items[2], state.core_table_names, "core table")
        0x02 =>
          resolve_reference(items[2], state.core_memory_names, "core memory")
        0x03 =>
          resolve_reference(items[2], state.core_global_names, "core global")
        0x04 => resolve_reference(items[2], state.core_tag_names, "core tag")
        0x05 => resolve_core_type_reference(items[2], state)
        0x11 => resolve_core_module_reference(items[2], state)
        0x12 =>
          resolve_reference(
            items[2],
            state.core_instance_names,
            "core instance",
          )
        _ => raise Unsupported("unsupported core sort reference")
      }
    } else {
      let mut current_instance_idx = resolve_reference(
        items[2],
        state.instance_names,
        "instance",
      )
      let mut resolved_idx = -1
      for i in 3..<items.length() {
        let export_name = parse_name_text(items[i], "core export name")
        let is_last = i + 1 == items.length()
        let alias_sort_tag = if is_last { 0x00 } else { 0x05 }
        let alias_core_kind = if is_last { Some(core_sort) } else { None }
        let alias_idx = allocate_alias_index(
          state,
          alias_sort_tag,
          alias_core_kind,
          None,
        )
        let alias_decl = encode_alias_instance_export_decl(
          alias_sort_tag, alias_core_kind, current_instance_idx, export_name,
        )
        push_ordered_section(state, 6, alias_decl)
        current_instance_idx = alias_idx
        if is_last {
          resolved_idx = alias_idx
        }
      }
      if resolved_idx < 0 {
        raise Unsupported("invalid core sort projection")
      }
      resolved_idx
    }
    return { name: "", sort_tag: 0x00, core_kind: Some(core_sort), idx }
  }
  let sort_name = if items[0] is Atom(sort_name) {
    sort_name
  } else {
    raise Unsupported("sort name must be an atom")
  }
  let sort_tag = if parse_component_sort_tag(sort_name) is Some(tag) {
    tag
  } else {
    raise Unsupported("unsupported sort reference '\{sort_name}'")
  }
  if items.length() == 2 {
    if sort_tag == 0x05 && items[1] is List(_) {
      let exports : Array[SortRef] = []
      for i in 1..<items.length() {
        let export_item = if items[i] is List(export_expr) {
          export_expr
        } else {
          raise Unsupported("instance inline export must be a list")
        }
        if export_item.length() != 3 || !(export_item[0] is Atom("export")) {
          raise Unsupported(
            "instance inline export must be `(export <name> <sort-ref>)`",
          )
        }
        let export_name = parse_name_text(
          export_item[1],
          "instance inline export name",
        )
        let export_ref = parse_component_sort_ref(export_item[2], state)
        exports.push({
          name: export_name,
          sort_tag: export_ref.sort_tag,
          core_kind: export_ref.core_kind,
          idx: export_ref.idx,
        })
      }
      let entry = InstanceEntry::{ expr: InlineExports(exports) }
      let instance_idx = state.next_instance_idx
      state.next_instance_idx += 1
      push_ordered_section(state, 5, encode_instance_decl(entry))
      return { name: "", sort_tag: 0x05, core_kind: None, idx: instance_idx }
    }
    let idx = match sort_tag {
      0x01 => resolve_reference(items[1], state.func_names, "function")
      0x03 => resolve_type_reference(items[1], state)
      0x04 => resolve_component_reference(items[1], state)
      0x05 => resolve_reference(items[1], state.instance_names, "instance")
      _ => raise Unsupported("unsupported component sort reference")
    }
    return { name: "", sort_tag, core_kind: None, idx }
  }
  if items.length() >= 3 &&
    (
      sort_tag == 0x01 ||
      sort_tag == 0x03 ||
      sort_tag == 0x04 ||
      sort_tag == 0x05
    ) {
    let mut current_instance_idx = resolve_reference(
      items[1],
      state.instance_names,
      "instance",
    )
    let mut resolved_idx = -1
    for i in 2..<items.length() {
      let export_name = parse_name_text(items[i], "instance export name")
      let alias_sort_tag = if i + 1 == items.length() { sort_tag } else { 0x05 }
      let alias_idx = allocate_alias_index(state, alias_sort_tag, None, None)
      let alias_decl = encode_alias_instance_export_decl(
        alias_sort_tag,
        None,
        current_instance_idx,
        export_name,
      )
      push_ordered_section(state, 6, alias_decl)
      current_instance_idx = alias_idx
      if i + 1 == items.length() {
        resolved_idx = alias_idx
      }
    }
    return { name: "", sort_tag, core_kind: None, idx: resolved_idx }
  }
  raise Unsupported("sort reference must be `(<sort> <index-or-id>)` for now")
}

///|
fn parse_instance_instantiate_arg(
  arg_expr : SExpr,
  state : ComponentBuildState,
) -> SortRef raise ComponentTextError {
  let arg = if arg_expr is List(items) {
    items
  } else {
    raise Unsupported("instance instantiate arg must be a list")
  }
  if arg.length() != 3 || !(arg[0] is Atom("with")) {
    raise Unsupported("instance instantiate arg must be `(with <name> <ref>)`")
  }
  let name = parse_name_text(arg[1], "instance instantiate import name")
  let sort_ref = parse_component_sort_ref(arg[2], state)
  {
    name,
    sort_tag: sort_ref.sort_tag,
    core_kind: sort_ref.core_kind,
    idx: sort_ref.idx,
  }
}

///|
fn parse_instance_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  let name_opt = parse_optional_identifier(field, 1)
  let expr_index = if name_opt is Some(_) { 2 } else { 1 }
  if expr_index >= field.length() {
    let empty = InstanceEntry::{ expr: InlineExports([]) }
    push_ordered_section(state, 5, encode_instance_decl(empty))
    let idx = state.next_instance_idx
    state.next_instance_idx += 1
    bind_named_index(state.instance_names, name_opt, idx)
    return
  }
  let expr = if field[expr_index] is List(items) {
    items
  } else {
    raise Unsupported("instance expression must be a list")
  }
  if expr.length() == 2 && expr[0] is Atom("export") {
    let export_names : Array[String] = []
    let mut cursor = expr_index
    while cursor < field.length() {
      let export_item = if field[cursor] is List(items) { items } else { break }
      if export_item.length() != 2 || !(export_item[0] is Atom("export")) {
        break
      }
      export_names.push(parse_name_text(export_item[1], "instance export name"))
      cursor += 1
    }
    if cursor >= field.length() {
      let exports : Array[SortRef] = []
      for export_name in export_names {
        exports.push({
          name: export_name,
          sort_tag: 0x01,
          core_kind: None,
          idx: 0,
        })
      }
      let entry = InstanceEntry::{ expr: InlineExports(exports) }
      push_ordered_section(state, 5, encode_instance_decl(entry))
      let idx = state.next_instance_idx
      state.next_instance_idx += 1
      bind_named_index(state.instance_names, name_opt, idx)
      return
    }
    if cursor + 1 != field.length() {
      raise Unsupported("unsupported instance expression")
    }
    let base_field : Array[SExpr] = [Atom("instance")]
    if name_opt is Some(name) {
      base_field.push(Atom(name))
    }
    base_field.push(field[cursor])
    parse_instance_field(base_field, state)
    let instance_idx = if name_opt is Some(name) {
      if lookup_named_index(state.instance_names, name) is Some(idx) {
        idx
      } else {
        state.next_instance_idx - 1
      }
    } else {
      state.next_instance_idx - 1
    }
    for export_name in export_names {
      push_export_decl(state, {
        name: export_name,
        sort_tag: 0x05,
        core_kind: None,
        idx: instance_idx,
        desc: None,
      })
      finalize_export(state, 0x05, None, None)
    }
    return
  }
  if expr.length() >= 2 && expr[0] is Atom("instantiate") {
    let component_ref = if expr[1] is List(_) {
      expr[1]
    } else {
      List([Atom("component"), expr[1]])
    }
    let sort_ref = parse_component_sort_ref(component_ref, state)
    if sort_ref.sort_tag != 0x04 || sort_ref.core_kind is Some(_) {
      raise Unsupported("instantiate expects a component reference")
    }
    let component_idx = sort_ref.idx
    let args : Array[SortRef] = []
    for i in 2..<expr.length() {
      args.push(parse_instance_instantiate_arg(expr[i], state))
    }
    let entry = InstanceEntry::{ expr: Instantiate(component_idx, args) }
    push_ordered_section(state, 5, encode_instance_decl(entry))
    let idx = state.next_instance_idx
    state.next_instance_idx += 1
    bind_named_index(state.instance_names, name_opt, idx)
    return
  }

  let inline_items : Array[SExpr] = []
  if expr.length() >= 1 &&
    expr[0] is Atom("instance") &&
    field.length() == expr_index + 1 {
    for i in 1..<expr.length() {
      inline_items.push(expr[i])
    }
  } else {
    for i in expr_index..<field.length() {
      inline_items.push(field[i])
    }
  }

  let mut import_field : Array[SExpr]? = None
  let exports : Array[SortRef] = []
  for item in inline_items {
    let list = if item is List(items) {
      items
    } else {
      raise Unsupported("instance expression items must be lists")
    }
    if list.length() == 0 {
      raise Unsupported("instance expression item cannot be empty")
    }
    if list[0] is Atom("import") {
      if list.length() != 2 {
        raise Unsupported("instance import sugar must be `(import <name>)`")
      }
      if import_field is Some(_) {
        raise Unsupported("instance import sugar can contain only one import")
      }
      let desc : Array[SExpr] = [Atom("instance")]
      if name_opt is Some(name) {
        desc.push(Atom(name))
      }
      import_field = Some([Atom("import"), list[1], List(desc)])
      continue
    }
    if list[0] is Atom("type") {
      if import_field is Some(import_desc) {
        let desc_items = if import_desc[2] is List(items) {
          items
        } else {
          raise Unsupported("instance import descriptor must be a list")
        }
        desc_items.push(List(list))
        continue
      }
      raise Unsupported("unsupported instance expression")
    }
    if !(list[0] is Atom("export")) {
      raise Unsupported("unsupported instance expression")
    }
    let export_name = if list.length() >= 2 {
      parse_name_text(list[1], "instance inline export name")
    } else {
      raise Unsupported("instance inline export is missing name")
    }
    if import_field is Some(import_desc) {
      let desc_items = if import_desc[2] is List(items) {
        items
      } else {
        raise Unsupported("instance import descriptor must be a list")
      }
      if list.length() == 2 {
        desc_items.push(List([Atom("export"), list[1], List([Atom("func")])]))
      } else if list.length() == 3 {
        desc_items.push(List([Atom("export"), list[1], list[2]]))
      } else {
        raise Unsupported(
          "instance import export sugar must be `(export <name> [<type-desc>])`",
        )
      }
      continue
    }
    if list.length() == 2 {
      exports.push({
        name: export_name,
        sort_tag: 0x01,
        core_kind: None,
        idx: 0,
      })
      continue
    }
    if list.length() != 3 {
      raise Unsupported(
        "instance inline export must be `(export <name> <sort-ref>)`",
      )
    }
    let sort_ref = parse_component_sort_ref(list[2], state)
    exports.push({
      name: export_name,
      sort_tag: sort_ref.sort_tag,
      core_kind: sort_ref.core_kind,
      idx: sort_ref.idx,
    })
  }

  if import_field is Some(import_field) {
    parse_import(import_field, state)
    return
  }

  let entry = InstanceEntry::{ expr: InlineExports(exports) }
  push_ordered_section(state, 5, encode_instance_decl(entry))
  let idx = state.next_instance_idx
  state.next_instance_idx += 1
  bind_named_index(state.instance_names, name_opt, idx)
}

///|
fn parse_core_sort_kind(sort_name : String) -> Int? {
  match sort_name {
    "func" => Some(0x00)
    "table" => Some(0x01)
    "memory" => Some(0x02)
    "global" => Some(0x03)
    "tag" => Some(0x04)
    "type" => Some(0x05)
    "module" => Some(0x11)
    "instance" => Some(0x12)
    _ => None
  }
}

///|
fn parse_core_sort_ref(
  expr : SExpr,
  state : ComponentBuildState,
) -> CoreSortRef raise ComponentTextError {
  let items = if expr is List(items) {
    items
  } else {
    raise Unsupported("core instantiate arg must be a list")
  }
  if items.length() < 2 {
    raise Unsupported("core instantiate arg is incomplete")
  }
  let kind_name = if items[0] is Atom(name) {
    name
  } else {
    raise Unsupported("core instantiate arg sort must be an atom")
  }
  let kind = if parse_core_sort_kind(kind_name) is Some(kind) {
    kind
  } else {
    raise Unsupported("unsupported core instantiate sort '\{kind_name}'")
  }

  if kind_name == "instance" {
    if items.length() == 2 && items[1] is Atom(_) {
      let idx = resolve_reference(
        items[1],
        state.core_instance_names,
        "core instance",
      )
      return { name: "", kind: 0x12, idx }
    }
    let exports : Array[CoreSortRef] = []
    for i in 1..<items.length() {
      let export_item = if items[i] is List(export_expr) {
        export_expr
      } else {
        raise Unsupported("core inline instance export must be a list")
      }
      if export_item.length() != 3 || !(export_item[0] is Atom("export")) {
        raise Unsupported(
          "core inline instance export must be `(export <name> <ref>)`",
        )
      }
      let export_name = parse_name_text(
        export_item[1],
        "core inline export name",
      )
      let export_ref = parse_core_sort_ref(export_item[2], state)
      exports.push({
        name: export_name,
        kind: export_ref.kind,
        idx: export_ref.idx,
      })
    }
    let entry = CoreInstanceEntry::{ expr: InlineExports(exports) }
    let core_instance_idx = state.next_core_instance_idx
    state.next_core_instance_idx += 1
    push_ordered_section(state, 2, encode_core_instance_decl(entry))
    return { name: "", kind: 0x12, idx: core_instance_idx }
  }

  if kind_name == "module" {
    if items.length() == 2 {
      let idx = resolve_core_module_reference(items[1], state)
      return { name: "", kind, idx }
    }
    if items.length() == 3 {
      let export_name = parse_name_text(items[2], "core module export name")
      let idx = if items[1] is Atom(ref_name) && ref_name.has_prefix("$") {
        if lookup_named_index(state.core_instance_names, ref_name)
          is Some(core_instance_idx) {
          parse_core_alias_binding(
            state,
            0x11,
            core_instance_idx,
            export_name,
            None,
          )
        } else if lookup_named_index(state.instance_names, ref_name)
          is Some(instance_idx) {
          let alias_idx = allocate_alias_index(state, 0x00, Some(0x11), None)
          let alias_decl = encode_alias_instance_export_decl(
            0x00,
            Some(0x11),
            instance_idx,
            export_name,
          )
          push_ordered_section(state, 6, alias_decl)
          alias_idx
        } else {
          let core_instance_idx = resolve_reference(
            items[1],
            state.core_instance_names,
            "core instance",
          )
          parse_core_alias_binding(
            state,
            0x11,
            core_instance_idx,
            export_name,
            None,
          )
        }
      } else {
        let core_instance_idx = resolve_reference(
          items[1],
          state.core_instance_names,
          "core instance",
        )
        parse_core_alias_binding(
          state,
          0x11,
          core_instance_idx,
          export_name,
          None,
        )
      }
      return { name: "", kind, idx }
    }
    raise Unsupported(
      "core module ref must be `(module <idx-or-id>)` or `(module <instance> <export>)`",
    )
  }

  if kind_name == "func" {
    if items.length() == 2 {
      let idx = resolve_reference(items[1], state.core_func_names, "core func")
      return { name: "", kind, idx }
    }
    if items.length() == 3 {
      let instance_idx = resolve_reference(
        items[1],
        state.core_instance_names,
        "core instance",
      )
      let export_name = parse_name_text(items[2], "core export name")
      let idx = parse_core_alias_binding(
        state,
        0x00,
        instance_idx,
        export_name,
        None,
      )
      return { name: "", kind, idx }
    }
    raise Unsupported(
      "core func ref must be `(func <idx-or-id>)` or `(func <instance> <export>)`",
    )
  }

  if kind_name == "memory" {
    if items.length() == 2 {
      let idx = resolve_reference(
        items[1],
        state.core_memory_names,
        "core memory",
      )
      return { name: "", kind, idx }
    }
    if items.length() == 3 {
      let instance_idx = resolve_reference(
        items[1],
        state.core_instance_names,
        "core instance",
      )
      let export_name = parse_name_text(items[2], "memory export name")
      let idx = parse_core_alias_binding(
        state,
        0x02,
        instance_idx,
        export_name,
        None,
      )
      return { name: "", kind, idx }
    }
    raise Unsupported(
      "core memory ref must be `(memory <idx-or-id>)` or `(memory <instance> <export>)`",
    )
  }

  if kind_name == "table" {
    if items.length() == 2 {
      let idx = resolve_reference(
        items[1],
        state.core_table_names,
        "core table",
      )
      return { name: "", kind, idx }
    }
    if items.length() == 3 {
      let instance_idx = resolve_reference(
        items[1],
        state.core_instance_names,
        "core instance",
      )
      let export_name = parse_name_text(items[2], "table export name")
      let idx = parse_core_alias_binding(
        state,
        0x01,
        instance_idx,
        export_name,
        None,
      )
      return { name: "", kind, idx }
    }
    raise Unsupported(
      "core table ref must be `(table <idx-or-id>)` or `(table <instance> <export>)`",
    )
  }

  if kind_name == "global" {
    if items.length() == 2 {
      let idx = resolve_reference(
        items[1],
        state.core_global_names,
        "core global",
      )
      return { name: "", kind, idx }
    }
    if items.length() == 3 {
      let instance_idx = resolve_reference(
        items[1],
        state.core_instance_names,
        "core instance",
      )
      let export_name = parse_name_text(items[2], "global export name")
      let idx = parse_core_alias_binding(
        state,
        0x03,
        instance_idx,
        export_name,
        None,
      )
      return { name: "", kind, idx }
    }
    raise Unsupported(
      "core global ref must be `(global <idx-or-id>)` or `(global <instance> <export>)`",
    )
  }

  if kind_name == "tag" {
    if items.length() == 2 {
      let idx = resolve_reference(items[1], state.core_tag_names, "core tag")
      return { name: "", kind, idx }
    }
    if items.length() == 3 {
      let instance_idx = resolve_reference(
        items[1],
        state.core_instance_names,
        "core instance",
      )
      let export_name = parse_name_text(items[2], "tag export name")
      let idx = parse_core_alias_binding(
        state,
        0x04,
        instance_idx,
        export_name,
        None,
      )
      return { name: "", kind, idx }
    }
    raise Unsupported(
      "core tag ref must be `(tag <idx-or-id>)` or `(tag <instance> <export>)`",
    )
  }

  if kind_name == "type" {
    if items.length() == 2 {
      let idx = resolve_reference(items[1], state.core_type_names, "core type")
      return { name: "", kind, idx }
    }
    if items.length() == 3 {
      let instance_idx = resolve_reference(
        items[1],
        state.core_instance_names,
        "core instance",
      )
      let export_name = parse_name_text(items[2], "core type export name")
      let idx = parse_core_alias_binding(
        state,
        0x05,
        instance_idx,
        export_name,
        None,
      )
      return { name: "", kind, idx }
    }
    raise Unsupported(
      "core type ref must be `(type <idx-or-id>)` or `(type <instance> <export>)`",
    )
  }

  raise Unsupported("unsupported core sort reference '\{kind_name}'")
}

///|
fn parse_core_instantiate_arg(
  arg_expr : SExpr,
  state : ComponentBuildState,
) -> CoreSortRef raise ComponentTextError {
  let arg = if arg_expr is List(items) {
    items
  } else {
    raise Unsupported("core instantiate arg must be a list")
  }
  if arg.length() != 3 || !(arg[0] is Atom("with")) {
    raise Unsupported("core instantiate arg must be `(with <name> <ref>)`")
  }
  let name = parse_name_text(arg[1], "core instantiate import name")
  let sort_ref = parse_core_sort_ref(arg[2], state)
  { name, kind: sort_ref.kind, idx: sort_ref.idx }
}

///|
fn parse_core_instance_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  let name_opt = parse_optional_identifier(field, 2)
  let expr_index = if name_opt is Some(_) { 3 } else { 2 }
  if expr_index >= field.length() {
    let empty = CoreInstanceEntry::{ expr: InlineExports([]) }
    push_ordered_section(state, 2, encode_core_instance_decl(empty))
    let idx = state.next_core_instance_idx
    state.next_core_instance_idx += 1
    bind_named_index(state.core_instance_names, name_opt, idx)
    return
  }
  let expr = if field[expr_index] is List(items) {
    items
  } else {
    raise Unsupported("core instance expression must be a list")
  }

  if expr.length() >= 2 && expr[0] is Atom("instantiate") {
    let module_ref = if expr[1] is List(_) {
      expr[1]
    } else {
      List([Atom("module"), expr[1]])
    }
    let sort_ref = parse_core_sort_ref(module_ref, state)
    if sort_ref.kind != 0x11 {
      raise Unsupported("core instantiate expects a core module reference")
    }
    let module_idx = sort_ref.idx
    let args : Array[CoreSortRef] = []
    for i in 2..<expr.length() {
      args.push(parse_core_instantiate_arg(expr[i], state))
    }
    let entry = CoreInstanceEntry::{ expr: Instantiate(module_idx, args) }
    push_ordered_section(state, 2, encode_core_instance_decl(entry))
    let idx = state.next_core_instance_idx
    state.next_core_instance_idx += 1
    bind_named_index(state.core_instance_names, name_opt, idx)
    return
  }

  let inline_items : Array[SExpr] = []
  if expr.length() >= 1 &&
    expr[0] is Atom("instance") &&
    field.length() == expr_index + 1 {
    for i in 1..<expr.length() {
      inline_items.push(expr[i])
    }
  } else {
    for i in expr_index..<field.length() {
      inline_items.push(field[i])
    }
  }

  let exports : Array[CoreSortRef] = []
  for item in inline_items {
    let export_item = if item is List(export_expr) {
      export_expr
    } else {
      raise Unsupported("core inline export must be a list")
    }
    if export_item.length() < 2 || !(export_item[0] is Atom("export")) {
      raise Unsupported("unsupported core instance expression")
    }
    let export_name = parse_name_text(export_item[1], "core inline export name")
    if export_item.length() == 2 {
      exports.push({ name: export_name, kind: 0x00, idx: 0 })
      continue
    }
    if export_item.length() != 3 {
      raise Unsupported("core inline export must be `(export <name> <ref>)`")
    }
    let sort_ref = parse_core_sort_ref(export_item[2], state)
    exports.push({ name: export_name, kind: sort_ref.kind, idx: sort_ref.idx })
  }

  let entry = CoreInstanceEntry::{ expr: InlineExports(exports) }
  push_ordered_section(state, 2, encode_core_instance_decl(entry))
  let idx = state.next_core_instance_idx
  state.next_core_instance_idx += 1
  bind_named_index(state.core_instance_names, name_opt, idx)
}

///|
fn parse_core_func_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  let name_opt = parse_optional_identifier(field, 2)
  let body_index = if name_opt is Some(_) { 3 } else { 2 }
  if body_index >= field.length() {
    raise Unsupported("core func declaration is missing body")
  }
  if body_index + 1 != field.length() {
    raise Unsupported(
      "core func currently supports exactly one canonical declaration",
    )
  }
  let canon_items = if field[body_index] is List(items) {
    items
  } else {
    raise Unsupported("core func body must be a canonical declaration list")
  }
  let (canon_decl, is_core_func_decl, _target_name_opt) = parse_canon_decl(
    canon_items, state, false,
  )
  if !is_core_func_decl {
    raise Unsupported(
      "core func canonical declaration must produce a core function",
    )
  }
  push_ordered_section(state, 8, canon_decl)
  let idx = state.next_core_func_idx
  state.next_core_func_idx += 1
  bind_named_index(state.core_func_names, name_opt, idx)
}

///|
fn resolve_alias_sort_index(
  expr : SExpr,
  state : ComponentBuildState,
  sort_tag : Int,
  core_kind : Int?,
) -> Int raise ComponentTextError {
  if expr is Atom(atom) {
    if parse_decimal_index(atom) is Some(idx) {
      return idx
    }
  }
  if sort_tag == 0x00 {
    let kind = match core_kind {
      Some(kind) => kind
      None => raise Unsupported("core alias is missing kind")
    }
    match kind {
      0x00 => resolve_reference(expr, state.core_func_names, "core func")
      0x01 => resolve_reference(expr, state.core_table_names, "core table")
      0x02 => resolve_reference(expr, state.core_memory_names, "core memory")
      0x03 => resolve_reference(expr, state.core_global_names, "core global")
      0x04 => resolve_reference(expr, state.core_tag_names, "core tag")
      0x05 => resolve_core_type_reference(expr, state)
      0x11 => resolve_core_module_reference(expr, state)
      0x12 =>
        resolve_reference(expr, state.core_instance_names, "core instance")
      _ => raise Unsupported("unsupported core alias reference")
    }
  } else {
    match sort_tag {
      0x01 => resolve_reference(expr, state.func_names, "function")
      0x03 => resolve_type_reference(expr, state)
      0x04 => resolve_component_reference(expr, state)
      0x05 => resolve_reference(expr, state.instance_names, "instance")
      _ => raise Unsupported("unsupported alias reference")
    }
  }
}

///|
fn parse_alias_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  if field.length() < 2 {
    raise Unsupported("alias declaration is incomplete")
  }
  if field.length() == 6 &&
    field[1] is Atom("core") &&
    field[2] is Atom("export") {
    let core_instance_idx = resolve_reference(
      field[3],
      state.core_instance_names,
      "core instance",
    )
    let export_name = parse_name_text(field[4], "core export name")
    let sort_spec = parse_alias_sort_spec(field[5])
    if sort_spec.sort_tag != 0x00 {
      raise Unsupported("`alias core export` expects a core sort descriptor")
    }
    let kind = match sort_spec.core_kind {
      Some(kind) => kind
      None => raise Unsupported("core alias is missing kind")
    }
    parse_core_alias_binding(
      state,
      kind,
      core_instance_idx,
      export_name,
      sort_spec.name_opt,
    )
    |> ignore
    return
  }
  if field.length() == 5 && field[1] is Atom("export") {
    let instance_idx = resolve_reference(
      field[2],
      state.instance_names,
      "instance",
    )
    let export_name = parse_name_text(field[3], "instance export name")
    let sort_spec = parse_alias_sort_spec(field[4])
    allocate_alias_index(
      state,
      sort_spec.sort_tag,
      sort_spec.core_kind,
      sort_spec.name_opt,
    )
    |> ignore
    let alias_decl = encode_alias_instance_export_decl(
      sort_spec.sort_tag,
      sort_spec.core_kind,
      instance_idx,
      export_name,
    )
    push_ordered_section(state, 6, alias_decl)
    return
  }
  if field.length() == 5 && field[1] is Atom("outer") {
    let sort_spec = parse_alias_sort_spec(field[4])
    let inferred_outer_count = if field[3] is Atom(target_name) &&
      target_name.has_prefix("$") {
      if sort_spec.sort_tag == 0x03 {
        let mut found : Int? = None
        for depth in 0..<state.outer_type_scopes.length() {
          if lookup_named_index(state.outer_type_scopes[depth], target_name)
            is Some(_) {
            found = Some(depth + 1)
            break
          }
        }
        found
      } else if sort_spec.sort_tag == 0x00 && sort_spec.core_kind is Some(0x05) {
        let mut found : Int? = None
        for depth in 0..<state.outer_core_type_scopes.length() {
          if lookup_named_index(
              state.outer_core_type_scopes[depth],
              target_name,
            )
            is Some(_) {
            found = Some(depth + 1)
            break
          }
        }
        found
      } else {
        None
      }
    } else {
      None
    }
    let count = if field[2] is Atom(count_atom) {
      if parse_decimal_index(count_atom) is Some(count) {
        count
      } else if count_atom.has_prefix("$") {
        match inferred_outer_count {
          Some(depth) => depth
          None => 0
        }
      } else {
        raise Unsupported("outer alias count must be a decimal index for now")
      }
    } else {
      raise Unsupported("outer alias count must be a decimal index for now")
    }
    let target_idx = if field[3] is Atom(target_name) &&
      target_name.has_prefix("$") {
      if sort_spec.sort_tag == 0x03 &&
        count > 0 &&
        count <= state.outer_type_scopes.length() {
        if lookup_named_index(state.outer_type_scopes[count - 1], target_name)
          is Some(idx) {
          idx
        } else {
          resolve_alias_sort_index(
            field[3],
            state,
            sort_spec.sort_tag,
            sort_spec.core_kind,
          )
        }
      } else if sort_spec.sort_tag == 0x00 &&
        sort_spec.core_kind is Some(0x05) &&
        count > 0 &&
        count <= state.outer_core_type_scopes.length() {
        if lookup_named_index(
            state.outer_core_type_scopes[count - 1],
            target_name,
          )
          is Some(idx) {
          idx
        } else {
          resolve_alias_sort_index(
            field[3],
            state,
            sort_spec.sort_tag,
            sort_spec.core_kind,
          )
        }
      } else {
        resolve_alias_sort_index(
          field[3],
          state,
          sort_spec.sort_tag,
          sort_spec.core_kind,
        )
      }
    } else {
      resolve_alias_sort_index(
        field[3],
        state,
        sort_spec.sort_tag,
        sort_spec.core_kind,
      )
    }
    allocate_alias_index(
      state,
      sort_spec.sort_tag,
      sort_spec.core_kind,
      sort_spec.name_opt,
    )
    |> ignore
    let alias_decl = encode_alias_outer_decl(
      sort_spec.sort_tag,
      sort_spec.core_kind,
      count,
      target_idx,
    )
    push_ordered_section(state, 6, alias_decl)
    return
  }
  raise Unsupported("unsupported alias declaration")
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
  if field[1] is Atom("type") {
    parse_core_type_field(field, state)
    return
  }
  if field[1] is Atom("instance") {
    parse_core_instance_field(field, state)
    return
  }
  if field[1] is Atom("func") {
    parse_core_func_field(field, state)
    return
  }
  raise Unsupported("unsupported core declaration")
}

///|
fn parse_canon_field(
  field : Array[SExpr],
  state : ComponentBuildState,
) -> Unit raise ComponentTextError {
  let (canon_decl, is_core_func_decl, target_name_opt) = parse_canon_decl(
    field, state, true,
  )
  if !is_core_func_decl {
    raise Unsupported(
      "component canonical declaration must produce a core function",
    )
  }
  push_ordered_section(state, 8, canon_decl)
  let idx = state.next_core_func_idx
  state.next_core_func_idx += 1
  bind_named_index(state.core_func_names, target_name_opt, idx)
}

///|
fn append_section(output : ByteBuf, section_id : Int, payload : Bytes) -> Unit {
  output.push_u8(section_id)
  output.push_uleb_u32(payload.length())
  output.push_bytes(payload)
}

///|
fn compile_component_expr_with_outer(
  expr : Array[SExpr],
  outer_type_scopes : Array[Array[NamedBinding]],
  outer_core_type_scopes : Array[Array[NamedBinding]],
  outer_component_scopes : Array[Array[NamedBinding]],
  outer_core_module_scopes : Array[Array[NamedBinding]],
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

  let state = ComponentBuildState::new(
    outer_type_scopes, outer_core_type_scopes, outer_component_scopes, outer_core_module_scopes,
  )

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
      let name_opt = parse_optional_identifier(field, 1)
      let body_start = if name_opt is Some(_) { 2 } else { 1 }
      let export_names : Array[String] = []
      let mut nested_start = body_start
      while nested_start < field.length() {
        let export_item = if field[nested_start] is List(items) {
          items
        } else {
          break
        }
        if export_item.length() == 2 && export_item[0] is Atom("export") {
          export_names.push(
            parse_name_text(export_item[1], "component export name"),
          )
          nested_start += 1
          continue
        }
        break
      }
      if nested_start < field.length() &&
        export_names.length() == 0 &&
        nested_start + 1 == field.length() {
        if field[nested_start] is List(items) &&
          items.length() == 2 &&
          items[0] is Atom("import") {
          let desc : Array[SExpr] = [Atom("component")]
          if name_opt is Some(name) {
            desc.push(Atom(name))
          }
          parse_import([Atom("import"), items[1], List(desc)], state)
          continue
        }
      }
      let next_outer_type_scopes : Array[Array[NamedBinding]] = [
        state.type_names,
      ]
      for scope in state.outer_type_scopes {
        next_outer_type_scopes.push(scope)
      }
      let next_outer_core_type_scopes : Array[Array[NamedBinding]] = [
        state.core_type_names,
      ]
      for scope in state.outer_core_type_scopes {
        next_outer_core_type_scopes.push(scope)
      }
      let next_outer_component_scopes : Array[Array[NamedBinding]] = [
        state.component_names,
      ]
      for scope in state.outer_component_scopes {
        next_outer_component_scopes.push(scope)
      }
      let next_outer_core_module_scopes : Array[Array[NamedBinding]] = [
        state.core_module_names,
      ]
      for scope in state.outer_core_module_scopes {
        next_outer_core_module_scopes.push(scope)
      }
      let nested_expr : Array[SExpr] = [Atom("component")]
      if name_opt is Some(name) {
        nested_expr.push(Atom(name))
      }
      for i in nested_start..<field.length() {
        nested_expr.push(field[i])
      }
      let nested = compile_component_expr_with_outer(
        nested_expr, next_outer_type_scopes, next_outer_core_type_scopes, next_outer_component_scopes,
        next_outer_core_module_scopes,
      )
      state.nested_components.push(nested)
      state.sections_ordered.push({ section_id: 4, payload: nested })
      let component_idx = state.next_component_idx
      state.next_component_idx += 1
      bind_named_index(state.component_names, name_opt, component_idx)
      for export_name in export_names {
        push_export_decl(state, {
          name: export_name,
          sort_tag: 0x04,
          core_kind: None,
          idx: component_idx,
          desc: None,
        })
        finalize_export(state, 0x04, None, None)
      }
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
    if field[0] is Atom("instance") {
      parse_instance_field(field, state)
      continue
    }
    if field[0] is Atom("alias") {
      parse_alias_field(field, state)
      continue
    }
    if field[0] is Atom("func") {
      parse_func_field(field, state)
      continue
    }
    if field[0] is Atom("canon") {
      parse_canon_field(field, state)
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

  for section in state.sections_ordered {
    append_section(out, section.section_id, section.payload)
  }

  out.to_bytes()
}

///|
fn compile_component_expr(
  expr : Array[SExpr],
) -> Bytes raise ComponentTextError {
  compile_component_expr_with_outer(expr, [], [], [], [])
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
fn decode_wat_binary_string(text : String) -> Bytes raise ComponentTextError {
  let out : Array[Byte] = []
  for ch in text {
    let code = ch.to_int()
    if code < 0 || code > 0xff {
      raise ParseError("binary form contains non-byte character")
    }
    out.push(code.to_byte())
  }
  Bytes::from_array(out)
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
    if items.length() >= 2 && items[0] is Atom("component") {
      let mut index = 1
      if index < items.length() && items[index] is Atom("definition") {
        index += 1
      }
      if index < items.length() {
        if items[index] is Atom(name) && name.has_prefix("$") {
          index += 1
        }
      }
      if index < items.length() && items[index] is Atom("binary") {
        index += 1
        let out : Array[Byte] = []
        for i in index..<items.length() {
          if items[i] is Str(text) {
            let bytes = decode_wat_binary_string(text)
            for b in bytes {
              out.push(b)
            }
          } else {
            raise Unsupported("component binary form expects string segments")
          }
        }
        let bytes = Bytes::from_array(out)
        ignore(@component.parse_component(bytes)) catch {
          e => raise ParseError("\{e}")
        }
        return bytes
      }
    }
    compile_component_expr(items)
  } else {
    raise ParseError("expected a single (component ...) form")
  }
}
