///|
/// Minimal WIT (WebAssembly Interface Types) text parser/printer used by `wasmoon-tools`.
///
/// This is intentionally an MVP: it targets the subset needed for basic inspection
/// and will be expanded incrementally towards wasm-tools parity.

///|
pub(all) suberror WitError {
  Error(String)
}

///|
fn WitError::to_string(self : WitError) -> String {
  match self {
    Error(msg) => msg
  }
}

///|
pub impl Show for WitError with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) enum TokenKind {
  Ident(String)
  IntLit(Int)
  StrLit(String)
  KwPackage
  KwInterface
  KwWorld
  KwType
  KwFunc
  KwImport
  KwExport
  KwRecord
  LBrace
  RBrace
  LParen
  RParen
  LAngle
  RAngle
  Colon
  Semi
  Comma
  Dot
  Slash
  At
  Eq
  Arrow
}

///|
priv struct Token {
  kind : TokenKind
  line : Int
  col : Int
}

///|
pub(all) struct Package {
  name : String?
  version : String?
  items : Array[TopItem]
}

///|
pub(all) enum TopItem {
  Interface(Interface)
  World(World)
}

///|
pub(all) struct Interface {
  name : String
  items : Array[InterfaceItem]
}

///|
pub(all) enum InterfaceItem {
  Func(FuncDecl)
  TypeAlias(TypeAlias)
  Record(RecordDecl)
}

///|
pub(all) struct World {
  name : String
  items : Array[WorldItem]
}

///|
pub(all) enum WorldItem {
  Import(String)
  Export(String)
}

///|
pub(all) struct FuncDecl {
  name : String
  params : Array[(String, TypeExpr)]
  results : Array[(String?, TypeExpr)]
}

///|
pub(all) struct TypeAlias {
  name : String
  ty : TypeExpr
}

///|
pub(all) struct RecordDecl {
  name : String
  fields : Array[(String, TypeExpr)]
}

///|
pub(all) enum TypeExpr {
  Id(String)
  Apply(String, Array[TypeExpr]) // e.g. list<u8>, option<t>, result<ok, err>
  Record(Array[(String, TypeExpr)]) // inline record { a: u32, ... }
}

///|
pub fn parse_package(src : String) -> Package raise WitError {
  let lx = Lexer::new(src)
  let toks = lx.lex_all()
  let p = Parser::new(toks)
  p.parse_package()
}

///|
pub fn format_package(pkg : Package) -> String {
  let sb = StringBuilder::new()
  match pkg.name {
    Some(n) => {
      sb.write_string("package ")
      sb.write_string(n)
      match pkg.version {
        Some(v) => {
          sb.write_char('@')
          sb.write_string(v)
        }
        None => ()
      }
      sb.write_string(";\n\n")
    }
    None => ()
  }
  let mut first = true
  for it in pkg.items {
    if !first {
      sb.write_char('\n')
    }
    first = false
    match it {
      Interface(i) => format_interface(sb, i)
      World(w) => format_world(sb, w)
    }
  }
  sb.to_string()
}

