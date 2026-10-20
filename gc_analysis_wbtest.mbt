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
  assert_true(
    execute(heap, ["gc", "--limit", "3"]).contains("retained_payload_bytes"),
  )
}
