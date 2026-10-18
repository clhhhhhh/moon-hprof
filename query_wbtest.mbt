///|
test "both identifier widths preserve indexes and summary counts" {
  for width in [4, 8] {
    let heap = parse(sample_dump(width))
    assert_eq(heap.id_size, width)
    assert_eq(heap.timestamp_ms, 123456789UL)
    assert_eq(heap.classes, 3)
    assert_eq(heap.instances, 2)
    assert_eq(heap.object_arrays, 1)
    assert_eq(heap.primitive_arrays, 2)
    assert_eq(heap.object_count(), 8)
    assert_eq(heap.class_name(101UL), Some("pkg/Child"))
    assert_eq(heap.count_class("pkg/Base"), 1)
    assert_eq(heap.find_classes("pkg/Child"), [101UL])
    assert_eq(heap.object_ids(), [200UL, 201UL, 300UL, 301UL, 302UL])
  }
}

///|
test "field decoding follows subclass then superclass and preserves numeric types" {
  for width in [4, 8] {
    let heap = parse(sample_dump(width))
    let fields = heap.instance_fields(200UL)
    assert_eq(fields.length(), 10)
    assert_true(fields[0].value is IntValue(42))
    assert_true(fields[1].value is Reference(201UL))
    assert_true(fields[2].value is Boolean(true))
    assert_true(fields[3].value is Character(0x4e2d))
    assert_true(fields[4].value is ByteValue(-7))
    assert_true(fields[5].value is ShortValue(-300))
    assert_true(fields[6].value is LongValue(-9000000000L))
    assert_true(fields[7].value is FloatValue(1.5))
    assert_true(fields[8].value is DoubleValue(-2.25))
    assert_true(fields[9].value is IntValue(-99))
    assert_eq(fields[9].declaring_class_id, 100UL)
    assert_eq(fields[9].name, "base")
    assert_eq(heap.hierarchy(101UL).map(cls => cls.id), [101UL, 100UL])
  }
}

///|
test "static fields and array paging decode without expanding entire arrays" {
  let heap = parse(sample_dump(8))
  assert_true(heap.static_fields(101UL)[0].value is Reference(201UL))
  let values = heap.array_values(300UL, offset=1, limit=2)
  assert_eq(values.length(), 2)
  assert_true(values[0] is Reference(0UL))
  assert_true(values[1] is Reference(201UL))
  assert_true(heap.array_values(301UL)[0] is ByteValue(-1))
  assert_true(heap.array_values(302UL)[1] is Character(0x4e2d))
  assert_eq(heap.array_values(300UL, offset=3).length(), 0)
  assert_eq(heap.array_values(300UL, limit=0).length(), 0)
}

///|
test "references omit null targets and preserve source labels" {
  let heap = parse(sample_dump(4))
  let edges = heap.references(200UL)
  assert_eq(edges.length(), 1)
  assert_eq(edges[0].label, "ref")
  assert_eq(edges[0].target_id, 201UL)
  assert_eq(heap.references(101UL)[0].label, "staticRef")
  let arrays = heap.references(300UL)
  assert_eq(arrays.map(edge => edge.target_id), [200UL, 201UL])
  assert_eq(heap.references(300UL, limit=1).length(), 1)
  assert_eq(heap.references(301UL).length(), 0)
}

///|
test "root and stack metadata resolve against string and class tables" {
  let heap = parse(sample_dump(8))
  assert_eq(heap.root_count(), 2)
  assert_eq(heap.roots()[0].label(), "sticky_class")
  assert_eq(heap.roots()[1].thread_serial, 9UL)
  let frames = heap.stack_trace(7UL)
  assert_eq(frames.length(), 1)
  assert_eq(frames[0].class_name, "pkg/Child")
  assert_eq(frames[0].method_name, "run")
  assert_eq(frames[0].line_number, 123)
  assert_eq(heap.thread(9UL).map(info => info.name_id), Some(18UL))
}

///|
test "histogram totals count payload bytes rather than JVM memory size" {
  let heap = parse(sample_dump(8))
  let rows = heap.histogram()
  assert_eq(rows.fold(init=0, (sum, row) => sum + row.count), 5)
  assert_eq(rows.fold(init=0L, (sum, row) => sum + row.elements), 8L)
  assert_eq(rows.filter(row => row.name == "byte[]")[0].payload_bytes, 3L)
  assert_eq(rows.filter(row => row.name == "pkg/Child")[0].loader_id, 55UL)
  assert_eq(heap.record_count(1), 18)
}

///|
test "queries reject missing objects inappropriate kinds and invalid pages" {
  let heap = parse(sample_dump(8))
  let operations : Array[() -> Unit raise ParseError] = [
    () => ignore(heap.instance_fields(999UL)),
    () => ignore(heap.instance_fields(300UL)),
    () => ignore(heap.array_values(200UL)),
    () => ignore(heap.array_values(300UL, offset=-1)),
    () => ignore(heap.array_values(300UL, offset=4)),
    () => ignore(heap.array_values(300UL, limit=100001)),
    () => ignore(heap.references(200UL, limit=-1)),
    () => ignore(heap.hierarchy(999UL)),
    () => ignore(heap.stack_trace(999UL)),
  ]
  for operation in operations {
    try operation() catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("accepted invalid query")
    }
  }
}
