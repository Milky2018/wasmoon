///|
pub(all) enum TokenKind {
  Ident(String)
  IntLit(Int)
  StrLit(String)
  KwPackage
  KwInterface
  KwWorld
  KwUse
  KwAs
  KwWith
  KwInclude
  KwType
  KwFunc
  KwImport
  KwExport
  KwRecord
  KwResource
  KwEnum
  KwFlags
  KwVariant
  KwTuple
  KwList
  KwOption
  KwResult
  KwBorrow
  KwFuture
  KwStream
  KwAsync
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
  Dash
  Plus
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
pub fn parse_package(src : String) -> Package raise WitError {
  let lx = Lexer::new(src)
  let toks = lx.lex_all()
  let p = Parser::new(toks)
  p.parse_package()
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
    43 => {
      self.bump() |> ignore
      (Plus, line, col)
    } // +
    45 =>
      match self.peek(1) {
        Some(62) => { // ->
          self.bump() |> ignore
          self.bump() |> ignore
          (Arrow, line, col)
        }
        _ => {
          self.bump() |> ignore
          (Dash, line, col)
        }
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
          "use" => KwUse
          "as" => KwAs
          "with" => KwWith
          "include" => KwInclude
          "type" => KwType
          "resource" => KwResource
          "enum" => KwEnum
          "flags" => KwFlags
          "variant" => KwVariant
          "func" => KwFunc
          "import" => KwImport
          "export" => KwExport
          "record" => KwRecord
          "tuple" => KwTuple
          "list" => KwList
          "option" => KwOption
          "result" => KwResult
          "borrow" => KwBorrow
          "future" => KwFuture
          "stream" => KwStream
          "async" => KwAsync
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
  let nested : Array[Package] = []
  while self.i < self.toks.length() {
    self.skip_gates()
    if self.i >= self.toks.length() {
      break
    }
    if self.peek_kw(KwUse) {
      items.push(ToplevelUse(self.parse_toplevel_use()))
    } else if self.peek_kw(KwInterface) {
      items.push(Interface(self.parse_interface()))
    } else if self.peek_kw(KwWorld) {
      items.push(World(self.parse_world()))
    } else if self.peek_kw(KwPackage) {
      nested.push(self.parse_nested_package())
    } else {
      raise self.err_here(
        "expected `use`, `interface`, `world`, or nested `package`",
      )
    }
  }
  { name, version, items, nested }
}

///|
fn Parser::skip_gates(self : Parser) -> Unit raise WitError {
  while self.peek_kw(At) {
    self.bump_kw(At)
    // Eat the gate name token (e.g. since/unstable/deprecated).
    if self.i >= self.toks.length() {
      raise self.err_here("unexpected EOF after '@'")
    }
    self.i = self.i + 1
    // If followed by parentheses, skip balanced parens.
    if self.peek_kw(LParen) {
      self.bump_kw(LParen)
      let mut depth = 1
      while depth > 0 {
        if self.i >= self.toks.length() {
          raise self.err_here("unterminated gate annotation")
        }
        match self.toks[self.i].kind {
          LParen => depth = depth + 1
          RParen => depth = depth - 1
          _ => ()
        }
        self.i = self.i + 1
      }
    }
  }
}

///|
fn Parser::parse_toplevel_use(self : Parser) -> ToplevelUse raise WitError {
  self.bump_kw(KwUse)
  let path = self.parse_use_path_until([KwAs, Semi])
  let mut as_name : String? = None
  if self.peek_kw(KwAs) {
    self.bump_kw(KwAs)
    as_name = Some(self.parse_ident())
  }
  self.bump_kw(Semi)
  { path, as_name }
}

///|
fn Parser::parse_nested_package(self : Parser) -> Package raise WitError {
  self.bump_kw(KwPackage)
  let name = Some(self.parse_package_name())
  let mut version : String? = None
  if self.peek_kw(At) {
    self.bump_kw(At)
    version = Some(self.parse_version())
  }
  self.bump_kw(LBrace)
  let items : Array[TopItem] = []
  let nested : Array[Package] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(KwUse) {
      items.push(ToplevelUse(self.parse_toplevel_use()))
    } else if self.peek_kw(KwInterface) {
      items.push(Interface(self.parse_interface()))
    } else if self.peek_kw(KwWorld) {
      items.push(World(self.parse_world()))
    } else if self.peek_kw(KwPackage) {
      nested.push(self.parse_nested_package())
    } else {
      raise self.err_here("expected item within nested package")
    }
  }
  self.bump_kw(RBrace)
  { name, version, items, nested }
}

///|
fn Parser::parse_package_name(self : Parser) -> String raise WitError {
  // Capture tokens up to '@', ';' or '{' (namespace:path[/path]*).
  let sb = StringBuilder::new()
  while self.i < self.toks.length() {
    match self.toks[self.i].kind {
      At | Semi | LBrace => break
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
  // Simple semver-ish capture until ';' or '{' (supports pre-release/build).
  let sb = StringBuilder::new()
  while self.i < self.toks.length() {
    match self.toks[self.i].kind {
      Semi | LBrace => break
      IntLit(n) => {
        sb.write_string(n.to_string())
        self.i = self.i + 1
      }
      Dot => {
        sb.write_char('.')
        self.i = self.i + 1
      }
      Dash => {
        sb.write_char('-')
        self.i = self.i + 1
      }
      Plus => {
        sb.write_char('+')
        self.i = self.i + 1
      }
      Ident(s) => {
        sb.write_string(s)
        self.i = self.i + 1
      }
      _ => raise self.err_here("invalid token in version")
    }
  }
  sb.to_string()
}

///|
fn Parser::parse_use_path_until(
  self : Parser,
  stops : Array[TokenKind],
) -> UsePath raise WitError {
  let sb = StringBuilder::new()
  while self.i < self.toks.length() && !self.peek_any(stops) {
    match self.toks[self.i].kind {
      Ident(s) => sb.write_string(s)
      IntLit(n) => sb.write_string(n.to_string())
      Colon => sb.write_char(':')
      Slash => sb.write_char('/')
      Dot => sb.write_char('.')
      At => sb.write_char('@')
      Dash => sb.write_char('-')
      Plus => sb.write_char('+')
      _ => raise self.err_here("invalid token in use-path")
    }
    self.i = self.i + 1
  }
  { raw: sb.to_string() }
}

///|
fn Parser::peek_any(self : Parser, stops : Array[TokenKind]) -> Bool {
  for s in stops {
    if self.peek_kw(s) {
      return true
    }
  }
  false
}

///|
fn Parser::parse_use_item(self : Parser) -> UseItem raise WitError {
  self.bump_kw(KwUse)
  let path = self.parse_use_path_before_dot_lbrace()
  self.bump_kw(Dot)
  self.bump_kw(LBrace)
  let names : Array[(String, String?)] = []
  if !self.peek_kw(RBrace) {
    while true {
      let n = self.parse_ident()
      let mut asn : String? = None
      if self.peek_kw(KwAs) {
        self.bump_kw(KwAs)
        asn = Some(self.parse_ident())
      }
      names.push((n, asn))
      if self.peek_kw(Comma) {
        self.bump_kw(Comma)
        // Trailing comma allowed.
        if self.peek_kw(RBrace) {
          break
        }
        continue
      }
      break
    }
  }
  self.bump_kw(RBrace)
  self.bump_kw(Semi)
  { path, names }
}

///|
fn Parser::parse_use_path_before_dot_lbrace(
  self : Parser,
) -> UsePath raise WitError {
  let sb = StringBuilder::new()
  while self.i < self.toks.length() {
    if self.peek_kw(Dot) && self.peek_next_is(LBrace) {
      break
    }
    match self.toks[self.i].kind {
      Ident(s) => sb.write_string(s)
      IntLit(n) => sb.write_string(n.to_string())
      Colon => sb.write_char(':')
      Slash => sb.write_char('/')
      Dot => sb.write_char('.')
      At => sb.write_char('@')
      Dash => sb.write_char('-')
      Plus => sb.write_char('+')
      _ => raise self.err_here("invalid token in use-path")
    }
    self.i = self.i + 1
  }
  { raw: sb.to_string() }
}

///|
fn Parser::peek_next_is(self : Parser, k : TokenKind) -> Bool {
  if self.i + 1 >= self.toks.length() {
    return false
  }
  token_kind_is(self.toks[self.i + 1].kind, k)
}

///|
fn Parser::parse_include_item(self : Parser) -> IncludeItem raise WitError {
  self.bump_kw(KwInclude)
  let path = self.parse_use_path_until([KwWith, Semi])
  let mut renames : Array[(String, String)]? = None
  if self.peek_kw(KwWith) {
    self.bump_kw(KwWith)
    self.bump_kw(LBrace)
    let rs : Array[(String, String)] = []
    if !self.peek_kw(RBrace) {
      while true {
        let from = self.parse_ident()
        self.bump_kw(KwAs)
        let to = self.parse_ident()
        rs.push((from, to))
        if self.peek_kw(Comma) {
          self.bump_kw(Comma)
          if self.peek_kw(RBrace) {
            break
          }
          continue
        }
        break
      }
    }
    self.bump_kw(RBrace)
    renames = Some(rs)
    // wasm-tools accepts `include X with { ... }` without a trailing `;`.
    self.eat_kw(Semi)
  } else {
    self.bump_kw(Semi)
  }
  { path, renames }
}

///|
fn Parser::parse_resource_decl(self : Parser) -> ResourceDecl raise WitError {
  self.bump_kw(KwResource)
  let name = self.parse_ident()
  let methods : Array[FuncDecl] = []
  if self.peek_kw(LBrace) {
    self.bump_kw(LBrace)
    while !self.peek_kw(RBrace) {
      self.skip_gates()
      if self.peek_kw(RBrace) {
        break
      }
      // Methods use the same syntax as interface functions: `id: func ...;`
      methods.push(self.parse_func_decl())
      self.bump_kw(Semi)
    }
    self.bump_kw(RBrace)
  }
  { name, methods }
}

///|
fn Parser::parse_variant_decl(self : Parser) -> VariantDecl raise WitError {
  self.bump_kw(KwVariant)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let cases : Array[VariantCase] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(RBrace) {
      break
    }
    let case_name = self.parse_ident()
    let mut payload : TypeExpr? = None
    if self.peek_kw(LParen) {
      self.bump_kw(LParen)
      payload = Some(self.parse_type())
      self.bump_kw(RParen)
    }
    cases.push({ name: case_name, payload })
    self.eat_kw(Comma)
  }
  self.bump_kw(RBrace)
  { name, cases }
}

///|
fn Parser::parse_flags_decl(self : Parser) -> FlagsDecl raise WitError {
  self.bump_kw(KwFlags)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let flags : Array[String] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(RBrace) {
      break
    }
    flags.push(self.parse_ident())
    self.eat_kw(Comma)
  }
  self.bump_kw(RBrace)
  { name, flags }
}

///|
fn Parser::parse_enum_decl(self : Parser) -> EnumDecl raise WitError {
  self.bump_kw(KwEnum)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let cases : Array[String] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(RBrace) {
      break
    }
    cases.push(self.parse_ident())
    self.eat_kw(Comma)
  }
  self.bump_kw(RBrace)
  { name, cases }
}

