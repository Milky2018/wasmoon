///|
#external
type Instant

///|
pub extern "c" fn instant_now() -> Instant = "perf_instant_now_ffi"

///|
extern "c" fn instant_as_secs_f64_ffi(i : Instant) -> Double = "perf_instant_as_secs_f64_ffi"

///|
pub fn instant_elapsed_as_secs_f64(i : Instant) -> Double {
  let now = instant_now()
  instant_as_secs_f64_ffi(now) - instant_as_secs_f64_ffi(i)
}
