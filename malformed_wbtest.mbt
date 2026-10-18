///|
fn must_reject(data : Bytes) -> Unit raise {
  try parse(data) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("accepted malformed heap dump")
  }
}

///|
test "nontrivial four and eight byte dumps reject every truncated prefix" {
  for width in [4, 8] {
    let bytes = sample_dump(width)
    for length in 0..<bytes.length() {
      must_reject(bytes[0:length].to_owned())
    }
  }
}

///|
test "wrong headers and oversized unsigned record lengths are rejected" {
  let sample = empty_dump(8)
  must_reject(b"JAVA PROFILE 1.0.1\x00" + sample[19:].to_owned())
  must_reject(b"JAVA PROFILE 1.0.3\x00" + sample[19:].to_owned())
  must_reject(sample[0:31].to_owned() + b"\x01\x00\x00\x00\x00\xff\xff\xff\xff")
  must_reject(sample + b"\x01")
}

///|
test "duplicate class objects instances arrays and cross-kind IDs fail" {
  for width in [4, 8] {
    let cls = class_record(100UL, 0UL, width, [], [])
    let instance = instance_record(200UL, 100UL, b"", width)
    let array = object_array_record(200UL, 100UL, [], width)
    let primitive = primitive_array_record(200UL, 8, 0, b"", width)
    for
      heap in [
        cls + cls,
        instance + instance,
        array + array,
        primitive + primitive,
        instance + array,
        primitive + instance,
        cls + instance_record(100UL, 100UL, b"", width),
        instance_record(100UL, 100UL, b"", width) + cls,
      ] {
      must_reject(wrap_heap(heap, width))
    }
  }
}

///|
test "null object class and string IDs are not legal indexed records" {
  for width in [4, 8] {
    must_reject(wrap_heap(class_record(0UL, 0UL, width, [], []), width))
    must_reject(wrap_heap(instance_record(0UL, 100UL, b"", width), width))
    must_reject(wrap_heap(object_array_record(0UL, 100UL, [], width), width))
    must_reject(wrap_heap(primitive_array_record(0UL, 8, 0, b"", width), width))
    must_reject(wrap_heap(b"", width, records=string_record(0UL, "bad", width)))
  }
}

///|
test "duplicate strings cannot silently change class or field names" {
  let records = string_record(1UL, "original", 8) +
    string_record(1UL, "replacement", 8)
  must_reject(wrap_heap(b"", 8, records~))
}

///|
test "all standard GC roots preserve their payload metadata" {
  for width in [4, 8] {
    let mut bytes = b""
    for tag in [0xff, 1, 2, 3, 4, 5, 6, 7, 8] {
      bytes += be(tag.to_uint64(), 1) + be(200UL, width)
      if tag == 1 {
        bytes += be(201UL, width)
      }
      if [2, 3, 4, 6, 8].contains(tag) {
        bytes += be(17UL, 4)
      }
      if [2, 3, 8].contains(tag) {
        bytes += be(19UL, 4)
      }
    }
    let heap = parse(wrap_heap(bytes, width))
    let roots = heap.roots()
    assert_eq(roots.length(), 9)
    assert_eq(roots[0].label(), "unknown")
    assert_eq(roots[1].related_id, 201UL)
    assert_eq(roots[2].thread_serial, 17UL)
    assert_eq(roots[2].frame_number, 19UL)
    assert_eq(roots[8].label(), "thread_object")
  }
}

///|
test "segmented and monolithic heaps have equivalent counts" {
  let data = empty_dump(8)
  let header = data[0:31].to_owned()
  let body = primitive_array_record(200UL, 8, 3, b"abc", 8)
  let segmented = parse(
    header + record(0x1c, b"") + record(0x1c, body) + record(0x2c, b""),
  )
  let monolithic = parse(header + record(0x0c, body))
  assert_eq(segmented.primitive_arrays, 1)
  assert_eq(monolithic.primitive_arrays, 1)
  assert_eq(segmented.payload(200UL), monolithic.payload(200UL))
  assert_eq(segmented.record_count(0x1c), 2)
}

///|
test "end markers enforce ordering shape and unique completion" {
  let header = empty_dump(8)[0:31].to_owned()
  let segment = record(0x1c, b"")
  let end = record(0x2c, b"")
  for
    tail in [
      end,
      segment,
      segment + end + end,
      segment + end + segment,
      segment + record(0x2c, b"x"),
      record(0x0c, b"") + end,
    ] {
    must_reject(header + tail)
  }
}

///|
test "length-delimited unknown top-level records can be skipped safely" {
  let metadata = record(0xf0, b"opaque payload")
  let heap = parse(wrap_heap(b"", 8, records=metadata))
  assert_eq(heap.record_count(0xf0), 1)
  assert_eq(heap.object_count(), 0)
}

