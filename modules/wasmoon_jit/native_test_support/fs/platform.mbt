///|
extern "c" fn c_is_windows() -> Bool = "wasmoon_test_fs_is_windows"

///|
extern "c" fn c_temp_dir() -> Bytes = "wasmoon_test_fs_temp_dir"

///|
/// Return the platform's absolute temporary directory for native test fixtures.
pub fn temp_dir() -> String {
  let bytes = c_temp_dir()
  if bytes.is_empty() {
    abort("Could not determine native test temporary directory")
  }
  @utf8.decode_lossy(bytes)
}

///|
/// Return the host null device without adding a runtime path alias.
pub fn null_device() -> String {
  if c_is_windows() {
    "NUL"
  } else {
    "/dev/null"
  }
}
