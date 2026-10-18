///|
/// Entry point for the CLI or runnable program in this template.
/// Keep main focused; move logic into the library package.
/// Run with `moon run cmd/main` from the project root.
fn main {
  @async.run_async_main(() => {
    let args = @env.args()
    if args.length() != 2 {
      fail("usage: moon run cmd/main -- <heap.hprof>")
    }
    let summary = @lib.parse(@fs.read_file(args[1]).binary())
    println("classes=\{summary.classes}")
    println("instances=\{summary.instances}")
    println("object_arrays=\{summary.object_arrays}")
    println("primitive_arrays=\{summary.primitive_arrays}")
    println("markers=\{summary.count_class("GenerateHeap$Marker")}")
  })
}
