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
  let mut prev_world = false
  for it in pkg.items {
    if !first {
      // wasm-tools does not insert an extra blank line between consecutive `world` items.
      let cur_world = match it {
        World(_) => true
        _ => false
      }
      if !(prev_world && cur_world) {
        sb.write_char('\n')
      }
      prev_world = cur_world
    } else {
      prev_world = match it {
        World(_) => true
        _ => false
      }
    }
    first = false
    match it {
      Interface(i) => format_interface(sb, i)
      World(w) => format_world(sb, w)
      ToplevelUse(u) => {
        sb.write_string("use ")
        sb.write_string(u.path.raw)
        match u.as_name {
          Some(n) => {
            sb.write_string(" as ")
            sb.write_string(n)
          }
          None => ()
        }
        sb.write_string(";\n")
      }
    }
  }
  if pkg.nested.length() > 0 {
    if pkg.items.length() > 0 {
      sb.write_char('\n')
    }
    for i in 0..<pkg.nested.length() {
      if i > 0 {
        sb.write_char('\n')
      }
      format_nested_package(sb, pkg.nested[i])
    }
  }
  sb.to_string()
}

///|
fn format_nested_package(sb : StringBuilder, pkg : Package) -> Unit {
  // Nested package notation: `package name@ver { ... }`
  let name = pkg.name.unwrap_or_else(fn() { "<unknown>" })
  sb.write_string("package ")
  sb.write_string(name)
  match pkg.version {
    Some(v) => {
      sb.write_char('@')
      sb.write_string(v)
    }
    None => ()
  }
  sb.write_string(" {\n")
  for it in pkg.items {
    let tmp = StringBuilder::new()
    match it {
      Interface(i) => format_interface(tmp, i)
      World(w) => format_world(tmp, w)
      ToplevelUse(u) => {
        tmp.write_string("use ")
        tmp.write_string(u.path.raw)
        match u.as_name {
          Some(n) => {
            tmp.write_string(" as ")
            tmp.write_string(n)
          }
          None => ()
        }
        tmp.write_string(";\n")
      }
    }
    sb.write_string(indent_lines(tmp.to_string(), "  "))
  }
  for np in pkg.nested {
    sb.write_char('\n')
    let tmp = StringBuilder::new()
    format_nested_package(tmp, np)
    sb.write_string(indent_lines(tmp.to_string(), "  "))
  }
  sb.write_string("}\n")
}

///|
fn indent_lines(s : String, prefix : String) -> String {
  let sb = StringBuilder::new()
  let mut at_line_start = true
  for c in s {
    if at_line_start {
      sb.write_string(prefix)
      at_line_start = false
    }
    sb.write_char(c)
    if c == '\n' {
      at_line_start = true
    }
  }
  sb.to_string()
}

