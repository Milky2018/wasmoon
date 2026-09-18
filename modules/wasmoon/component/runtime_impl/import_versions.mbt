///|
// Prereleases use exact matching. Stable versions share a compatibility track:
// major for 1+, minor for 0.x, and patch for 0.0.x.
fn import_version(name : String) -> (String, String, String, String)? {
  guard name.split_once("@") is Some((base, version)) else { return None }
  let parts = version.split(".").to_array()
  guard parts.length() == 3 else { return None }
  for part in parts {
    if part.is_empty() || (part.length() > 1 && part.has_prefix("0")) {
      return None
    }
    for code in part {
      if code < '0' || code > '9' {
        return None
      }
    }
  }
  Some(
    (
      base.to_owned(),
      parts[0].to_owned(),
      parts[1].to_owned(),
      parts[2].to_owned(),
    ),
  )
}

///|
fn version_number_less(a : String, b : String) -> Bool {
  if a.length() == b.length() {
    a < b
  } else {
    a.length() < b.length()
  }
}

///|
fn compatible_import(
  imports : Map[String, ComponentExtern],
  name : String,
) -> ComponentExtern? {
  if imports.get(name) is Some(value) {
    return Some(value)
  }
  guard import_version(name) is Some((base, major, minor, patch)) else {
    return None
  }
  let mut best : (String, String, ComponentExtern)? = None
  for candidate, value in imports {
    guard import_version(candidate) is Some((other, a, b, c)) else { continue }
    if other != base ||
      a != major ||
      (major == "0" && (b != minor || (minor == "0" && c != patch))) {
      continue
    }
    match best {
      None => best = Some((b, c, value))
      Some((old_minor, old_patch, _)) =>
        if version_number_less(old_minor, b) ||
          (old_minor == b && version_number_less(old_patch, c)) {
          best = Some((b, c, value))
        }
    }
  }
  best.map(entry => entry.2)
}