///|
pub fn package_to_json(pkg : Package) -> String {
  // Small JSON emitter for CLI output; stable ordering.
  let sb = StringBuilder::new()
  sb.write_char('{')
  sb.write_string("\"name\":")
  match pkg.name {
    Some(n) => json_string(sb, n)
    None => sb.write_string("null")
  }
  sb.write_string(",\"version\":")
  match pkg.version {
    Some(v) => json_string(sb, v)
    None => sb.write_string("null")
  }
  sb.write_string(",\"items\":[")
  for i in 0..<pkg.items.length() {
    if i > 0 {
      sb.write_char(',')
    }
    match pkg.items[i] {
      Interface(it) => {
        sb.write_string("{\"kind\":\"interface\",\"name\":")
        json_string(sb, it.name)
        sb.write_string(",\"items\":[")
        for j in 0..<it.items.length() {
          if j > 0 {
            sb.write_char(',')
          }
          match it.items[j] {
            Func(fd) => {
              sb.write_string("{\"kind\":\"func\",\"name\":")
              json_string(sb, fd.name)
              sb.write_string("}")
            }
            TypeAlias(td) => {
              sb.write_string("{\"kind\":\"type\",\"name\":")
              json_string(sb, td.name)
              sb.write_string("}")
            }
            Record(rd) => {
              sb.write_string("{\"kind\":\"record\",\"name\":")
              json_string(sb, rd.name)
              sb.write_string("}")
            }
          }
        }
        sb.write_string("]}")
      }
      World(w) => {
        sb.write_string("{\"kind\":\"world\",\"name\":")
        json_string(sb, w.name)
        sb.write_string(",\"items\":[")
        for j in 0..<w.items.length() {
          if j > 0 {
            sb.write_char(',')
          }
          match w.items[j] {
            Import(n) => {
              sb.write_string("{\"kind\":\"import\",\"name\":")
              json_string(sb, n)
              sb.write_string("}")
            }
            Export(n) => {
              sb.write_string("{\"kind\":\"export\",\"name\":")
              json_string(sb, n)
              sb.write_string("}")
            }
          }
        }
        sb.write_string("]}")
      }
    }
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
fn json_string(sb : StringBuilder, s : String) -> Unit {
  sb.write_char('"')
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ => sb.write_char(c)
    }
  }
  sb.write_char('"')
}

