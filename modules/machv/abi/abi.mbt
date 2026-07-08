///|
/// Align value up to the next multiple of `align` (which must be a power of two).
pub fn align_up(value : Int, align : Int) -> Int {
  if align <= 1 {
    value
  } else {
    (value + (align - 1)) / align * align
  }
}