///|
test "primitive arrays cover every numeric representation" {
  let cases = [
    (4, b"\x01", "boolean"),
    (5, b"\xff\xff", "char"),
    (6, b"\x3f\xc0\x00\x00", "float"),
    (7, b"\xc0\x02\x00\x00\x00\x00\x00\x00", "double"),
    (8, b"\x80", "byte"),
    (9, b"\x80\x00", "short"),
    (10, b"\x80\x00\x00\x00", "int"),
    (11, b"\x80\x00\x00\x00\x00\x00\x00\x00", "long"),
  ]
  for width in [4, 8] {
    for entry in cases {
      let heap = parse(
        wrap_heap(
          primitive_array_record(200UL, entry.0, 1, entry.1, width),
          width,
        ),
      )
      heap.validate()
      assert_eq(value_type_name(heap.array_values(200UL)[0].kind()), entry.2)
      assert_eq(heap.object(200UL).unwrap().payload_bytes, entry.1.length())
    }
  }
}

///|
test "boolean array invalid bit patterns are detected on query and validation" {
  let heap = parse(
    wrap_heap(primitive_array_record(200UL, 4, 1, b"\x02", 8), 8),
  )
  try heap.array_values(200UL) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("accepted boolean value 2")
  }
  try heap.validate() catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("validation ignored boolean value 2")
  }
}

///|
test "invalid primitive array type and truncated elements are rejected" {
  for kind in [0, 1, 2, 3, 12, 255] {
    must_reject(
      wrap_heap(primitive_array_record(200UL, kind, 1, b"\x00", 8), 8),
    )
  }
  must_reject(wrap_heap(primitive_array_record(200UL, 11, 1, b"\x00", 8), 8))
}

///|
test "class hierarchy cycles and missing definitions fail without looping" {
  let cyclic = parse(
    wrap_heap(
      class_record(100UL, 101UL, 8, [], []) +
      class_record(101UL, 100UL, 8, [], []),
      8,
    ),
  )
  try cyclic.hierarchy(100UL) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("accepted hierarchy cycle")
  }
  let missing = parse(wrap_heap(class_record(100UL, 101UL, 8, [], []), 8))
  try missing.hierarchy(100UL) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("accepted missing superclass")
  }
}

///|
test "instance payload mismatches are detected lazily and by full validation" {
  let records = string_record(1UL, "pkg/Example", 8) +
    string_record(2UL, "value", 8) +
    load_record(1, 100UL, 1UL, 8)
  for payload in [b"", be(42UL, 4) + b"x"] {
    let data = wrap_heap(
      class_record(100UL, 0UL, 8, [(2UL, 10)], []) +
      instance_record(200UL, 100UL, payload, 8),
      8,
      records~,
    )
    let heap = parse(data)
    try heap.instance_fields(200UL) catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("accepted wrong payload size")
    }
    try heap.validate() catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("validation ignored wrong payload size")
    }
  }
}

///|
test "shadowed field lookup requires a declaring class" {
  let records = string_record(1UL, "value", 8)
  let classes = class_record(100UL, 0UL, 8, [(1UL, 10)], []) +
    class_record(101UL, 100UL, 8, [(1UL, 10)], [])
  let heap = parse(
    wrap_heap(
      classes + instance_record(200UL, 101UL, be(42UL, 4) + be(99UL, 4), 8),
      8,
      records~,
    ),
  )
  try heap.field(200UL, "value") catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("ambiguous field returned arbitrary value")
  }
  assert_true(
    heap.field(200UL, "value", declaring_class=101UL) is Some(IntValue(42)),
  )
  assert_true(
    heap.field(200UL, "value", declaring_class=100UL) is Some(IntValue(99)),
  )
}

///|
test "unresolved field names and class names are explicit validation errors" {
  let heap = parse(
    wrap_heap(
      class_record(100UL, 0UL, 8, [(99UL, 10)], []) +
      instance_record(200UL, 100UL, be(1UL, 4), 8),
      8,
    ),
  )
  try heap.validate() catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("missing metadata ignored")
  }
  try heap.instance_fields(200UL) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("missing field name replaced silently")
  }
}

///|
test "primitive arrays cannot be queried as instance fields or class objects" {
  let heap = parse(wrap_heap(primitive_array_record(200UL, 8, 0, b"", 8), 8))
  try heap.instance_fields(200UL) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("wrong instance kind")
  }
  try heap.class_json(200UL) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("wrong class kind")
  }
  assert_eq(heap.references(200UL).length(), 0)
}
