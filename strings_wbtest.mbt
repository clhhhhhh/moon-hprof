///|
fn compact_string_dump(coder : Int, bytes : Bytes, width : Int) -> Bytes {
  let records = string_record(1UL, "java/lang/String", width) +
    string_record(2UL, "value", width) +
    string_record(3UL, "coder", width) +
    load_record(1, 100UL, 1UL, width)
  let heap = class_record(100UL, 0UL, width, [(2UL, 2), (3UL, 8)], []) +
    instance_record(
      200UL,
      100UL,
      be(301UL, width) + be(coder.to_uint64(), 1),
      width,
    ) +
    primitive_array_record(301UL, 8, bytes.length(), bytes, width)
  wrap_heap(heap, width, records~)
}

///|
test "compact Latin-1 Strings decode signed byte storage as unsigned characters" {
  for width in [4, 8] {
    let heap = parse(compact_string_dump(0, b"caf\xe9", width))
    assert_eq(heap.java_string(200UL, utf16_little_endian=true), "café")
    assert_eq(heap.java_string(200UL, utf16_little_endian=false), "café")
  }
}

///|
test "compact UTF-16 strings use explicit native order and combine surrogate pairs" {
  let little = parse(compact_string_dump(1, b"\x2d\x4e\x3d\xd8\x00\xde", 8))
  assert_eq(little.java_string(200UL, utf16_little_endian=true), "中😀")
  let big = parse(compact_string_dump(1, b"\x4e\x2d\xd8\x3d\xde\x00", 4))
  assert_eq(big.java_string(200UL, utf16_little_endian=false), "中😀")
}

///|
test "legacy character array String respects offset and count" {
  let width = 8
  let records = string_record(1UL, "java/lang/String", width) +
    string_record(2UL, "value", width) +
    string_record(3UL, "offset", width) +
    string_record(4UL, "count", width) +
    load_record(1, 100UL, 1UL, width)
  let cls = class_record(100UL, 0UL, width, [(2UL, 2), (3UL, 10), (4UL, 10)], [])
  let instance = instance_record(
    200UL,
    100UL,
    be(301UL, width) + be(1UL, 4) + be(2UL, 4),
    width,
  )
  let array = primitive_array_record(
    301UL, 5, 4, b"\x00x\x00A\x4e\x2d\x00y", width,
  )
  let heap = parse(wrap_heap(cls + instance + array, width, records~))
  assert_eq(heap.java_string(200UL, utf16_little_endian=true), "A中")
}

///|
test "String decoder rejects malformed coders UTF-16 and resource overflow" {
  let bad = [
    compact_string_dump(2, b"x", 8),
    compact_string_dump(1, b"x", 8),
    compact_string_dump(1, b"\x00\xd8", 8),
  ]
  for data in bad {
    let heap = parse(data)
    try heap.java_string(200UL, utf16_little_endian=true) catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("accepted invalid String representation")
    }
  }
  let heap = parse(compact_string_dump(0, b"abc", 8))
  try heap.java_string(200UL, utf16_little_endian=true, max_chars=2) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("ignored String length bound")
  }
  let other = parse(sample_dump(8))
  try other.java_string(200UL, utf16_little_endian=true) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("interpreted unrelated object as String")
  }
}