///|
fn Parser::parse_interface(self : Parser) -> Interface raise WitError {
  self.bump_kw(KwInterface)
  let name = self.parse_ident()
  self.bump_kw(LBrace)
  let items : Array[InterfaceItem] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(RBrace) {
      break
    }
    if self.peek_kw(KwUse) {
      items.push(Use(self.parse_use_item()))
    } else if self.peek_kw(KwType) {
      items.push(TypeAlias(self.parse_type_alias()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwRecord) {
      items.push(Record(self.parse_record_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwResource) {
      items.push(Resource(self.parse_resource_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwVariant) {
      items.push(Variant(self.parse_variant_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwFlags) {
      items.push(Flags(self.parse_flags_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwEnum) {
      items.push(Enum(self.parse_enum_decl()))
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
    self.skip_gates()
    if self.peek_kw(RBrace) {
      break
    }
    if self.peek_kw(KwImport) || self.peek_kw(KwExport) {
      let is_import = self.peek_kw(KwImport)
      self.i = self.i + 1
      // `import name: ...` vs `import use-path;`
      //
      // Disambiguation:
      // - named form: `id ':' ('interface' | 'async'? 'func')`
      // - use-path form: includes ':' but next token is `Ident`, not `interface`/`func`.
      if self.peek_kw(Ident("")) && self.peek_next_is(Colon) {
        // Peek after ':' to see if this is a named extern-type.
        if self.i + 2 < self.toks.length() {
          match self.toks[self.i + 2].kind {
            KwInterface | KwFunc | KwAsync => {
              let nm = self.parse_ident()
              self.bump_kw(Colon)
              if self.peek_kw(KwInterface) {
                let iface = self.parse_inline_interface()
                if is_import {
                  items.push(ImportInlineInterface(nm, iface))
                } else {
                  items.push(ExportInlineInterface(nm, iface))
                }
              } else {
                // func-type ends with ';'
                let f = self.parse_func_type_after_colon(nm)
                if is_import {
                  items.push(ImportFunc(f))
                } else {
                  items.push(ExportFunc(f))
                }
                self.bump_kw(Semi)
              }
              continue
            }
            _ => ()
          }
        }
      }
      // Otherwise parse as `use-path;`
      let p = self.parse_use_path_until([Semi])
      self.bump_kw(Semi)
      if is_import {
        items.push(Import(p))
      } else {
        items.push(Export(p))
      }
    } else if self.peek_kw(KwInclude) {
      items.push(Include(self.parse_include_item()))
    } else if self.peek_kw(KwUse) {
      items.push(Use(self.parse_use_item()))
    } else if self.peek_kw(KwType) {
      items.push(TypeAlias(self.parse_type_alias()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwRecord) {
      items.push(Record(self.parse_record_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwResource) {
      items.push(Resource(self.parse_resource_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwVariant) {
      items.push(Variant(self.parse_variant_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwFlags) {
      items.push(Flags(self.parse_flags_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwEnum) {
      items.push(Enum(self.parse_enum_decl()))
      self.eat_kw(Semi)
    } else {
      raise self.err_here(
        "expected `import`, `export`, `include`, `use`, or type definition",
      )
    }
  }
  self.bump_kw(RBrace)
  { name, items }
}

///|
fn Parser::parse_inline_interface(
  self : Parser,
) -> InlineInterface raise WitError {
  self.bump_kw(KwInterface)
  self.bump_kw(LBrace)
  let items : Array[InterfaceItem] = []
  while !self.peek_kw(RBrace) {
    self.skip_gates()
    if self.peek_kw(RBrace) {
      break
    }
    if self.peek_kw(KwUse) {
      items.push(Use(self.parse_use_item()))
    } else if self.peek_kw(KwType) {
      items.push(TypeAlias(self.parse_type_alias()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwRecord) {
      items.push(Record(self.parse_record_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwResource) {
      items.push(Resource(self.parse_resource_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwVariant) {
      items.push(Variant(self.parse_variant_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwFlags) {
      items.push(Flags(self.parse_flags_decl()))
      self.eat_kw(Semi)
    } else if self.peek_kw(KwEnum) {
      items.push(Enum(self.parse_enum_decl()))
      self.eat_kw(Semi)
    } else {
      items.push(Func(self.parse_func_decl()))
      self.bump_kw(Semi)
    }
  }
  self.bump_kw(RBrace)
  { items, }
}

///|
fn Parser::parse_func_type_after_colon(
  self : Parser,
  name : String,
) -> FuncDecl raise WitError {
  let mut is_async = false
  if self.peek_kw(KwAsync) {
    self.bump_kw(KwAsync)
    is_async = true
  }
  self.bump_kw(KwFunc)
  self.bump_kw(LParen)
  let params = self.parse_named_type_list(RParen)
  self.bump_kw(RParen)
  let results : Array[(String?, TypeExpr)] = []
  if self.peek_kw(Arrow) {
    self.bump_kw(Arrow)
    results.push((None, self.parse_type()))
  }
  { name, is_async, params, results }
}

///|
fn Parser::parse_func_decl(self : Parser) -> FuncDecl raise WitError {
  let name = self.parse_ident()
  self.bump_kw(Colon)
  let mut is_async = false
  if self.peek_kw(KwAsync) {
    self.bump_kw(KwAsync)
    is_async = true
  }
  self.bump_kw(KwFunc)
  self.bump_kw(LParen)
  let params = self.parse_named_type_list(RParen)
  self.bump_kw(RParen)
  let results : Array[(String?, TypeExpr)] = []
  if self.peek_kw(Arrow) {
    self.bump_kw(Arrow)
    results.push((None, self.parse_type()))
  }
  { name, is_async, params, results }
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
  // Builtin type constructors which take angle-bracketed parameters.
  let mut ctor : String? = None
  if self.peek_kw(KwTuple) {
    self.bump_kw(KwTuple)
    ctor = Some("tuple")
  } else if self.peek_kw(KwList) {
    self.bump_kw(KwList)
    ctor = Some("list")
  } else if self.peek_kw(KwOption) {
    self.bump_kw(KwOption)
    ctor = Some("option")
  } else if self.peek_kw(KwResult) {
    self.bump_kw(KwResult)
    ctor = Some("result")
  } else if self.peek_kw(KwBorrow) {
    self.bump_kw(KwBorrow)
    ctor = Some("borrow")
  } else if self.peek_kw(KwFuture) {
    self.bump_kw(KwFuture)
    ctor = Some("future")
  } else if self.peek_kw(KwStream) {
    self.bump_kw(KwStream)
    ctor = Some("stream")
  }
  match ctor {
    Some(name) =>
      if self.peek_kw(LAngle) {
        self.bump_kw(LAngle)
        let args : Array[TypeExpr] = []
        if !self.peek_kw(RAngle) {
          while true {
            args.push(self.parse_type())
            if self.peek_kw(Comma) {
              self.bump_kw(Comma)
              if self.peek_kw(RAngle) {
                break
              }
              // If this is list<T, N>, consume N and exit.
              if name == "list" {
                match self.toks[self.i].kind {
                  IntLit(_) => {
                    self.i = self.i + 1
                    // Optional trailing comma before '>'.
                    self.eat_kw(Comma)
                    break
                  }
                  _ => ()
                }
              }
              continue
            }
            break
          }
        }
        self.bump_kw(RAngle)
        Apply(name, args)
      } else {
        // `result`, `future`, `stream` may omit their parameters.
        Apply(name, [])
      }
    None => {
      let name = self.parse_ident()
      if self.peek_kw(LAngle) {
        self.bump_kw(LAngle)
        let args : Array[TypeExpr] = []
        if !self.peek_kw(RAngle) {
          while true {
            args.push(self.parse_type())
            if self.peek_kw(Comma) {
              self.bump_kw(Comma)
              if self.peek_kw(RAngle) {
                break
              }
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
      // Allow trailing comma.
      if self.peek_kw(end) {
        break
      }
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
    (Ident(_), Ident(_))
    | (IntLit(_), IntLit(_))
    | (StrLit(_), StrLit(_))
    | (KwPackage, KwPackage)
    | (KwInterface, KwInterface)
    | (KwWorld, KwWorld)
    | (KwUse, KwUse)
    | (KwAs, KwAs)
    | (KwWith, KwWith)
    | (KwInclude, KwInclude)
    | (KwType, KwType)
    | (KwResource, KwResource)
    | (KwEnum, KwEnum)
    | (KwFlags, KwFlags)
    | (KwVariant, KwVariant)
    | (KwFunc, KwFunc)
    | (KwImport, KwImport)
    | (KwExport, KwExport)
    | (KwRecord, KwRecord)
    | (KwTuple, KwTuple)
    | (KwList, KwList)
    | (KwOption, KwOption)
    | (KwResult, KwResult)
    | (KwBorrow, KwBorrow)
    | (KwFuture, KwFuture)
    | (KwStream, KwStream)
    | (KwAsync, KwAsync)
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
    | (Dash, Dash)
    | (Plus, Plus)
    | (Eq, Eq)
    | (Arrow, Arrow) => true
    _ => false
  }
}
