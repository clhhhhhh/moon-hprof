///|
test "default and explicitly bounded parsers agree" {
  let data = sample_dump(8)
  let limits = ParseLimits::new(
    max_file_bytes=data.length(),
    max_objects=5,
    max_classes=3,
    max_strings=18,
    max_roots=2,
    max_records=26,
    max_trace_frames=1,
  )
  let heap = parse_with_limits(data, limits)
  heap.validate()
  assert_eq(heap.object_count(), parse(data).object_count())
  assert_eq(heap.file_size(), data.length())
}

///|
test "each indexing resource limit rejects before unbounded growth" {
  let data = sample_dump(8)
  let limits = [
    ParseLimits::new(max_file_bytes=data.length() - 1),
    ParseLimits::new(max_objects=4),
    ParseLimits::new(max_classes=2),
    ParseLimits::new(max_strings=17),
    ParseLimits::new(max_text_bytes=2),
    ParseLimits::new(max_roots=1),
    ParseLimits::new(max_records=1),
    ParseLimits::new(max_trace_frames=0),
  ]
  for limit in limits {
    try parse_with_limits(data, limit) catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("accepted exhausted resource limit")
    }
  }
}

///|
test "negative limits are rejected at construction" {
  let constructors : Array[() -> ParseLimits raise ParseError] = [
    () => ParseLimits::new(max_file_bytes=30),
    () => ParseLimits::new(max_objects=-1),
    () => ParseLimits::new(max_classes=-1),
    () => ParseLimits::new(max_strings=-1),
    () => ParseLimits::new(max_text_bytes=-1),
    () => ParseLimits::new(max_roots=-1),
    () => ParseLimits::new(max_records=-1),
    () => ParseLimits::new(max_trace_frames=-1),
  ]
  for construct in constructors {
    try construct() catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("accepted invalid limits")
    }
  }
}

///|
test "zero object class string and root limits still allow an empty dump" {
  let limits = ParseLimits::new(
    max_objects=0,
    max_classes=0,
    max_strings=0,
    max_roots=0,
    max_records=2,
  )
  let heap = parse_with_limits(empty_dump(4), limits)
  heap.validate()
  assert_eq(heap.object_count(), 0)
}

///|
test "payload pages never include record metadata or adjacent objects" {
  let heap = parse(sample_dump(8))
  assert_eq(heap.payload(301UL), b"\xff\x00\x07")
  assert_eq(heap.payload(301UL, offset=1, limit=1), b"\x00")
  assert_eq(heap.payload(301UL, offset=3), b"")
  try heap.payload(301UL, offset=4) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("read past payload")
  }
}

///|
test "field lookup respects declaring class and missing field semantics" {
  let heap = parse(sample_dump(4))
  assert_true(heap.field(200UL, "base") is Some(IntValue(-99)))
  assert_true(
    heap.field(200UL, "count", declaring_class=101UL) is Some(IntValue(42)),
  )
  assert_true(heap.field(200UL, "count", declaring_class=100UL) is None)
  assert_true(heap.field(200UL, "missing") is None)
  assert_true(heap.field(101UL, "staticRef") is Some(Reference(201UL)))
  assert_eq(
    heap.instance_payload_size(101UL),
    heap.object(200UL).unwrap().payload_bytes,
  )
}

///|
test "root and trace lookup helpers preserve ordering" {
  let heap = parse(sample_dump(8))
  assert_eq(heap.root_kinds().get("sticky_class"), Some(1))
  assert_eq(heap.roots_for(200UL).length(), 1)
  assert_eq(heap.roots_for(999UL).length(), 0)
  assert_eq(heap.thread_serials(), [9UL])
  assert_eq(heap.trace_serials(), [7UL])
}
