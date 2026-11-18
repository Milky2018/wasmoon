///|
#cfg(platform="windows")
pub fn is_windows() -> Bool {
  true
}

///|
#cfg(not(platform="windows"))
pub fn is_windows() -> Bool {
  false
}
