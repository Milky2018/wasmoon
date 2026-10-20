///|
struct Instant(Int64)

///|
extern "c" fn instant_now_ffi() -> Int64 = "perf_instant_now_ffi"

///|
pub fn instant_now() -> Instant {
  Instant(instant_now_ffi())
}

///|
extern "c" fn instant_as_secs_f64_ffi(i : Int64) -> Double = "perf_instant_as_secs_f64_ffi"

///|
pub fn instant_elapsed_as_secs_f64(i : Instant) -> Double {
  let now = instant_now()
  instant_as_secs_f64_ffi(now.0) - instant_as_secs_f64_ffi(i.0)
}
