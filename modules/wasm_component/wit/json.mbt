///|
pub fn package_to_json(pkg : Package) -> String {
  let sb = StringBuilder::StringBuilder()
  write_package_json(sb, pkg)
  sb.to_string()
}

///|
fn write_package_json(sb : StringBuilder, pkg : Package) -> Unit {
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
  sb.write_string(",\"nested\":[")
  for i in 0..<pkg.nested.length() {
    if i > 0 {
      sb.write_char(',')
    }
    write_package_json(sb, pkg.nested[i])
  }
  sb.write_char(']')
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
            Func(fd) => json_item(sb, "{\"kind\":\"func\",\"name\":", fd.name)
            TypeAlias(td) =>
              json_item(sb, "{\"kind\":\"type\",\"name\":", td.name)
            Record(rd) =>
              json_item(sb, "{\"kind\":\"record\",\"name\":", rd.name)
            Use(u) => json_item(sb, "{\"kind\":\"use\",\"path\":", u.path.raw)
            Resource(r) =>
              json_item(sb, "{\"kind\":\"resource\",\"name\":", r.name)
            Variant(v) =>
              json_item(sb, "{\"kind\":\"variant\",\"name\":", v.name)
            Flags(f) => json_item(sb, "{\"kind\":\"flags\",\"name\":", f.name)
            Enum(e) => json_item(sb, "{\"kind\":\"enum\",\"name\":", e.name)
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
            Import(p) => json_item(sb, "{\"kind\":\"import\",\"path\":", p.raw)
            Export(p) => json_item(sb, "{\"kind\":\"export\",\"path\":", p.raw)
            ImportFunc(f) =>
              json_item(sb, "{\"kind\":\"import-func\",\"name\":", f.name)
            ExportFunc(f) =>
              json_item(sb, "{\"kind\":\"export-func\",\"name\":", f.name)
            ImportInlineInterface(nm, _) =>
              json_item(sb, "{\"kind\":\"import-interface\",\"name\":", nm)
            ExportInlineInterface(nm, _) =>
              json_item(sb, "{\"kind\":\"export-interface\",\"name\":", nm)
            Include(inc) =>
              json_item(sb, "{\"kind\":\"include\",\"path\":", inc.path.raw)
            Use(u) => json_item(sb, "{\"kind\":\"use\",\"path\":", u.path.raw)
            TypeAlias(td) =>
              json_item(sb, "{\"kind\":\"type\",\"name\":", td.name)
            Record(rd) =>
              json_item(sb, "{\"kind\":\"record\",\"name\":", rd.name)
            Resource(r) =>
              json_item(sb, "{\"kind\":\"resource\",\"name\":", r.name)
            Variant(v) =>
              json_item(sb, "{\"kind\":\"variant\",\"name\":", v.name)
            Flags(f) => json_item(sb, "{\"kind\":\"flags\",\"name\":", f.name)
            Enum(e) => json_item(sb, "{\"kind\":\"enum\",\"name\":", e.name)
          }
        }
        sb.write_string("]}")
      }
      ToplevelUse(u) => {
        sb.write_string("{\"kind\":\"use\",\"path\":")
        json_string(sb, u.path.raw)
        sb.write_string(",\"as\":")
        match u.as_name {
          Some(n) => json_string(sb, n)
          None => sb.write_string("null")
        }
        sb.write_string("}")
      }
    }
  }
  sb.write_string("]}")
}

///|
#inline
fn json_item(sb : StringBuilder, prefix : String, value : String) -> Unit {
  sb.write_string(prefix)
  json_string(sb, value)
  sb.write_char('}')
}

///|
fn json_string(sb : StringBuilder, s : String) -> Unit {
  sb.write_char('"')
  for unit in s.code_units() {
    if unit == 0x22 || unit == 0x5C || unit < 0x20 {
      for c in s {
        match c {
          '"' => sb.write_string("\\\"")
          '\\' => sb.write_string("\\\\")
          '\n' => sb.write_string("\\n")
          '\r' => sb.write_string("\\r")
          '\t' => sb.write_string("\\t")
          '\u{0020}'..<='\u{10FFFF}' => sb.write_char(c)
          _ => {
            let code = c.to_int()
            sb.write_string("\\u00")
            if code < 0x10 {
              sb.write_char('0')
            }
            sb.write_string(code.to_string(radix=16))
          }
        }
      }
      sb.write_char('"')
      return
    }
  }
  sb.write_string(s)
  sb.write_char('"')
}
