///|
/// Embedding-visible stack-map identity and argument-root contract.
pub(all) struct StackMapMetadata {
  id : Int
  argument_root_count : Int
} derive(Debug, Eq)

///|
pub fn StackMapMetadata::new(
  id : Int,
  argument_root_count~ : Int,
) -> StackMapMetadata {
  { id, argument_root_count, }
}
