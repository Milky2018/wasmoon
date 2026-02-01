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
  sb.write_string(",\"nested\":[")
  for i in 0..<pkg.nested.length() {
    if i > 0 {
      sb.write_char(',')
    }
    sb.write_string(package_to_json(pkg.nested[i]))
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
            Use(u) => {
              sb.write_string("{\"kind\":\"use\",\"path\":")
              json_string(sb, u.path.raw)
              sb.write_string("}")
            }
            Resource(r) => {
              sb.write_string("{\"kind\":\"resource\",\"name\":")
              json_string(sb, r.name)
              sb.write_string("}")
            }
            Variant(v) => {
              sb.write_string("{\"kind\":\"variant\",\"name\":")
              json_string(sb, v.name)
              sb.write_string("}")
            }
            Flags(f) => {
              sb.write_string("{\"kind\":\"flags\",\"name\":")
              json_string(sb, f.name)
              sb.write_string("}")
            }
            Enum(e) => {
              sb.write_string("{\"kind\":\"enum\",\"name\":")
              json_string(sb, e.name)
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
            Import(p) => {
              sb.write_string("{\"kind\":\"import\",\"path\":")
              json_string(sb, p.raw)
              sb.write_string("}")
            }
            Export(p) => {
              sb.write_string("{\"kind\":\"export\",\"path\":")
              json_string(sb, p.raw)
              sb.write_string("}")
            }
            ImportFunc(f) => {
              sb.write_string("{\"kind\":\"import-func\",\"name\":")
              json_string(sb, f.name)
              sb.write_string("}")
            }
            ExportFunc(f) => {
              sb.write_string("{\"kind\":\"export-func\",\"name\":")
              json_string(sb, f.name)
              sb.write_string("}")
            }
            ImportInlineInterface(nm, _) => {
              sb.write_string("{\"kind\":\"import-interface\",\"name\":")
              json_string(sb, nm)
              sb.write_string("}")
            }
            ExportInlineInterface(nm, _) => {
              sb.write_string("{\"kind\":\"export-interface\",\"name\":")
              json_string(sb, nm)
              sb.write_string("}")
            }
            Include(inc) => {
              sb.write_string("{\"kind\":\"include\",\"path\":")
              json_string(sb, inc.path.raw)
              sb.write_string("}")
            }
            Use(u) => {
              sb.write_string("{\"kind\":\"use\",\"path\":")
              json_string(sb, u.path.raw)
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
            Resource(r) => {
              sb.write_string("{\"kind\":\"resource\",\"name\":")
              json_string(sb, r.name)
              sb.write_string("}")
            }
            Variant(v) => {
              sb.write_string("{\"kind\":\"variant\",\"name\":")
              json_string(sb, v.name)
              sb.write_string("}")
            }
            Flags(f) => {
              sb.write_string("{\"kind\":\"flags\",\"name\":")
              json_string(sb, f.name)
              sb.write_string("}")
            }
            Enum(e) => {
              sb.write_string("{\"kind\":\"enum\",\"name\":")
              json_string(sb, e.name)
              sb.write_string("}")
            }
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
