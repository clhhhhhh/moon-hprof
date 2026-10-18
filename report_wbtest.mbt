///|
test "histogram sort modes are deterministic and have stable tie breaks" {
  let heap = parse(sample_dump(8))
  let names = heap.select_histogram(sort=Name).map(row => row.name)
  let expected = names.copy()
  expected.sort()
  assert_eq(names, expected)
  let sizes = heap.select_histogram(sort=Payload).map(row => row.payload_bytes)
  for i in 1..<sizes.length() {
    assert_true(sizes[i - 1] >= sizes[i])
  }
  let elements = heap.select_histogram(sort=Elements).map(row => row.elements)
  for i in 1..<elements.length() {
    assert_true(elements[i - 1] >= elements[i])
  }
}

///|
test "totals and largest objects agree with indexed payloads" {
  let heap = parse(sample_dump(8))
  let totals = heap.totals()
  assert_eq(totals.class_objects, 3)
  assert_eq(totals.instance_objects, 2)
  assert_eq(totals.array_objects, 3)
  assert_eq(totals.array_elements, 8L)
  assert_eq(
    totals.payload_bytes,
    heap.histogram().fold(init=0L, (sum, row) => sum + row.payload_bytes),
  )
  assert_eq(totals.largest_payload_id, 200UL)
  assert_eq(heap.largest_objects(limit=1)[0].id, totals.largest_payload_id)
  assert_eq(heap.largest_objects(limit=0).length(), 0)
}

///|
test "empty heap totals have no invented largest object" {
  let totals = parse(empty_dump(8)).totals()
  assert_eq(totals.largest_payload_id, 0UL)
  assert_eq(totals.largest_payload_bytes, 0)
  assert_eq(totals.payload_bytes, 0L)
}

///|
test "heap comparison uses class names and distinguishes additions removals and identity" {
  let full = parse(sample_dump(8))
  let empty = parse(empty_dump(8))
  let additions = compare_heaps(empty, full)
  assert_eq(additions.fold(init=0L, (sum, row) => sum + row.count_delta), 5L)
  let removals = compare_heaps(full, empty)
  assert_eq(removals.fold(init=0L, (sum, row) => sum + row.count_delta), -5L)
  for row in compare_heaps(full, full) {
    assert_eq(row.count_delta, 0L)
    assert_eq(row.payload_delta, 0L)
  }
  assert_eq(compare_heaps(empty, empty).length(), 0)
}
