///|
test "JSON object IDs and long values are lossless decimal strings" {
  let id = 18446744073709551615UL
  let value = Value::Reference(id).to_json()
  assert_eq(
    value,
    Json::object({
      "type": Json::string("object"),
      "value": Json::string(id.to_string()),
    }),
  )
  let long = Value::LongValue(-9223372036854775808L).to_json()
  assert_eq(
    long,
    Json::object({
      "type": Json::string("long"),
      "value": Json::string("-9223372036854775808"),
    }),
  )
}

///|
test "nonfinite floating values have valid JSON encodings" {
  let positive = 0x7ff0000000000000UL.reinterpret_as_double()
  let negative = 0xfff0000000000000UL.reinterpret_as_double()
  let nan = 0x7ff8000000000001UL.reinterpret_as_double()
  for pair in [(positive, "Infinity"), (negative, "-Infinity"), (nan, "NaN")] {
    assert_eq(
      Value::DoubleValue(pair.0).to_json(),
      Json::object({
        "type": Json::string("double"),
        "value": Json::string(pair.1),
      }),
    )
  }
}

///|
test "CSV cells quote delimiters quotes CR and LF" {
  assert_eq(csv_cell("plain"), "plain")
  assert_eq(csv_cell(""), "")
  assert_eq(csv_cell("a,b"), "\"a,b\"")
  assert_eq(csv_cell("a\"b"), "\"a\"\"b\"")
  assert_eq(csv_cell("a\nb"), "\"a\nb\"")
  assert_eq(csv_cell("a\rb"), "\"a\rb\"")
}

///|
test "histogram JSON and CSV describe the same stable rows" {
  let heap = parse(sample_dump(8))
  let rows = heap.histogram()
  assert_eq(heap.histogram_json(), Json::array(rows.map(row => row.to_json())))
  let csv = heap.histogram_csv()
  assert_true(
    csv.has_prefix(
      "name,class_id,loader_id,kind,count,payload_bytes,elements\r\n",
    ),
  )
  assert_true(csv.contains("byte[],0,0,primitive_array,1,3,3\r\n"))
  assert_true(csv.contains("pkg/Base,100,55,instance,1,4,0\r\n"))
}

///|
test "object export preserves typed fields and array page metadata" {
  let heap = parse(sample_dump(4))
  assert_true(
    heap.object_json(200UL) is Object(fields) && fields.contains("fields"),
  )
  assert_true(
    heap.object_json(300UL, offset=1, limit=1) is Object(fields) &&
    fields.get("length") == Some(Json::number(3)) &&
    fields.get("offset") == Some(Json::number(1)) &&
    fields.get("values") == Some(Json::array([Value::Reference(0UL).to_json()])),
  )
  assert_true(
    heap.class_json(101UL) is Object(fields) &&
    fields.get("superclass_id") == Some(Json::string("100")),
  )
}

///|
test "class display names expand valid JVM array descriptors" {
  let cases = [
    ("java/lang/String", "java.lang.String"),
    ("[[I", "int[][]"),
    ("[Z", "boolean[]"),
    ("[B", "byte[]"),
    ("[C", "char[]"),
    ("[S", "short[]"),
    ("[J", "long[]"),
    ("[F", "float[]"),
    ("[D", "double[]"),
    ("[[Ljava/lang/String;", "java.lang.String[][]"),
    ("[Q", "[Q"),
    ("[", "["),
    ("[Lbad", "[Lbad"),
  ]
  for entry in cases {
    assert_eq(display_class_name(entry.0), entry.1)
  }
}

///|
test "modified UTF-8 preserves NUL CJK and supplementary characters" {
  for
    text in [
      "", "ASCII", "\u0000", "中文", "日本語", "😀", "A\u0000中😀",
    ] {
    assert_eq(decode_hprof_text(encode_hprof_text(text)), text)
  }
  assert_eq(encode_hprof_text("\u0000"), b"\xc0\x80")
  assert_eq(decode_hprof_text(b"\xed\xa0\xbd\xed\xb8\x80"), "😀")
  assert_eq(decode_hprof_text(b"\xf0\x9f\x98\x80"), "😀")
}

///|
test "malformed modified UTF-8 is rejected without replacement characters" {
  for
    bytes in [
      b"\x80", b"\xff", b"\xc1\x81", b"\xe0\x80\x81", b"\xc2", b"\xc2x", b"\xf0\x80\x80\x80",
      b"\xf4\x90\x80\x80", b"\xed\xa0\x80", b"\xed\xb0\x80", b"\xed\xa0\x80x",
    ] {
    try decode_hprof_text(bytes) catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("accepted malformed Unicode")
    }
  }
}

///|
test "Unicode names survive the real string-table parsing path" {
  let records = string_record(1UL, "包/类😀", 8) +
    load_record(1, 100UL, 1UL, 8)
  let heap = parse(wrap_heap(class_record(100UL, 0UL, 8, [], []), 8, records~))
  assert_eq(heap.class_name(100UL), Some("包/类😀"))
}
