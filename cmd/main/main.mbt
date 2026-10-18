///|
/// Summarizes a dump, optionally counting instances of one JVM class name.
fn main {
  @async.run_async_main(() => {
    let args = @env.args()
    if args.length() == 1 || args[1] == "--help" {
      println(@lib.cli_help())
      return
    }
    if args[1] == "diff" {
      if args.length() != 4 {
        fail("usage: moon-hprof diff <before.hprof> <after.hprof>")
      }
      let before = @lib.parse(@fs.read_file(args[2]).binary())
      let after = @lib.parse(@fs.read_file(args[3]).binary())
      let changes = @lib.compare_heaps(before, after)
      println(Json::array(changes.map(row => row.to_json())).stringify())
      return
    }
    let commands = [
      "summary", "histogram", "objects", "object", "class", "roots", "stack", "refs",
      "check", "inbound", "preview", "export", "referenced",
    ]
    if commands.contains(args[1]) {
      if args.length() < 3 {
        fail("missing heap path; see --help")
      }
      let heap = @lib.parse(@fs.read_file(args[2]).binary())
      let command_args = [args[1]]
      for i in 3..<args.length() {
        command_args.push(args[i])
      }
      println(@lib.execute(heap, command_args))
    } else {
      // Compatibility with the original feasibility command and reference script.
      if args.length() != 2 && args.length() != 3 {
        fail("invalid arguments; see --help")
      }
      let heap = @lib.parse(@fs.read_file(args[1]).binary())
      let command_args = ["summary"]
      if args.length() == 3 {
        command_args.push("--class")
        command_args.push(args[2])
      }
      println(@lib.execute(heap, command_args))
    }
  })
}
