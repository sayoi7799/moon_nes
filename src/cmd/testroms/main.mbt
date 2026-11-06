///|
/// Runs every ROM of the test suite and prints a Markdown result table.
/// Usage (from the repository root): moon run src/cmd/testroms [filter]
/// where `filter` keeps only ROMs whose path contains it.
fn main {
  let dir = "test-roms/"
  let args = @env.args()
  let filter = if args.length() > 1 { args[args.length() - 1] } else { "" }
  let mut passed = 0
  let mut total = 0
  println("| Area | ROM | Result |")
  println("|---|---|---|")
  for rom in @nes.test_suite {
    if !rom.path.contains(filter) {
      continue
    }
    let path = dir + rom.path
    let result = if !@fs.path_exists(path) {
      "not downloaded"
    } else {
      try {
        let nes = @nes.Nes::load_rom(@fs.read_file_to_bytes(path))
        total += 1
        match nes.run_suite_rom(rom) {
          Passed(_) => {
            passed += 1
            "pass"
          }
          outcome =>
            "FAIL: " + outcome.to_string().replace_all(old="\n", new=" ")
        }
      } catch {
        e => "error: \{e}"
      }
    }
    println("| \{rom.area} | `\{rom.path}` | \{result} |")
  }
  println("")
  println("\{passed} / \{total} passed")
}
