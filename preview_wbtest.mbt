///|
test "previews are one level and report item and character truncation" {
  let heap = parse(sample_dump(8))
  let preview = heap.preview(200UL, max_items=2)
  assert_true(preview.text.contains("count=42"))
  assert_true(preview.text.contains("ref=@c9"))
  assert_true(preview.truncated)
  let full = heap.preview(200UL, max_items=100, max_chars=1000)
  assert_true(!full.truncated)
  let short = heap.preview(200UL, max_chars=5)
  assert_eq(short.text.to_array().length(), 5)
  assert_true(short.truncated)
  let array = heap.preview(300UL, max_items=100)
  assert_true(array.text.contains("null"))
  assert_eq(array.array_length, Some(3))
  assert_true(!array.truncated)
}

///|
test "bounded JSON Lines exports preserve page order and array item limits" {
  let heap = parse(sample_dump(4))
  let expected = heap.object_json(300UL, limit=1).stringify() + "\n"
  assert_eq(heap.objects_jsonl(offset=2, limit=1, array_limit=1), expected)
  assert_eq(heap.objects_jsonl(offset=5), "")
  let previews = heap.previews_jsonl(class_id=101UL, max_items=1)
  assert_eq(
    previews,
    heap.preview(200UL, max_items=1).to_json().stringify() + "\n",
  )
  assert_eq(
    execute(heap, ["export", "101"]),
    heap.objects_jsonl(class_id=101UL),
  )
  assert_eq(
    execute(heap, ["preview", "200", "--limit", "2"]),
    heap.preview(200UL, max_items=2).to_json().stringify(),
  )
  assert_eq(
    execute(heap, ["inbound", "201", "--limit", "1"]),
    Json::array(
      ReferenceIndex::build(heap)
      .incoming(201UL, limit=1)
      .map(edge => edge.to_json()),
    ).stringify(),
  )
}

///|
test "preview and export limits are validated even for empty pages" {
  let heap = parse(sample_dump(8))
  let invalid : Array[() -> Unit raise ParseError] = [
    () => ignore(heap.preview(200UL, max_chars=-1)),
    () => ignore(heap.preview(200UL, max_items=100001)),
    () => ignore(heap.objects_jsonl(limit=0, array_limit=-1)),
    () => ignore(heap.previews_jsonl(limit=0, max_chars=-1)),
  ]
  for operation in invalid {
    try operation() catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("invalid limits ignored")
    }
  }
}
