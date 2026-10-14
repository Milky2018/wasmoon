///|
/// Embedding-visible stack-map identity and argument-root contract.
pub(all) struct StackMapMetadata {
  id : Int32
  argument_root_count : Int32
} derive(Debug, Eq)

///|
pub fn StackMapMetadata::new(
  id : Int32,
  argument_root_count~ : Int32,
) -> StackMapMetadata {
  { id, argument_root_count, }
}