///|
fn format_interface(sb : StringBuilder, it : Interface) -> Unit {
  sb.write_string("interface ")
  sb.write_string(it.name)
  sb.write_string(" {\n")
  for item in it.items {
    match item {
      Func(f) => {
        sb.write_string("  ")
        sb.write_string(f.name)
        sb.write_string(": func(")
        for i in 0..<f.params.length() {
          if i > 0 {
            sb.write_string(", ")
          }
          let (n, t) = f.params[i]
          sb.write_string(n)
          sb.write_string(": ")
          format_type(sb, t)
        }
        sb.write_char(')')
        if f.results.length() > 0 {
          sb.write_string(" -> ")
          if f.results.length() == 1 && f.results[0].0 is None {
            format_type(sb, f.results[0].1)
          } else {
            sb.write_char('(')
            for i in 0..<f.results.length() {
              if i > 0 {
                sb.write_string(", ")
              }
              let (rn, rt) = f.results[i]
              match rn {
                Some(n) => {
                  sb.write_string(n)
                  sb.write_string(": ")
                }
                None => ()
              }
              format_type(sb, rt)
            }
            sb.write_char(')')
          }
        }
        sb.write_string(";\n")
      }
      TypeAlias(t) => {
        sb.write_string("  type ")
        sb.write_string(t.name)
        sb.write_string(" = ")
        format_type(sb, t.ty)
        sb.write_string(";\n")
      }
      Record(r) => {
        sb.write_string("  record ")
        sb.write_string(r.name)
        sb.write_string(" {\n")
        for field in r.fields {
          let (n, t) = field
          sb.write_string("    ")
          sb.write_string(n)
          sb.write_string(": ")
          format_type(sb, t)
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
    }
  }
  sb.write_string("}\n")
}

///|
fn format_world(sb : StringBuilder, w : World) -> Unit {
  sb.write_string("world ")
  sb.write_string(w.name)
  sb.write_string(" {\n")
  for it in w.items {
    match it {
      Import(n) => {
        sb.write_string("  import ")
        sb.write_string(n)
        sb.write_string(";\n")
      }
      Export(n) => {
        sb.write_string("  export ")
        sb.write_string(n)
        sb.write_string(";\n")
      }
    }
  }
  sb.write_string("}\n")
}

///|
fn format_type(sb : StringBuilder, t : TypeExpr) -> Unit {
  match t {
    Id(n) => sb.write_string(n)
    Apply(n, args) => {
      sb.write_string(n)
      sb.write_char('<')
      for i in 0..<args.length() {
        if i > 0 {
          sb.write_string(", ")
        }
        format_type(sb, args[i])
      }
      sb.write_char('>')
    }
    Record(fields) => {
      sb.write_string("record { ")
      for i in 0..<fields.length() {
        if i > 0 {
          sb.write_string(", ")
        }
        let (field_name, ft) = fields[i]
        sb.write_string(field_name)
        sb.write_string(": ")
        format_type(sb, ft)
      }
      sb.write_string(" }")
    }
  }
}

///|
priv struct Lexer {
  src : String
  mut i : Int
  mut line : Int
  mut col : Int
}

///|
fn Lexer::new(src : String) -> Lexer {
  { src, i: 0, line: 1, col: 1 }
}

///|
fn Lexer::lex_all(self : Lexer) -> Array[Token] raise WitError {
  let out : Array[Token] = []
  while true {
    self.skip_ws_and_comments()
    if self.i >= self.src.length() {
      break
    }
    let (kind, line, col) = self.lex_one()
    out.push({ kind, line, col })
  }
  out
}

///|
fn Lexer::peek(self : Lexer, off : Int) -> Int? {
  let j = self.i + off
  if j >= self.src.length() {
    None
  } else {
    Some(self.src.code_unit_at(j).to_int())
  }
}

///|
fn Lexer::bump(self : Lexer) -> Int? {
  if self.i >= self.src.length() {
    return None
  }
  let cu = self.src.code_unit_at(self.i).to_int()
  self.i = self.i + 1
  if cu == 10 { // \n
    self.line = self.line + 1
    self.col = 1
  } else {
    self.col = self.col + 1
  }
  Some(cu)
}

///|
fn Lexer::skip_ws_and_comments(self : Lexer) -> Unit raise WitError {
  while self.i < self.src.length() {
    let cu = self.src.code_unit_at(self.i).to_int()
    // whitespace
    if cu == 32 || cu == 9 || cu == 10 || cu == 13 {
      self.bump() |> ignore
      continue
    }
    // line comment: //
    if cu == 47 {
      match self.peek(1) {
        Some(47) => {
          while self.i < self.src.length() {
            let b = self.bump().unwrap_or(0)
            if b == 10 {
              break
            }
          }
          continue
        }
        Some(42) => {
          // block comment: /* ... */
          self.bump() |> ignore
          self.bump() |> ignore
          while true {
            if self.i >= self.src.length() {
              raise WitError::Error("unterminated block comment")
            }
            let b = self.bump().unwrap_or(0)
            if b == 42 && self.peek(0) is Some(47) {
              self.bump() |> ignore
              break
            }
          }
          continue
        }
        _ => ()
      }
    }
    break
  }
}

///|
fn Lexer::lex_one(self : Lexer) -> (TokenKind, Int, Int) raise WitError {
  let line = self.line
  let col = self.col
  let cu = self.src.code_unit_at(self.i).to_int()
  // punctuation / operators
  match cu {
    123 => {
      self.bump() |> ignore
      (LBrace, line, col)
    } // {
    125 => {
      self.bump() |> ignore
      (RBrace, line, col)
    } // }
    40 => {
      self.bump() |> ignore
      (LParen, line, col)
    } // (
    41 => {
      self.bump() |> ignore
      (RParen, line, col)
    } // )
    60 => {
      self.bump() |> ignore
      (LAngle, line, col)
    } // <
    62 =>
      match self.peek(1) {
        Some(_) => {
          self.bump() |> ignore
          (RAngle, line, col)
        }
        None => {
          self.bump() |> ignore
          (RAngle, line, col)
        }
      }
    58 => {
      self.bump() |> ignore
      (Colon, line, col)
    } // :
    59 => {
      self.bump() |> ignore
      (Semi, line, col)
    } // ;
    44 => {
      self.bump() |> ignore
      (Comma, line, col)
    } // ,
    46 => {
      self.bump() |> ignore
      (Dot, line, col)
    } // .
    47 => {
      self.bump() |> ignore
      (Slash, line, col)
    } // /
    64 => {
      self.bump() |> ignore
      (At, line, col)
    } // @
    61 => {
      self.bump() |> ignore
      (Eq, line, col)
    } // =
    45 =>
      match self.peek(1) {
        Some(62) => { // ->
          self.bump() |> ignore
          self.bump() |> ignore
          (Arrow, line, col)
        }
        _ => raise WitError::Error("unexpected '-'")
      }
    34 => // "
      (StrLit(self.lex_string()), line, col)
    _ =>
      if is_digit(cu) {
        let n = self.lex_int()
        (IntLit(n), line, col)
      } else if is_ident_start(cu) {
        let s = self.lex_ident()
        let k = match s {
          "package" => KwPackage
          "interface" => KwInterface
          "world" => KwWorld
          "type" => KwType
          "func" => KwFunc
          "import" => KwImport
          "export" => KwExport
          "record" => KwRecord
          _ => Ident(s)
        }
        (k, line, col)
      } else {
        raise WitError::Error("unexpected character")
      }
  }
}

///|
fn Lexer::lex_ident(self : Lexer) -> String {
  let sb = StringBuilder::new()
  // First char is known to be a valid ident start.
  let first = self.bump().unwrap_or(0)
  sb.write_char(first.unsafe_to_char())
  while self.i < self.src.length() {
    let cu = self.src.code_unit_at(self.i).to_int()
    if is_ident_continue(cu) {
      let b = self.bump().unwrap_or(0)
      sb.write_char(b.unsafe_to_char())
    } else {
      break
    }
  }
  sb.to_string()
}

///|
fn Lexer::lex_int(self : Lexer) -> Int {
  let mut n = 0
  while self.i < self.src.length() {
    let cu = self.src.code_unit_at(self.i).to_int()
    if !is_digit(cu) {
      break
    }
    n = n * 10 + (cu - 48)
    self.bump() |> ignore
  }
  n
}

///|
fn Lexer::lex_string(self : Lexer) -> String raise WitError {
  // Consume opening quote.
  self.bump() |> ignore
  let sb = StringBuilder::new()
  while true {
    if self.i >= self.src.length() {
      raise WitError::Error("unterminated string literal")
    }
    let cu = self.bump().unwrap_or(0)
    if cu == 34 {
      break
    }
    if cu == 92 { // backslash
      let esc = self.bump().unwrap_or(0)
      match esc {
        34 => sb.write_char('"')
        92 => sb.write_char('\\')
        110 => sb.write_char('\n')
        114 => sb.write_char('\r')
        116 => sb.write_char('\t')
        _ => raise WitError::Error("unsupported string escape")
      }
    } else {
      sb.write_char(cu.unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
fn is_digit(cu : Int) -> Bool {
  cu >= 48 && cu <= 57
}

///|
fn is_ident_start(cu : Int) -> Bool {
  (cu >= 65 && cu <= 90) || (cu >= 97 && cu <= 122) || cu == 95 // _
}

///|
fn is_ident_continue(cu : Int) -> Bool {
  is_ident_start(cu) || is_digit(cu) || cu == 45 // -
}

///|
priv struct Parser {
  toks : Array[Token]
  mut i : Int
}

///|
fn Parser::new(toks : Array[Token]) -> Parser {
  { toks, i: 0 }
}

///|
fn Parser::parse_package(self : Parser) -> Package raise WitError {
  let mut name : String? = None
  let mut version : String? = None
  if self.peek_kw(KwPackage) {
    self.bump_kw(KwPackage)
    name = Some(self.parse_package_name())
    if self.peek_kw(At) {
      self.bump_kw(At)
      version = Some(self.parse_version())
    }
    self.bump_kw(Semi)
  }
  let items : Array[TopItem] = []
  while self.i < self.toks.length() {
    if self.peek_kw(KwInterface) {
      items.push(Interface(self.parse_interface()))
    } else if self.peek_kw(KwWorld) {
      items.push(World(self.parse_world()))
    } else {
      raise self.err_here("expected `interface` or `world`")
    }
  }
  { name, version, items }
}

///|
fn Parser::parse_package_name(self : Parser) -> String raise WitError {
  // Capture tokens up to '@' or ';' (namespace:path[/path]*).
  let sb = StringBuilder::new()
  while self.i < self.toks.length() {
    match self.toks[self.i].kind {
      At | Semi => break
      Ident(s) => {
        sb.write_string(s)
        self.i = self.i + 1
      }
      Colon => {
        sb.write_char(':')
        self.i = self.i + 1
      }
      Slash => {
        sb.write_char('/')
        self.i = self.i + 1
      }
      Dot => {
        sb.write_char('.')
        self.i = self.i + 1
      }
      _ => raise self.err_here("invalid token in package name")
    }
  }
  sb.to_string()
}

///|
fn Parser::parse_version(self : Parser) -> String raise WitError {
  // Simple semver-ish capture: digits and dots until ';'.
  let sb = StringBuilder::new()
  while self.i < self.toks.length() {
    match self.toks[self.i].kind {
      Semi => break
      IntLit(n) => {
        sb.write_string(n.to_string())
        self.i = self.i + 1
      }
      Dot => {
        sb.write_char('.')
        self.i = self.i + 1
      }
      _ => raise self.err_here("invalid token in version")
    }
  }
  sb.to_string()
}

///|
fn Parser::parse_interface(self : Parser) -> Interface raise WitError {
  self.bump_kw(KwInterface)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let items : Array[InterfaceItem] = []
  while !self.peek_kw(RBrace) {
    if self.peek_kw(KwType) {
      items.push(TypeAlias(self.parse_type_alias()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwRecord) {
      items.push(Record(self.parse_record_decl()))
      self.eat_kw(Semi)
    } else {
      items.push(Func(self.parse_func_decl()))
      self.bump_kw(Semi)
    }
  }
  self.bump_kw(RBrace)
  { name, items }
}

///|
fn Parser::parse_world(self : Parser) -> World raise WitError {
  self.bump_kw(KwWorld)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let items : Array[WorldItem] = []
  while !self.peek_kw(RBrace) {
    if self.peek_kw(KwImport) {
      self.bump_kw(KwImport)
      let n = self.parse_ident()
      self.bump_kw(Semi)
      items.push(Import(n))
    } else if self.peek_kw(KwExport) {
      self.bump_kw(KwExport)
      let n = self.parse_ident()
      self.bump_kw(Semi)
      items.push(Export(n))
    } else {
      raise self.err_here("expected `import` or `export`")
    }
  }
  self.bump_kw(RBrace)
  { name, items }
}

///|
fn Parser::parse_func_decl(self : Parser) -> FuncDecl raise WitError {
  let name = self.parse_ident()
  self.bump_kw(Colon)
  self.bump_kw(KwFunc)
  self.bump_kw(LParen)
  let params = self.parse_named_type_list(RParen)
  self.bump_kw(RParen)
  let results : Array[(String?, TypeExpr)] = []
  if self.peek_kw(Arrow) {
    self.bump_kw(Arrow)
    if self.peek_kw(LParen) {
      self.bump_kw(LParen)
      let rs = self.parse_named_type_list(RParen)
      for pair in rs {
        let (n, t) = pair
        results.push((Some(n), t))
      }
      self.bump_kw(RParen)
    } else {
      results.push((None, self.parse_type()))
    }
  }
  { name, params, results }
}

///|
fn Parser::parse_type_alias(self : Parser) -> TypeAlias raise WitError {
  self.bump_kw(KwType)
  let name = self.parse_ident()
  self.bump_kw(Eq)
  let ty = self.parse_type()
  { name, ty }
}

///|
fn Parser::parse_record_decl(self : Parser) -> RecordDecl raise WitError {
  self.bump_kw(KwRecord)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let fields : Array[(String, TypeExpr)] = []
  while !self.peek_kw(RBrace) {
    let field_name = self.parse_ident()
    self.bump_kw(Colon)
    let ft = self.parse_type()
    fields.push((field_name, ft))
    self.eat_kw(Comma)
  }
  self.bump_kw(RBrace)
  { name, fields }
}

///|
fn Parser::parse_type(self : Parser) -> TypeExpr raise WitError {
  if self.peek_kw(KwRecord) {
    self.bump_kw(KwRecord)
    self.bump_kw(LBrace)
    let fields : Array[(String, TypeExpr)] = []
    while !self.peek_kw(RBrace) {
      let n = self.parse_ident()
      self.bump_kw(Colon)
      let t = self.parse_type()
      fields.push((n, t))
      self.eat_kw(Comma)
    }
    self.bump_kw(RBrace)
    return Record(fields)
  }
  let name = self.parse_ident()
  if self.peek_kw(LAngle) {
    self.bump_kw(LAngle)
    let args : Array[TypeExpr] = []
    if !self.peek_kw(RAngle) {
      while true {
        args.push(self.parse_type())
        if self.peek_kw(Comma) {
          self.bump_kw(Comma)
          continue
        }
        break
      }
    }
    self.bump_kw(RAngle)
    Apply(name, args)
  } else {
    Id(name)
  }
}

///|
fn Parser::parse_named_type_list(
  self : Parser,
  end : TokenKind,
) -> Array[(String, TypeExpr)] raise WitError {
  let out : Array[(String, TypeExpr)] = []
  if self.peek_kw(end) {
    return out
  }
  while true {
    let n = self.parse_ident()
    self.bump_kw(Colon)
    let t = self.parse_type()
    out.push((n, t))
    if self.peek_kw(Comma) {
      self.bump_kw(Comma)
      continue
    }
    break
  }
  out
}

///|
fn Parser::parse_ident(self : Parser) -> String raise WitError {
  if self.i >= self.toks.length() {
    raise WitError::Error("unexpected EOF")
  }
  match self.toks[self.i].kind {
    Ident(s) => {
      self.i = self.i + 1
      s
    }
    _ => raise self.err_here("expected identifier")
  }
}

///|
fn Parser::peek_kw(self : Parser, k : TokenKind) -> Bool {
  if self.i >= self.toks.length() {
    return false
  }
  token_kind_is(self.toks[self.i].kind, k)
}

///|
fn Parser::bump_kw(self : Parser, k : TokenKind) -> Unit raise WitError {
  if !self.peek_kw(k) {
    raise self.err_here("unexpected token")
  }
  self.i = self.i + 1
}

///|
fn Parser::eat_kw(self : Parser, k : TokenKind) -> Unit {
  if self.peek_kw(k) {
    self.i = self.i + 1
  }
}

///|
fn Parser::err_here(self : Parser, msg : String) -> WitError {
  if self.i >= self.toks.length() {
    WitError::Error(msg + " at EOF")
  } else {
    let t = self.toks[self.i]
    WitError::Error(msg + " at " + t.line.to_string() + ":" + t.col.to_string())
  }
}

///|
fn token_kind_is(a : TokenKind, b : TokenKind) -> Bool {
  match (a, b) {
    (KwPackage, KwPackage)
    | (KwInterface, KwInterface)
    | (KwWorld, KwWorld)
    | (KwType, KwType)
    | (KwFunc, KwFunc)
    | (KwImport, KwImport)
    | (KwExport, KwExport)
    | (KwRecord, KwRecord)
    | (LBrace, LBrace)
    | (RBrace, RBrace)
    | (LParen, LParen)
    | (RParen, RParen)
    | (LAngle, LAngle)
    | (RAngle, RAngle)
    | (Colon, Colon)
    | (Semi, Semi)
    | (Comma, Comma)
    | (Dot, Dot)
    | (Slash, Slash)
    | (At, At)
    | (Eq, Eq)
    | (Arrow, Arrow) => true
    _ => false
  }
}
