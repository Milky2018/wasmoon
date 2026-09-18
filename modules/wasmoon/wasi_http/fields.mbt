///|
/// HTTP fields preserve order, spelling and repeated values.
pub struct HttpFields {
  entries : Array[(String, Bytes)]
  immutable : Bool
}

///|
pub(all) enum HeaderError {
  InvalidSyntax
  Forbidden
  Immutable
  SizeExceeded
} derive(Eq, Debug)

///|
pub extend HeaderError with Eq::{not_equal, equal}

///|
pub extend HeaderError with Debug::{to_repr}

///|
fn field_token(text : String) -> Bool {
  if text.is_empty() {
    return false
  }
  for code in text {
    if !(code
      is ('a'..='z'
      | 'A'..='Z'
      | '0'..='9'
      | '!'
      | '#'
      | '$'
      | '%'
      | '&'
      | '\''
      | '*'
      | '+'
      | '-'
      | '.'
      | '^'
      | '_'
      | '`'
      | '|'
      | '~')) {
      return false
    }
  }
  true
}

///|
fn field_valid(value : Bytes) -> Bool {
  for byte in value {
    if (byte < 32 && byte != 9) || byte == 127 {
      return false
    }
  }
  true
}

///|
fn field_forbidden(name : String) -> Bool {
  [
    "connection", "proxy-connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "transfer-encoding", "upgrade",
  ].contains(name.to_lower())
}

///|
pub fn HttpFields::from_list(
  entries? : Array[(String, Bytes)] = [],
) -> Result[HttpFields, HeaderError] {
  let fields = { entries: [], immutable: false, }
  for entry in entries {
    let (name, value) = entry
    match fields.append(name, value) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(fields)
}

///|
pub fn HttpFields::copy_all(self : HttpFields) -> Array[(String, Bytes)] {
  self.entries.copy()
}

///|
pub fn HttpFields::clone(self : HttpFields) -> HttpFields {
  { entries: self.entries.copy(), immutable: false, }
}

///|
fn HttpFields::freeze(self : HttpFields) -> HttpFields {
  { entries: self.entries.copy(), immutable: true, }
}

///|
pub fn HttpFields::get(self : HttpFields, name : String) -> Array[Bytes] {
  let key = name.to_lower()
  self.entries.filter_map(fn(entry) {
    if entry.0.to_lower() == key {
      Some(entry.1)
    } else {
      None
    }
  })
}

///|
pub fn HttpFields::has(self : HttpFields, name : String) -> Bool {
  !self.get(name).is_empty()
}

///|
fn fields_validate(
  entries : Array[(String, Bytes)],
) -> Result[Unit, HeaderError] {
  let mut size = 0
  for entry in entries {
    let (name, value) = entry
    if !field_token(name) || !field_valid(value) {
      return Err(InvalidSyntax)
    }
    if field_forbidden(name) {
      return Err(Forbidden)
    }
    size += name.length() + value.length()
    if size > 65536 || entries.length() > 1024 {
      return Err(SizeExceeded)
    }
  }
  Ok(())
}

///|
pub fn HttpFields::append(
  self : HttpFields,
  name : String,
  value : Bytes,
) -> Result[Unit, HeaderError] {
  if self.immutable {
    return Err(Immutable)
  }
  let entries = self.entries.copy()
  entries.push((name, value))
  match fields_validate(entries) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  self.entries.push((name, value))
  Ok(())
}

///|
pub fn HttpFields::set(
  self : HttpFields,
  name : String,
  values : Array[Bytes],
) -> Result[Unit, HeaderError] {
  if self.immutable {
    return Err(Immutable)
  }
  if !field_token(name) {
    return Err(InvalidSyntax)
  }
  if field_forbidden(name) {
    return Err(Forbidden)
  }
  let key = name.to_lower()
  let entries = self.entries.filter(fn(entry) { entry.0.to_lower() != key })
  for value in values {
    entries.push((name, value))
  }
  match fields_validate(entries) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  self.entries.clear()
  self.entries.append(entries)
  Ok(())
}

///|
pub fn HttpFields::delete(
  self : HttpFields,
  name : String,
) -> Result[Unit, HeaderError] {
  if self.immutable {
    return Err(Immutable)
  }
  let key = name.to_lower()
  let entries = self.entries.filter(fn(entry) { entry.0.to_lower() != key })
  self.entries.clear()
  self.entries.append(entries)
  Ok(())
}
