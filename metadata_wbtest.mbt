///|
test "class constant pool decodes typed values without shifting following sections" {
  let width = 8
  // One object constant and one signed long, followed by empty static/field tables.
  let header = be(100UL, width) +
    be(7UL, 4) +
    Bytes::make(width * 6, 0) +
    be(24UL, 4)
  let constants = be(2UL, 2) +
    be(3UL, 2) +
    be(2UL, 1) +
    be(200UL, width) +
    be(9UL, 2) +
    be(11UL, 1) +
    be(0xffffffffffffffffUL, 8)
  let bytes = be(0x20UL, 1) + header + constants + be(0UL, 2) + be(0UL, 2)
  let heap = parse(wrap_heap(bytes, width))
  let cls = heap.class_info(100UL).unwrap()
  assert_eq(cls.stack_serial, 7UL)
  assert_eq(cls.instance_size, 24)
  assert_eq(cls.constants.length(), 2)
  assert_eq(cls.constants[0].index, 3)
  assert_true(cls.constants[0].value is Reference(200UL))
  assert_true(cls.constants[1].value is LongValue(-1L))
  assert_eq(cls.fields.length(), 0)
  assert_eq(cls.statics.length(), 0)
}

///|
test "high-bit object IDs retain unsigned identity in indexes and JSON" {
  let id = 0xf000000000000123UL
  let cls = 0xf000000000000100UL
  let records = string_record(1UL, "pkg/High", 8) + load_record(1, cls, 1UL, 8)
  let bytes = class_record(cls, 0UL, 8, [], []) +
    instance_record(id, cls, b"", 8)
  let heap = parse(wrap_heap(bytes, 8, records~))
  heap.validate()
  assert_eq(heap.object(id).unwrap().class_id, cls)
  assert_eq(heap.object_ids(class_id=cls), [id])
  assert_true(
    heap.object_json(id) is Object(fields) &&
    fields.get("id") == Some(Json::string(id.to_string())),
  )
}

///|
test "native stack frame line markers remain signed and trace frame order is preserved" {
  let width = 4
  let names = string_record(1UL, "nativeMethod", width) +
    string_record(2UL, "()I", width) +
    string_record(3UL, "Native.java", width)
  let frame = be(900UL, width) +
    be(1UL, width) +
    be(2UL, width) +
    be(3UL, width) +
    be(1UL, 4) +
    be(0xfffffffdUL, 4)
  let trace = be(7UL, 4) +
    be(1UL, 4) +
    be(2UL, 4) +
    be(900UL, width) +
    be(900UL, width)
  let heap = parse(
    wrap_heap(b"", width, records=names + record(4, frame) + record(5, trace)),
  )
  let frames = heap.stack_trace(7UL)
  assert_eq(frames.length(), 2)
  assert_eq(frames[0].line_number, -3)
  assert_eq(frames[1].id, 900UL)
  assert_eq(frames[0].readable_signature(), "nativeMethod() -> int")
}

///|
test "metadata record boundaries reject duplicate frames and oversized trace counts" {
  let frame = be(900UL, 8) + Bytes::make(8 * 3 + 8, 0)
  must_reject(wrap_heap(b"", 8, records=record(4, frame) + record(4, frame)))
  must_reject(wrap_heap(b"", 8, records=record(4, frame + b"x")))
  let trace = be(7UL, 4) + be(1UL, 4) + be(100UL, 4)
  must_reject(wrap_heap(b"", 8, records=record(5, trace)))
  let missing = be(7UL, 4) + be(1UL, 4) + be(1UL, 4) + be(999UL, 8)
  let heap = parse(wrap_heap(b"", 8, records=record(5, missing)))
  try heap.validate() catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("unresolved frame was ignored")
  }
}
