///|
pub impl @runtime.SegmentDropBinding for NativeJITContext with fn bind_segment_drop_flags(
  self,
  data,
  elements,
) {
  NativeJITContext::bind_segment_drop_flags(self, data, elements)
}
