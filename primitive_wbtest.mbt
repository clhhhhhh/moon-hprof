///|
test "all 256 byte bit patterns decode with Java signed-byte semantics" {
  let payload = Bytes::makei(256, i => i.to_byte())
  for width in [4, 8] {
    let heap = parse(
      wrap_heap(primitive_array_record(200UL, 8, 256, payload, width), width),
    )
    let first = heap.array_values(200UL, limit=128)
    let second = heap.array_values(200UL, offset=128, limit=128)
    for i in 0..<128 {
      assert_true(first[i] is ByteValue(value) && value == i)
      assert_true(second[i] is ByteValue(value) && value == i - 128)
    }
    assert_eq(heap.payload(200UL, offset=255, limit=1), b"\xff")
    heap.validate()
  }
}

///|
test "signed short int and long extrema survive big endian decoding" {
  let cases = [
    (9, b"\x80\x00\xff\xff\x00\x00\x7f\xff"),
    (10, b"\x80\x00\x00\x00\xff\xff\xff\xff\x00\x00\x00\x00\x7f\xff\xff\xff"),
    (
      11,
      be(0x8000000000000000UL, 8) +
      be(0xffffffffffffffffUL, 8) +
      be(0UL, 8) +
      be(0x7fffffffffffffffUL, 8),
    ),
  ]
  for entry in cases {
    let heap = parse(
      wrap_heap(primitive_array_record(200UL, entry.0, 4, entry.1, 8), 8),
    )
    let values = heap.array_values(200UL)
    match entry.0 {
      9 => {
        assert_true(values[0] is ShortValue(-32768))
        assert_true(values[1] is ShortValue(-1))
        assert_true(values[2] is ShortValue(0))
        assert_true(values[3] is ShortValue(32767))
      }
      10 => {
        assert_true(values[0] is IntValue(-2147483648))
        assert_true(values[1] is IntValue(-1))
        assert_true(values[2] is IntValue(0))
        assert_true(values[3] is IntValue(2147483647))
      }
      _ => {
        assert_true(values[0] is LongValue(-9223372036854775808L))
        assert_true(values[1] is LongValue(-1L))
        assert_true(values[2] is LongValue(0L))
        assert_true(values[3] is LongValue(9223372036854775807L))
      }
    }
  }
}

///|
test "IEEE negative zero infinity NaN and subnormal values preserve their bits" {
  let single = b"\x80\x00\x00\x00\x7f\x80\x00\x00\xff\x80\x00\x00\x7f\xc0\x00\x01\x00\x00\x00\x01"
  let doubles = be(0x8000000000000000UL, 8) +
    be(0x7ff0000000000000UL, 8) +
    be(0xfff0000000000000UL, 8) +
    be(0x7ff8000000000001UL, 8) +
    be(1UL, 8)
  let data = primitive_array_record(200UL, 6, 5, single, 4) +
    primitive_array_record(201UL, 7, 5, doubles, 4)
  let heap = parse(wrap_heap(data, 4))
  let floats = heap.array_values(200UL)
  assert_true(floats[0] is FloatValue(n) && (1.0 / n).is_neg_inf())
  assert_true(floats[1] is FloatValue(n) && n.is_pos_inf())
  assert_true(floats[2] is FloatValue(n) && n.is_neg_inf())
  assert_true(floats[3] is FloatValue(n) && n.is_nan())
  assert_true(floats[4] is FloatValue(n) && n > 0 && n < 1.0e-40)
  let values = heap.array_values(201UL)
  assert_true(values[0] is DoubleValue(n) && (1.0 / n).is_neg_inf())
  assert_true(values[1] is DoubleValue(n) && n.is_pos_inf())
  assert_true(values[2] is DoubleValue(n) && n.is_neg_inf())
  assert_true(values[3] is DoubleValue(n) && n.is_nan())
  assert_true(values[4] is DoubleValue(n) && n > 0 && n < 1.0e-300)
}

///|
test "paged multi-byte arrays align to elements rather than arbitrary byte offsets" {
  let payload = be(0x0102030405060708UL, 8) + be(42UL, 8) + be(99UL, 8)
  for width in [4, 8] {
    let heap = parse(
      wrap_heap(primitive_array_record(200UL, 11, 3, payload, width), width),
    )
    assert_true(
      heap.array_values(200UL, offset=1, limit=1)[0] is LongValue(42L),
    )
    assert_true(
      heap.array_values(200UL, offset=2, limit=100)[0] is LongValue(99L),
    )
    assert_eq(heap.payload(200UL, offset=1, limit=3), b"\x02\x03\x04")
  }
}

///|
test "char array API preserves code units without falsely interpreting surrogate entries" {
  let payload = b"\x00\x00\xff\xff\xd8\x00\xdc\x00"
  let heap = parse(
    wrap_heap(primitive_array_record(200UL, 5, 4, payload, 8), 8),
  )
  let values = heap.array_values(200UL)
  assert_true(values[0] is Character(0))
  assert_true(values[1] is Character(65535))
  assert_true(values[2] is Character(0xd800))
  assert_true(values[3] is Character(0xdc00))
  // Raw char arrays can contain isolated code units; only String decoding rejects them.
  heap.validate()
}
