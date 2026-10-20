///|
test "bidirectional index counts null slots but stores only non-null edges" {
  let index = ReferenceIndex::build(parse(sample_dump(8)))
  assert_eq(index.slot_count(), 20)
  assert_eq(index.edge_count(), 11)
  let inbound = index.incoming(201UL)
  assert_eq(inbound.map(edge => edge.source_id), [101UL, 200UL, 300UL])
  assert_eq(inbound[1].label, "101:ref")
  assert_eq(index.outgoing(300UL).map(edge => edge.target_id), [
    102UL, 200UL, 201UL,
  ])
  assert_eq(index.incoming(55UL)[0].label, "class_loader")
  assert_eq(index.incoming(100UL)[0].source_id, 101UL)
  assert_eq(index.incoming(0UL).length(), 0)
  assert_eq(index.incoming(201UL, offset=1, limit=1)[0].source_id, 200UL)
}

///|
test "index budgets fail explicitly instead of exposing partial data" {
  let heap = parse(sample_dump(4))
  for limits in [(10, 20), (11, 19), (-1, 20), (11, -1)] {
    try
      ReferenceIndex::build(heap, max_edges=limits.0, max_slots=limits.1)
    catch {
      Invalid(_, _) => ()
    } noraise {
      _ => fail("accepted exhausted index budget")
    }
  }
  assert_eq(
    ReferenceIndex::build(heap, max_edges=11, max_slots=20).edge_count(),
    11,
  )
  assert_eq(
    ReferenceIndex::build(parse(empty_dump(8)), max_edges=0, max_slots=0).edge_count(),
    0,
  )
}

///|
test "breadth-first path chooses the shortest edge and reports budgets honestly" {
  let index = ReferenceIndex::build(parse(sample_dump(8)))
  let path = index.path(300UL, 201UL)
  assert_true(path.found)
  assert_true(!path.truncated)
  assert_eq(path.edges.length(), 1)
  assert_eq(path.edges[0].label, "[2]")
  let absent = index.path(201UL, 200UL)
  assert_true(!absent.found && !absent.truncated)
  let depth = index.path(300UL, 201UL, max_depth=0)
  assert_true(!depth.found && depth.truncated)
  let nodes = index.path(300UL, 201UL, max_nodes=1)
  assert_true(!nodes.found && nodes.truncated)
  let edges = index.path(300UL, 201UL, max_edges=0)
  assert_true(!edges.found && edges.truncated)
  assert_eq(index.path(200UL, 200UL).edges.length(), 0)
}

///|
test "reference cycles terminate and multi-edge paths reconstruct in source order" {
  let records = string_record(1UL, "next", 8)
  let cls = class_record(100UL, 0UL, 8, [(1UL, 2)], [])
  let instances = instance_record(200UL, 100UL, be(201UL, 8), 8) +
    instance_record(201UL, 100UL, be(202UL, 8), 8) +
    instance_record(202UL, 100UL, be(200UL, 8), 8) +
    primitive_array_record(300UL, 8, 0, b"", 8)
  let heap = parse(wrap_heap(cls + instances, 8, records~))
  let index = ReferenceIndex::build(heap)
  let path = index.path(200UL, 202UL)
  assert_eq(path.edges.map(edge => edge.source_id), [200UL, 201UL])
  assert_eq(path.edges.map(edge => edge.target_id), [201UL, 202UL])
  assert_true(!index.path(200UL, 300UL).found)
  assert_true(!index.path(200UL, 300UL).truncated)
  try index.path(999UL, 999UL) catch {
    Invalid(_, _) => ()
  } noraise {
    _ => fail("invented a path for a nonexistent object")
  }
}

///|
test "reference rankings distinguish repeated edges from distinct referring objects" {
  let bytes = object_array_record(300UL, 100UL, [200UL, 200UL, 999UL], 8) +
    primitive_array_record(200UL, 8, 0, b"", 8)
  let index = ReferenceIndex::build(parse(wrap_heap(bytes, 8)))
  assert_eq(index.referrer_ids(200UL), [300UL])
  let rows = index.most_referenced()
  assert_eq(rows[0].object_id, 200UL)
  assert_eq(rows[0].reference_count, 2)
  assert_eq(rows[0].source_count, 1)
  assert_true(rows[0].present_in_heap)
  assert_true(!rows[1].present_in_heap)
  assert_eq(index.most_referenced(limit=0).length(), 0)
  let heap = parse(sample_dump(8))
  let expected = ReferenceIndex::build(heap).most_referenced(limit=1)
  assert_eq(
    execute(heap, ["referenced", "--limit", "1"]),
    Json::array(expected.map(row => row.to_json())).stringify(),
  )
}
