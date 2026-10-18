///|
/// Checks semantic fixture expectations after independent record-count comparison.
fn main {
  @async.run_async_main(() => {
    let args = @env.args()
    if args.length() != 2 {
      fail("usage: moon run cmd/verify -- <generated.hprof>")
    }
    let heap = @lib.parse(@fs.read_file(args[1]).binary())
    heap.validate()
    let markers = heap.find_classes("GenerateHeap$Marker")
    assert_eq(markers.length(), 1)
    let ids = heap.object_ids(class_id=markers[0], limit=100)
    assert_eq(ids.length(), 37)
    let seen : Map[Int, Bool] = Map([])
    for id in ids {
      let fields = heap.instance_fields(id)
      let sequence = match
        fields.filter(field => field.name == "sequence")[0].value {
        IntValue(n) => n
        _ => fail("wrong sequence value type")
      }
      assert_true(sequence >= 0 && sequence < 37)
      assert_true(!seen.contains(sequence))
      seen[sequence] = true
      assert_true(heap.field(id, "inherited") is Some(LongValue(-9000000000L)))
      let payload = match heap.field(id, "payload") {
        Some(Reference(id)) => id
        _ => fail("missing payload reference")
      }
      let array = heap.object(payload).unwrap()
      assert_eq(array.length, sequence + 1)
      let values = heap.array_values(payload)
      assert_eq(values.length(), sequence + 1)
      for value in values {
        assert_true(value is ByteValue(0))
      }
    }
    let owner = heap.find_classes("GenerateHeap")
    assert_eq(owner.length(), 1)
    let text_id = match heap.field(owner[0], "TEXT") {
      Some(Reference(id)) => id
      _ => fail("missing TEXT static field")
    }
    // Validation runners are x86-64; compact UTF-16 backing bytes are native-endian.
    assert_eq(
      heap.java_string(text_id, utf16_little_endian=true),
      "A\u0000中😀",
    )
    let keep = match heap.field(owner[0], "KEEP") {
      Some(Reference(id)) => id
      _ => fail("missing KEEP static array")
    }
    let values = heap.array_values(keep)
    assert_eq(values.length(), 37)
    for i in 0..<values.length() {
      let id = values[i].reference().unwrap()
      assert_true(heap.field(id, "sequence") is Some(IntValue(n)) && n == i)
    }
    let arrays = match heap.field(owner[0], "ARRAYS") {
      Some(Reference(id)) => heap.array_values(id)
      _ => fail("missing ARRAYS static array")
    }
    assert_eq(arrays.length(), 8)
    let bools = heap.array_values(arrays[0].reference().unwrap())
    assert_true(bools[0] is Boolean(true))
    assert_true(bools[1] is Boolean(false))
    let chars = heap.array_values(arrays[1].reference().unwrap())
    assert_true(chars[1] is Character(0x4e2d))
    assert_true(chars[2] is Character(0xd83d))
    assert_true(chars[3] is Character(0xde00))
    let bytes = heap.array_values(arrays[2].reference().unwrap())
    assert_true(bytes[0] is ByteValue(-1))
    let shorts = heap.array_values(arrays[3].reference().unwrap())
    assert_true(shorts[0] is ShortValue(-300))
    let ints = heap.array_values(arrays[4].reference().unwrap())
    assert_true(ints[0] is IntValue(-2147483648))
    assert_true(ints[2] is IntValue(2147483647))
    let longs = heap.array_values(arrays[5].reference().unwrap())
    assert_true(longs[0] is LongValue(-9223372036854775808L))
    assert_true(longs[2] is LongValue(9223372036854775807L))
    let floats = heap.array_values(arrays[6].reference().unwrap())
    assert_true(floats[0] is FloatValue(1.5))
    assert_true(floats[1] is FloatValue(n) && n.is_nan())
    assert_true(floats[2] is FloatValue(n) && n.is_pos_inf())
    let doubles = heap.array_values(arrays[7].reference().unwrap())
    assert_true(doubles[0] is DoubleValue(-2.25))
    assert_true(doubles[1] is DoubleValue(n) && n.is_nan())
    assert_true(doubles[2] is DoubleValue(n) && n.is_neg_inf())
    let rows = heap.histogram()
    let expected = heap.instances + heap.object_arrays + heap.primitive_arrays
    assert_eq(rows.fold(init=0, (sum, row) => sum + row.count), expected)
    assert_eq(
      heap.totals().payload_bytes,
      rows.fold(init=0L, (sum, row) => sum + row.payload_bytes),
    )
    assert_true(heap.references(keep, limit=100).length() == 37)
    println("semantic_validation=OK")
  })
}
