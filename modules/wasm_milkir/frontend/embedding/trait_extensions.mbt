///|
pub extend EmbeddingEnvironment with Debug::{to_repr}

///|
pub extend MemoryDescriptorLayout with Debug::{to_repr}

///|
pub extend MemoryDescriptorLayout with Eq::{not_equal, equal}

///|
pub extend RuntimeLayout with Debug::{to_repr}

///|
pub extend RuntimeLayout with Eq::{not_equal, equal}

///|
pub extend SafepointPollLayout with Debug::{to_repr}

///|
pub extend SafepointPollLayout with Eq::{not_equal, equal}
