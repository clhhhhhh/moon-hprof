///|
test "loader totals keep primitive arrays separate from application class instances" {
  let heap = parse(sample_dump(8))
  let rows = heap.loader_statistics()
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].loader_id, 0UL)
  assert_eq(rows[0].array_count, 2)
  assert_eq(rows[0].class_count, 0)
  assert_eq(rows[0].payload_bytes, 7L)
  assert_eq(rows[1].loader_id, 55UL)
  assert_eq(rows[1].class_count, 3)
  assert_eq(rows[1].instance_count, 2)
  assert_eq(rows[1].array_count, 1)
  assert_eq(
    rows.fold(init=0L, (sum, row) => sum + row.payload_bytes),
    heap.totals().payload_bytes,
  )
}

///|
test "empty dumps have no synthetic class-loader statistics" {
  assert_eq(parse(empty_dump(4)).loader_statistics().length(), 0)
}

///|
test "class-only dumps report loader metadata without invented objects" {
  let heap = parse(
    wrap_heap(
      class_record(100UL, 0UL, 8, [], []) + class_record(101UL, 0UL, 8, [], []),
      8,
    ),
  )
  let rows = heap.loader_statistics()
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].class_count, 2)
  assert_eq(rows[0].instance_count, 0)
  assert_eq(rows[0].payload_bytes, 0L)
  assert_true(
    rows[0].to_json() is Object(fields) &&
    fields.get("loader_id") == Some(Json::string("55")),
  )
}
