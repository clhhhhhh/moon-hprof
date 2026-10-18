///|
test "field descriptors support primitives object names and multidimensional arrays" {
  for
    entry in [
      ("I", "int"),
      ("J", "long"),
      ("D", "double"),
      ("[B", "byte[]"),
      ("[[Z", "boolean[][]"),
      ("Ljava/lang/String;", "java.lang.String"),
      ("[[Ljava/util/Map$Entry;", "java.util.Map$Entry[][]"),
    ] {
    assert_eq(field_descriptor(entry.0), entry.1)
  }
}

///|
test "method descriptors track JVM slots independently of argument count" {
  let descriptor = method_descriptor("(IJDLjava/lang/String;[J)V")
  assert_eq(descriptor.parameters, [
    "int", "long", "double", "java.lang.String", "long[]",
  ])
  assert_eq(descriptor.parameter_slots, 7)
  assert_eq(descriptor.return_type, "void")
  assert_eq(
    descriptor.display(),
    "(int, long, double, java.lang.String, long[]) -> void",
  )
  assert_eq(method_descriptor("()[[I").return_type, "int[][]")
  assert_eq(method_descriptor("()V").parameters.length(), 0)
  let frame = parse(sample_dump(8)).stack_trace(7UL)[0]
  assert_eq(frame.readable_signature(), "run() -> void")
}

///|
test "invalid field descriptors fail rather than partially parsing" {
  for
    descriptor in [
      "", "V", "[V", "Q", "L;", "Ljava/lang/String", "II", "[", "Lbad.name;", "Lbad name;",
    ] {
    try field_descriptor(descriptor) catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("accepted invalid field descriptor")
    }
  }
}

///|
test "method descriptors reject missing punctuation invalid void use and overflow" {
  for
    descriptor in [
      "I", "(", "(I", "(I)", "(V)V", "([V)V", "()VV", "(I)Vx", "()Q",
    ] {
    try method_descriptor(descriptor) catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("accepted invalid method descriptor")
    }
  }
  try method_descriptor("(" + "J".repeat(128) + ")V") catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("accepted too many parameter slots")
  }
  try field_descriptor("[".repeat(256) + "I") catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("accepted oversized array rank")
  }
}
