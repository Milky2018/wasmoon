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
  type_idx : Int
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
fn ByteBuf::push_ascii_name(
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
        if items.length() == 3 && items[1] is Str(label) {
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
fn ensure_func_type(types : Array[FuncTypeSig], sig : FuncTypeSig) -> Int {
  for type_index in 0..<types.length() {
    if types[type_index] == sig {
      return type_index
    }
  }
  types.push(sig)
  types.length() - 1
}

///|
fn parse_import(
  field : Array[SExpr],
  types : Array[FuncTypeSig],
  imports : Array[ImportEntry],
) -> Unit raise ComponentTextError {
  if field.length() != 3 {
    raise Unsupported("import form currently expects exactly one descriptor")
  }
  let name = if field[1] is Str(value) {
    value
  } else {
    raise Unsupported("import name must be a string literal")
  }
  let desc = if field[2] is List(items) {
    items
  } else {
    raise Unsupported("import descriptor must be a list")
  }
  if desc.length() == 0 {
    raise Unsupported("empty import descriptor")
  }
  if desc[0] is Atom("func") {
    let sig = parse_func_sig(desc)
    let type_idx = ensure_func_type(types, sig)
    imports.push({ name, type_idx })
    return
  }
  raise Unsupported("unsupported import descriptor")
}

///|
fn encode_type_section(
  types : Array[FuncTypeSig],
) -> Bytes raise ComponentTextError {
  let payload = ByteBuf::new()
  payload.push_uleb_u32(types.length())
  for sig in types {
    payload.push_u8(0x40)
    payload.push_uleb_u32(sig.params.length())
    for param in sig.params {
      payload.push_ascii_name(param.label)
      payload.push_u8(param.type_opcode)
    }
    if sig.result_opcode is Some(opcode) {
      payload.push_u8(0x00)
      payload.push_u8(opcode)
    } else {
      payload.push_u8(0x01)
      payload.push_u8(0x00)
    }
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
    payload.push_ascii_name(import_item.name)
    payload.push_u8(0x01)
    payload.push_uleb_u32(import_item.type_idx)
  }
  payload.to_bytes()
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

  let type_entries : Array[FuncTypeSig] = []
  let import_entries : Array[ImportEntry] = []
  let nested_components : Array[Bytes] = []

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
      parse_import(field, type_entries, import_entries)
      continue
    }
    if field[0] is Atom("component") {
      nested_components.push(compile_component_expr(field))
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

  for nested in nested_components {
    append_section(out, 4, nested)
  }
  if type_entries.length() > 0 {
    append_section(out, 7, encode_type_section(type_entries))
  }
  if import_entries.length() > 0 {
    append_section(out, 10, encode_import_section(import_entries))
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