///|
fn format_interface(sb : StringBuilder, it : Interface) -> Unit {
  sb.write_string("interface ")
  sb.write_string(it.name)
  sb.write_string(" {\n")
  let mut has_use = false
  let mut has_other = false
  for item in it.items {
    match item {
      Use(_) => has_use = true
      _ => has_other = true
    }
  }
  if has_use {
    for item in it.items {
      match item {
        Use(u) => {
          sb.write_string("  use ")
          sb.write_string(u.path.raw)
          sb.write_string(".{")
          for i in 0..<u.names.length() {
            if i > 0 {
              sb.write_string(", ")
            }
            let (n, asn) = u.names[i]
            sb.write_string(n)
            match asn {
              Some(nn) => {
                sb.write_string(" as ")
                sb.write_string(nn)
              }
              None => ()
            }
          }
          sb.write_string("};\n")
        }
        _ => ()
      }
    }
    if has_other {
      sb.write_char('\n')
    }
  }
  for item in it.items {
    match item {
      Use(_) => ()
      Func(f) => {
        sb.write_string("  ")
        sb.write_string(f.name)
        sb.write_string(": ")
        if f.is_async {
          sb.write_string("async ")
        }
        sb.write_string("func(")
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
      Resource(r) => {
        sb.write_string("  resource ")
        sb.write_string(r.name)
        if r.methods.length() == 0 {
          sb.write_string(";\n")
        } else {
          sb.write_string(" {\n")
          for m in r.methods {
            sb.write_string("    ")
            sb.write_string(m.name)
            sb.write_string(": ")
            if m.is_async {
              sb.write_string("async ")
            }
            sb.write_string("func(")
            for i in 0..<m.params.length() {
              if i > 0 {
                sb.write_string(", ")
              }
              let (pn, pt) = m.params[i]
              sb.write_string(pn)
              sb.write_string(": ")
              format_type(sb, pt)
            }
            sb.write_char(')')
            if m.results.length() > 0 {
              sb.write_string(" -> ")
              if m.results.length() == 1 && m.results[0].0 is None {
                format_type(sb, m.results[0].1)
              } else {
                sb.write_char('(')
                for i in 0..<m.results.length() {
                  if i > 0 {
                    sb.write_string(", ")
                  }
                  let (rn, rt) = m.results[i]
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
          sb.write_string("  }\n")
        }
      }
      Variant(v) => {
        sb.write_string("  variant ")
        sb.write_string(v.name)
        sb.write_string(" {\n")
        for c in v.cases {
          sb.write_string("    ")
          sb.write_string(c.name)
          match c.payload {
            Some(t) => {
              sb.write_char('(')
              format_type(sb, t)
              sb.write_char(')')
            }
            None => ()
          }
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
      Flags(f) => {
        sb.write_string("  flags ")
        sb.write_string(f.name)
        sb.write_string(" {\n")
        for n in f.flags {
          sb.write_string("    ")
          sb.write_string(n)
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
      Enum(e) => {
        sb.write_string("  enum ")
        sb.write_string(e.name)
        sb.write_string(" {\n")
        for n in e.cases {
          sb.write_string("    ")
          sb.write_string(n)
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
  fn is_export_item(it : WorldItem) -> Bool {
    match it {
      Export(_) | ExportFunc(_) | ExportInlineInterface(_, _) => true
      _ => false
    }
  }

  let mut has_export = false
  let mut has_nonexport = false
  for it in w.items {
    if is_export_item(it) {
      has_export = true
    } else {
      has_nonexport = true
    }
  }
  fn emit(it : WorldItem) -> Unit {
    match it {
      Import(p) => {
        sb.write_string("  import ")
        sb.write_string(p.raw)
        sb.write_string(";\n")
      }
      Export(p) => {
        sb.write_string("  export ")
        sb.write_string(p.raw)
        sb.write_string(";\n")
      }
      ImportFunc(f) => {
        sb.write_string("  import ")
        sb.write_string(f.name)
        sb.write_string(": ")
        if f.is_async {
          sb.write_string("async ")
        }
        sb.write_string("func(")
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
          // WIT MVP supports a single result; this code prints the existing AST shape.
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
      ExportFunc(f) => {
        sb.write_string("  export ")
        sb.write_string(f.name)
        sb.write_string(": ")
        if f.is_async {
          sb.write_string("async ")
        }
        sb.write_string("func(")
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
      ImportInlineInterface(nm, iface) => {
        sb.write_string("  import ")
        sb.write_string(nm)
        sb.write_string(": interface {\n")
        for item in iface.items {
          match item {
            Func(f) => {
              sb.write_string("    ")
              sb.write_string(f.name)
              sb.write_string(": ")
              if f.is_async {
                sb.write_string("async ")
              }
              sb.write_string("func(")
              for i in 0..<f.params.length() {
                if i > 0 {
                  sb.write_string(", ")
                }
                let (pn, pt) = f.params[i]
                sb.write_string(pn)
                sb.write_string(": ")
                format_type(sb, pt)
              }
              sb.write_char(')')
              if f.results.length() > 0 {
                sb.write_string(" -> ")
                format_type(sb, f.results[0].1)
              }
              sb.write_string(";\n")
            }
            TypeAlias(t) => {
              sb.write_string("    type ")
              sb.write_string(t.name)
              sb.write_string(" = ")
              format_type(sb, t.ty)
              sb.write_string(";\n")
            }
            Record(r) => {
              sb.write_string("    record ")
              sb.write_string(r.name)
              sb.write_string(" {\n")
              for field in r.fields {
                let (n, t) = field
                sb.write_string("      ")
                sb.write_string(n)
                sb.write_string(": ")
                format_type(sb, t)
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
            Use(u) => {
              sb.write_string("    use ")
              sb.write_string(u.path.raw)
              sb.write_string(".{")
              for i in 0..<u.names.length() {
                if i > 0 {
                  sb.write_string(", ")
                }
                let (n, asn) = u.names[i]
                sb.write_string(n)
                match asn {
                  Some(nn) => {
                    sb.write_string(" as ")
                    sb.write_string(nn)
                  }
                  None => ()
                }
              }
              sb.write_string("};\n")
            }
            Resource(r) => {
              sb.write_string("    resource ")
              sb.write_string(r.name)
              if r.methods.length() == 0 {
                sb.write_string(";\n")
              } else {
                sb.write_string(" {\n")
                for m in r.methods {
                  sb.write_string("      ")
                  sb.write_string(m.name)
                  sb.write_string(": ")
                  if m.is_async {
                    sb.write_string("async ")
                  }
                  sb.write_string("func(")
                  for i in 0..<m.params.length() {
                    if i > 0 {
                      sb.write_string(", ")
                    }
                    let (pn, pt) = m.params[i]
                    sb.write_string(pn)
                    sb.write_string(": ")
                    format_type(sb, pt)
                  }
                  sb.write_char(')')
                  if m.results.length() > 0 {
                    sb.write_string(" -> ")
                    format_type(sb, m.results[0].1)
                  }
                  sb.write_string(";\n")
                }
                sb.write_string("    }\n")
              }
            }
            Variant(v) => {
              sb.write_string("    variant ")
              sb.write_string(v.name)
              sb.write_string(" {\n")
              for c in v.cases {
                sb.write_string("      ")
                sb.write_string(c.name)
                match c.payload {
                  Some(t) => {
                    sb.write_char('(')
                    format_type(sb, t)
                    sb.write_char(')')
                  }
                  None => ()
                }
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
            Flags(f) => {
              sb.write_string("    flags ")
              sb.write_string(f.name)
              sb.write_string(" {\n")
              for n in f.flags {
                sb.write_string("      ")
                sb.write_string(n)
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
            Enum(e) => {
              sb.write_string("    enum ")
              sb.write_string(e.name)
              sb.write_string(" {\n")
              for n in e.cases {
                sb.write_string("      ")
                sb.write_string(n)
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
          }
        }
        sb.write_string("  }\n")
      }
      ExportInlineInterface(nm, iface) => {
        // Same formatting as `import name: interface { ... }`
        sb.write_string("  export ")
        sb.write_string(nm)
        sb.write_string(": interface {\n")
        for item in iface.items {
          match item {
            Func(f) => {
              sb.write_string("    ")
              sb.write_string(f.name)
              sb.write_string(": ")
              if f.is_async {
                sb.write_string("async ")
              }
              sb.write_string("func(")
              for i in 0..<f.params.length() {
                if i > 0 {
                  sb.write_string(", ")
                }
                let (pn, pt) = f.params[i]
                sb.write_string(pn)
                sb.write_string(": ")
                format_type(sb, pt)
              }
              sb.write_char(')')
              if f.results.length() > 0 {
                sb.write_string(" -> ")
                format_type(sb, f.results[0].1)
              }
              sb.write_string(";\n")
            }
            TypeAlias(t) => {
              sb.write_string("    type ")
              sb.write_string(t.name)
              sb.write_string(" = ")
              format_type(sb, t.ty)
              sb.write_string(";\n")
            }
            Record(r) => {
              sb.write_string("    record ")
              sb.write_string(r.name)
              sb.write_string(" {\n")
              for field in r.fields {
                let (n, t) = field
                sb.write_string("      ")
                sb.write_string(n)
                sb.write_string(": ")
                format_type(sb, t)
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
            Use(u) => {
              sb.write_string("    use ")
              sb.write_string(u.path.raw)
              sb.write_string(".{")
              for i in 0..<u.names.length() {
                if i > 0 {
                  sb.write_string(", ")
                }
                let (n, asn) = u.names[i]
                sb.write_string(n)
                match asn {
                  Some(nn) => {
                    sb.write_string(" as ")
                    sb.write_string(nn)
                  }
                  None => ()
                }
              }
              sb.write_string("};\n")
            }
            Resource(r) => {
              sb.write_string("    resource ")
              sb.write_string(r.name)
              if r.methods.length() == 0 {
                sb.write_string(";\n")
              } else {
                sb.write_string(" {\n")
                for m in r.methods {
                  sb.write_string("      ")
                  sb.write_string(m.name)
                  sb.write_string(": ")
                  if m.is_async {
                    sb.write_string("async ")
                  }
                  sb.write_string("func(")
                  for i in 0..<m.params.length() {
                    if i > 0 {
                      sb.write_string(", ")
                    }
                    let (pn, pt) = m.params[i]
                    sb.write_string(pn)
                    sb.write_string(": ")
                    format_type(sb, pt)
                  }
                  sb.write_char(')')
                  if m.results.length() > 0 {
                    sb.write_string(" -> ")
                    format_type(sb, m.results[0].1)
                  }
                  sb.write_string(";\n")
                }
                sb.write_string("    }\n")
              }
            }
            Variant(v) => {
              sb.write_string("    variant ")
              sb.write_string(v.name)
              sb.write_string(" {\n")
              for c in v.cases {
                sb.write_string("      ")
                sb.write_string(c.name)
                match c.payload {
                  Some(t) => {
                    sb.write_char('(')
                    format_type(sb, t)
                    sb.write_char(')')
                  }
                  None => ()
                }
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
            Flags(f) => {
              sb.write_string("    flags ")
              sb.write_string(f.name)
              sb.write_string(" {\n")
              for n in f.flags {
                sb.write_string("      ")
                sb.write_string(n)
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
            Enum(e) => {
              sb.write_string("    enum ")
              sb.write_string(e.name)
              sb.write_string(" {\n")
              for n in e.cases {
                sb.write_string("      ")
                sb.write_string(n)
                sb.write_string(",\n")
              }
              sb.write_string("    }\n")
            }
          }
        }
        sb.write_string("  }\n")
      }
      Include(inc) => {
        sb.write_string("  include ")
        sb.write_string(inc.path.raw)
        match inc.renames {
          Some(rs) => {
            sb.write_string(" with { ")
            for i in 0..<rs.length() {
              if i > 0 {
                sb.write_string(", ")
              }
              let (from, to) = rs[i]
              sb.write_string(from)
              sb.write_string(" as ")
              sb.write_string(to)
            }
            sb.write_string(" }")
          }
          None => ()
        }
        match inc.renames {
          Some(_) => sb.write_string("\n")
          None => sb.write_string(";\n")
        }
      }
      Use(u) => {
        sb.write_string("  use ")
        sb.write_string(u.path.raw)
        sb.write_string(".{")
        for i in 0..<u.names.length() {
          if i > 0 {
            sb.write_string(", ")
          }
          let (n, asn) = u.names[i]
          sb.write_string(n)
          match asn {
            Some(nn) => {
              sb.write_string(" as ")
              sb.write_string(nn)
            }
            None => ()
          }
        }
        sb.write_string("};\n")
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
      Resource(r) => {
        sb.write_string("  resource ")
        sb.write_string(r.name)
        if r.methods.length() == 0 {
          sb.write_string(";\n")
        } else {
          sb.write_string(" {\n")
          for m in r.methods {
            sb.write_string("    ")
            sb.write_string(m.name)
            sb.write_string(": ")
            if m.is_async {
              sb.write_string("async ")
            }
            sb.write_string("func(")
            for i in 0..<m.params.length() {
              if i > 0 {
                sb.write_string(", ")
              }
              let (pn, pt) = m.params[i]
              sb.write_string(pn)
              sb.write_string(": ")
              format_type(sb, pt)
            }
            sb.write_char(')')
            if m.results.length() > 0 {
              sb.write_string(" -> ")
              format_type(sb, m.results[0].1)
            }
            sb.write_string(";\n")
          }
          sb.write_string("  }\n")
        }
      }
      Variant(v) => {
        sb.write_string("  variant ")
        sb.write_string(v.name)
        sb.write_string(" {\n")
        for c in v.cases {
          sb.write_string("    ")
          sb.write_string(c.name)
          match c.payload {
            Some(t) => {
              sb.write_char('(')
              format_type(sb, t)
              sb.write_char(')')
            }
            None => ()
          }
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
      Flags(f) => {
        sb.write_string("  flags ")
        sb.write_string(f.name)
        sb.write_string(" {\n")
        for n in f.flags {
          sb.write_string("    ")
          sb.write_string(n)
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
      Enum(e) => {
        sb.write_string("  enum ")
        sb.write_string(e.name)
        sb.write_string(" {\n")
        for n in e.cases {
          sb.write_string("    ")
          sb.write_string(n)
          sb.write_string(",\n")
        }
        sb.write_string("  }\n")
      }
    }
  }

  for it in w.items {
    if !is_export_item(it) {
      emit(it)
    }
  }
  if has_export && has_nonexport {
    sb.write_char('\n')
  }
  for it in w.items {
    if is_export_item(it) {
      emit(it)
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
