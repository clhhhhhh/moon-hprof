///|
fn descending_chain_dump(width : Int) -> Bytes {
  let records = string_record(1UL, "Node", width) +
    string_record(2UL, "next", width) +
    load_record(1, 10UL, 1UL, width)
  let mut body = class_record(10UL, 0UL, width, [(2UL, 2)], [])
  body += instance_record(300UL, 10UL, be(200UL, width), width)
  body += instance_record(200UL, 10UL, be(100UL, width), width)
  body += instance_record(100UL, 10UL, be(0UL, width), width)
  body += be(0xffUL, 1) + be(300UL, width)
  wrap_heap(body, width, records~)
}

///|
fn weak_reference_dump(width : Int) -> Bytes {
  let records = string_record(1UL, "java/lang/ref/Reference", width) +
    string_record(2UL, "referent", width) +
    string_record(3UL, "Target", width) +
    load_record(1, 10UL, 1UL, width) +
    load_record(2, 11UL, 3UL, width)
  let mut body = class_record(10UL, 0UL, width, [(2UL, 2)], [])
  body += class_record(11UL, 0UL, width, [], [])
  body += instance_record(300UL, 10UL, be(200UL, width), width)
  body += instance_record(200UL, 11UL, b"", width)
  body += be(0xffUL, 1) + be(300UL, width)
  wrap_heap(body, width, records~)
}

///|
fn diamond_dump(width : Int) -> Bytes {
  let records = string_record(1UL, "Node", width) +
    string_record(2UL, "left", width) +
    string_record(3UL, "right", width) +
    string_record(4UL, "next", width) +
    load_record(1, 10UL, 1UL, width)
  let mut body = class_record(
    10UL,
    0UL,
    width,
    [(2UL, 2), (3UL, 2), (4UL, 2)],
    [],
  )
  body += instance_record(
    300UL,
    10UL,
    be(200UL, width) + be(150UL, width) + be(0UL, width),
    width,
  )
  body += instance_record(
    200UL,
    10UL,
    be(100UL, width) + be(0UL, width) + be(0UL, width),
    width,
  )
  body += instance_record(
    150UL,
    10UL,
    be(0UL, width) + be(0UL, width) + be(100UL, width),
    width,
  )
  body += instance_record(
    100UL,
    10UL,
    be(0UL, width) + be(0UL, width) + be(0UL, width),
    width,
  )
  body += be(0xffUL, 1) + be(300UL, width)
  wrap_heap(body, width, records~)
}

///|
test "gc analysis computes dominators and retained payload independent of ID order" {
  let heap = parse(descending_chain_dump(8))
  let analysis = heap.gc_analysis()
  assert_true(analysis.is_reachable(300UL))
  assert_true(analysis.is_reachable(200UL))
  assert_true(analysis.is_reachable(100UL))
  assert_eq(analysis.dominator_of(200UL), Some(300UL))
  assert_eq(analysis.dominator_of(100UL), Some(200UL))
  assert_eq(analysis.retained_payload(300UL), 24L)
  assert_eq(analysis.retained_payload(200UL), 16L)
  assert_eq(analysis.retained_payload(100UL), 8L)
  let path = analysis.root_path(100UL)
  assert_eq(path.root_id, 300UL)
  assert_eq(path.edges.map(edge => edge.source_id), [300UL, 200UL])
  assert_true(
    execute(heap, ["gc", "--limit", "3"]).contains("retained_payload_bytes"),
  )
  assert_true(execute(heap, ["root-path", "100"]).contains("root_id"))
}

///|
test "gc reachability excludes the Reference.referent edge" {
  let heap = parse(weak_reference_dump(8))
  assert_eq(heap.class_name(10UL), Some("java/lang/ref/Reference"))
  assert_eq(ReferenceIndex::build(heap).incoming(200UL)[0].label, "10:referent")
  let analysis = heap.gc_analysis()
  assert_true(analysis.is_reachable(300UL))
  assert_true(!analysis.is_reachable(200UL))
  try analysis.root_path(200UL) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("weak referent unexpectedly had a strong GC-root path")
  }
}

///|
test "gc analysis finds the common dominator of a diamond" {
  let analysis = parse(diamond_dump(8)).gc_analysis()
  assert_eq(analysis.dominator_of(200UL), Some(300UL))
  assert_eq(analysis.dominator_of(150UL), Some(300UL))
  assert_eq(analysis.dominator_of(100UL), Some(300UL))
  assert_eq(analysis.retained_payload(300UL), 96L)
  assert_eq(analysis.retained_payload(200UL), 24L)
}

///|
test "multiple GC roots share only the synthetic dominator" {
  let analysis = parse(sample_dump(8)).gc_analysis()
  assert_true(analysis.is_reachable(201UL))
  assert_eq(analysis.dominator_of(201UL), None)
}
