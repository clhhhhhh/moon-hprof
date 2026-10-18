///|
test "same class names retain class identity but aggregate in name-based counts" {
  let records = string_record(1UL, "pkg/Shared", 8) +
    load_record(1, 100UL, 1UL, 8) +
    load_record(2, 101UL, 1UL, 8)
  let bytes = class_record(100UL, 0UL, 8, [], []) +
    class_record(101UL, 0UL, 8, [], []) +
    instance_record(200UL, 100UL, b"", 8) +
    instance_record(201UL, 101UL, b"", 8)
  let heap = parse(wrap_heap(bytes, 8, records~))
  heap.validate()
  assert_eq(heap.find_classes("pkg/Shared"), [100UL, 101UL])
  assert_eq(heap.count_class("pkg/Shared"), 2)
  assert_eq(heap.object_ids(class_id=100UL), [200UL])
  assert_eq(heap.object_ids(class_id=101UL), [201UL])
  let rows = heap.histogram()
  assert_eq(rows.length(), 2)
  assert_eq(rows.map(row => row.class_id), [100UL, 101UL])
  let comparison = compare_heaps(parse(empty_dump(8)), heap)
  assert_eq(comparison.length(), 1)
  assert_eq(comparison[0].count_delta, 2L)
}

///|
test "metadata after heap completion can resolve names already indexed by ID" {
  let bytes = class_record(100UL, 0UL, 4, [], []) +
    instance_record(200UL, 100UL, b"", 4)
  let trailing = string_record(1UL, "pkg/Late", 4) +
    load_record(1, 100UL, 1UL, 4)
  let heap = parse(wrap_heap(bytes, 4) + trailing)
  heap.validate()
  assert_eq(heap.class_name(100UL), Some("pkg/Late"))
  assert_eq(heap.count_class("pkg/Late"), 1)
}

///|
test "subclasses can precede superclass definitions without corrupting field order" {
  let records = string_record(1UL, "base", 8) + string_record(2UL, "child", 8)
  let classes = class_record(101UL, 100UL, 8, [(2UL, 10)], []) +
    class_record(100UL, 0UL, 8, [(1UL, 10)], [])
  let object = instance_record(200UL, 101UL, be(42UL, 4) + be(99UL, 4), 8)
  let heap = parse(wrap_heap(classes + object, 8, records~))
  let fields = heap.instance_fields(200UL)
  assert_eq(fields.map(field => field.name), ["child", "base"])
  assert_true(fields[0].value is IntValue(42))
  assert_true(fields[1].value is IntValue(99))
}

///|
test "object discovery pages have numeric unsigned ordering and no overlaps" {
  let heap = parse(sample_dump(8))
  let first = heap.object_ids(limit=2)
  let second = heap.object_ids(offset=2, limit=2)
  let last = heap.object_ids(offset=4, limit=2)
  assert_eq(first, [200UL, 201UL])
  assert_eq(second, [300UL, 301UL])
  assert_eq(last, [302UL])
  assert_eq(heap.object_ids(offset=5), [])
  assert_true(heap.contains_object(101UL))
  assert_true(heap.contains_object(200UL))
  assert_true(!heap.contains_object(0UL))
}
