///|
test "CLI parses decimal and hexadecimal unsigned IDs exactly" {
  for
    entry in [
      ("0", 0UL),
      ("0x0", 0UL),
      ("255", 255UL),
      ("0Xff", 255UL),
      ("18446744073709551615", 18446744073709551615UL),
      ("0xffffffffffffffff", 18446744073709551615UL),
    ] {
    assert_eq(parse_object_id(entry.0), entry.1)
  }
  for
    text in [
      "", "0x", "-1", "+1", " 1", "1 ", "1.0", "0xg", "18446744073709551616", "0x10000000000000000",
    ] {
    try parse_object_id(text) catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("accepted invalid ID")
    }
  }
}

///|
test "summary CLI renders a class count and valid structured output" {
  let heap = parse(sample_dump(8))
  assert_eq(
    execute(heap, ["summary", "--class", "pkg/Child"]),
    "classes=3\ninstances=2\nobject_arrays=1\nprimitive_arrays=2\nclass_instances=1",
  )
  assert_eq(
    execute(heap, ["summary", "--format", "json"]),
    heap.summary_json().stringify(),
  )
  assert_eq(execute(heap, ["check"]), "OK")
}

///|
test "histogram CLI applies filtering before offset and limit" {
  let heap = parse(sample_dump(4))
  let args = [
    "histogram", "--kind", "instance", "--prefix", "pkg/", "--sort", "name", "--offset",
    "1", "--limit", "1",
  ]
  let expected = heap.select_histogram(
    kind="instance",
    prefix="pkg/",
    sort=Name,
    offset=1,
    limit=1,
  )
  assert_eq(
    execute(heap, args),
    Json::array(expected.map(row => row.to_json())).stringify(),
  )
  let csv = execute(heap, [
    "histogram", "--format", "csv", "--kind", "primitive_array",
  ])
  assert_true(csv.contains("byte[]"))
  assert_true(!csv.contains("pkg/Child"))
}

///|
test "object class stack roots and reference commands use the library queries" {
  let heap = parse(sample_dump(8))
  assert_eq(
    execute(heap, ["object", "0xc8"]),
    heap.object_json(200UL).stringify(),
  )
  assert_eq(execute(heap, ["class", "101"]), heap.class_json(101UL).stringify())
  assert_eq(
    execute(heap, ["roots", "--limit", "1"]),
    Json::array(heap.roots(limit=1).map(root => root.to_json())).stringify(),
  )
  assert_eq(
    execute(heap, ["stack", "7"]),
    Json::array(heap.stack_trace(7UL).map(frame => frame.to_json())).stringify(),
  )
  assert_eq(
    execute(heap, ["refs", "200"]),
    Json::array(heap.references(200UL).map(edge => edge.to_json())).stringify(),
  )
}

///|
test "CLI rejects unknown duplicate missing and command-inappropriate options" {
  let heap = parse(sample_dump(4))
  let invalid = [
    [],
    ["unknown"],
    ["object"],
    ["class", "-1"],
    ["summary", "--format"],
    ["summary", "--format", "xml"],
    ["summary", "--limit", "1"],
    ["summary", "--format", "text", "--format", "json"],
    ["histogram", "--sort", "bad"],
    ["histogram", "--format", "text"],
    ["histogram", "--kind", "bad"],
    ["histogram", "--limit", "100001"],
    ["histogram", "--offset", "-1"],
    ["histogram", "--offset", "999"],
    ["check", "anything", "1"],
    ["object", "300", "--class", "pkg/Child"],
  ]
  for args in invalid {
    try execute(heap, args) catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("accepted malformed command")
    }
  }
}
