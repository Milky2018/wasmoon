///|
pub fn format_package(pkg : Package) -> String {
  let sb = StringBuilder::StringBuilder()
  if pkg.name is Some(n) {
    sb.write_string("package ")
    sb.write_string(n)
    if pkg.version is Some(v) {
      sb.write_char('@')
      sb.write_string(v)
    }
    sb.write_string(";\n\n")
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
  if pkg.version is Some(v) {
    sb.write_char('@')
    sb.write_string(v)
  }
  sb.write_string(" {\n")
  for it in pkg.items {
    let tmp = StringBuilder::StringBuilder()
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
    let tmp = StringBuilder::StringBuilder()
    format_nested_package(tmp, np)
    sb.write_string(indent_lines(tmp.to_string(), "  "))
  }
  sb.write_string("}\n")
}

///|
fn indent_lines(s : String, prefix : String) -> String {
  let sb = StringBuilder::StringBuilder()
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
      if item is Use(_) {
        format_interface_item(sb, item, "  ")
      }
    }
    if has_other {
      sb.write_char('\n')
    }
  }
  for item in it.items {
    if !(item is Use(_)) {
      format_interface_item(sb, item, "  ")
    }
  }
  sb.write_string("}\n")
}

///|
fn format_interface_item(
  sb : StringBuilder,
  item : InterfaceItem,
  indent : String,
  first_result_only~ : Bool = false,
) -> Unit {
  let child_indent = indent + "  "
  sb.write_string(indent)
  match item {
    Func(f) => format_func_decl(sb, f, "", first_result_only~)
    Use(u) => {
      sb.write_string("use ")
      sb.write_string(u.path.raw)
      sb.write_string(".{")
      for i in 0..<u.names.length() {
        if i > 0 {
          sb.write_string(", ")
        }
        let (name, renamed) = u.names[i]
        sb.write_string(name)
        if renamed is Some(name) {
          sb.write_string(" as ")
          sb.write_string(name)
        }
      }
      sb.write_string("};\n")
    }
    TypeAlias(t) => {
      sb.write_string("type ")
      sb.write_string(t.name)
      sb.write_string(" = ")
      format_type(sb, t.ty)
      sb.write_string(";\n")
    }
    Record(r) => {
      sb.write_string("record ")
      sb.write_string(r.name)
      sb.write_string(" {\n")
      for field in r.fields {
        let (n, t) = field
        sb.write_string(child_indent)
        sb.write_string(n)
        sb.write_string(": ")
        format_type(sb, t)
        sb.write_string(",\n")
      }
      sb.write_string(indent)
      sb.write_string("}\n")
    }
    Resource(r) => {
      sb.write_string("resource ")
      sb.write_string(r.name)
      if r.methods.length() == 0 {
        sb.write_string(";\n")
      } else {
        sb.write_string(" {\n")
        for m in r.methods {
          format_func_decl(sb, m, child_indent, first_result_only~)
        }
        sb.write_string(indent)
        sb.write_string("}\n")
      }
    }
    Variant(v) => {
      sb.write_string("variant ")
      sb.write_string(v.name)
      sb.write_string(" {\n")
      for c in v.cases {
        sb.write_string(child_indent)
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
      sb.write_string(indent)
      sb.write_string("}\n")
    }
    Flags(f) => {
      sb.write_string("flags ")
      sb.write_string(f.name)
      sb.write_string(" {\n")
      for n in f.flags {
        sb.write_string(child_indent)
        sb.write_string(n)
        sb.write_string(",\n")
      }
      sb.write_string(indent)
      sb.write_string("}\n")
    }
    Enum(e) => {
      sb.write_string("enum ")
      sb.write_string(e.name)
      sb.write_string(" {\n")
      for n in e.cases {
        sb.write_string(child_indent)
        sb.write_string(n)
        sb.write_string(",\n")
      }
      sb.write_string(indent)
      sb.write_string("}\n")
    }
  }
}

///|
fn format_func_decl(
  sb : StringBuilder,
  func : FuncDecl,
  prefix : String,
  first_result_only~ : Bool = false,
) -> Unit {
  sb.write_string(prefix)
  sb.write_string(func.name)
  sb.write_string(": ")
  if func.is_async {
    sb.write_string("async ")
  }
  sb.write_string("func(")
  for i, param in func.params {
    if i > 0 {
      sb.write_string(", ")
    }
    let (name, ty) = param
    sb.write_string(name)
    sb.write_string(": ")
    format_type(sb, ty)
  }
  sb.write_char(')')
  if func.results.length() > 0 {
    sb.write_string(" -> ")
    if first_result_only ||
      (func.results.length() == 1 && func.results[0].0 is None) {
      format_type(sb, func.results[0].1)
    } else {
      sb.write_char('(')
      for i, result in func.results {
        if i > 0 {
          sb.write_string(", ")
        }
        let (name, ty) = result
        if name is Some(name) {
          sb.write_string(name)
          sb.write_string(": ")
        }
        format_type(sb, ty)
      }
      sb.write_char(')')
    }
  }
  sb.write_string(";\n")
}

///|
fn format_inline_interface(
  sb : StringBuilder,
  prefix : String,
  name : String,
  iface : InlineInterface,
) -> Unit {
  sb.write_string(prefix)
  sb.write_string(name)
  sb.write_string(": interface {\n")
  for item in iface.items {
    format_interface_item(sb, item, "    ", first_result_only=true)
  }
  sb.write_string("  }\n")
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
      ImportFunc(f) => format_func_decl(sb, f, "  import ")
      ExportFunc(f) => format_func_decl(sb, f, "  export ")
      ImportInlineInterface(name, iface) =>
        format_inline_interface(sb, "  import ", name, iface)
      ExportInlineInterface(name, iface) =>
        format_inline_interface(sb, "  export ", name, iface)
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
      Use(u) => format_interface_item(sb, Use(u), "  ")
      TypeAlias(t) => format_interface_item(sb, TypeAlias(t), "  ")
      Record(r) => format_interface_item(sb, Record(r), "  ")
      Resource(r) =>
        format_interface_item(sb, Resource(r), "  ", first_result_only=true)
      Variant(v) => format_interface_item(sb, Variant(v), "  ")
      Flags(f) => format_interface_item(sb, Flags(f), "  ")
      Enum(e) => format_interface_item(sb, Enum(e), "  ")
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
