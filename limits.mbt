///|
/// Limits bound indexing allocations. The caller still owns the input buffer.
pub struct ParseLimits {
  max_file_bytes : Int
  max_objects : Int
  max_classes : Int
  max_strings : Int
  max_text_bytes : Int
  max_roots : Int
  max_records : Int
  max_trace_frames : Int
}

///|
pub fn ParseLimits::new(
  max_file_bytes? : Int = 536_870_912,
  max_objects? : Int = 2_000_000,
  max_classes? : Int = 200_000,
  max_strings? : Int = 2_000_000,
  max_text_bytes? : Int = 1_048_576,
  max_roots? : Int = 4_000_000,
  max_records? : Int = 8_000_000,
  max_trace_frames? : Int = 100_000,
) -> ParseLimits raise ParseError {
  let limits = {
    max_file_bytes,
    max_objects,
    max_classes,
    max_strings,
    max_text_bytes,
    max_roots,
    max_records,
    max_trace_frames,
  }
  limits.validate()
  limits
}

///|
pub fn ParseLimits::validate(self : ParseLimits) -> Unit raise ParseError {
  if self.max_file_bytes < 31 ||
    self.max_objects < 0 ||
    self.max_classes < 0 ||
    self.max_strings < 0 ||
    self.max_text_bytes < 0 ||
    self.max_roots < 0 ||
    self.max_records < 0 ||
    self.max_trace_frames < 0 {
    raise Invalid(0, "parse limits must be non-negative and allow a header")
  }
}

///|
fn check_limit(
  offset : Int,
  name : String,
  count : Int,
  maximum : Int,
) -> Unit raise ParseError {
  if count >= maximum {
    raise Invalid(offset, "resource limit exceeded: \{name}")
  }
}

///|
/// Parses and indexes a dump using explicit caller-specified resource limits.
pub fn parse_with_limits(
  data : Bytes,
  limits : ParseLimits,
) -> Summary raise ParseError {
  parse(data, limits~)
}
