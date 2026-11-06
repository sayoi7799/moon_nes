///|
/// Runs nestest.nes on the emulated console and compares the CPU trace with
/// the reference nestest.log, line by line.
///
/// Usage (from the repository root, after scripts/fetch-test-roms.sh):
///   moon run src/cmd/nestest            summary plus first/last lines
///   moon run src/cmd/nestest -- --all   every line
fn main {
  let dir = "test-roms/downloaded/other/"
  let print_all = @env.args().contains("--all")
  if !@fs.path_exists(dir + "nestest.nes") {
    println("nestest.nes not found; run scripts/fetch-test-roms.sh first")
    return
  }
  let rom = @fs.read_file_to_bytes(dir + "nestest.nes") catch {
    _ => abort("cannot read nestest.nes")
  }
  let log = @fs.read_file_to_string(dir + "nestest.log") catch {
    _ => abort("cannot read nestest.log")
  }
  let total = log.split("\n").filter(l => !l.is_empty()).count()
  let show = (n : Int32) => print_all || n <= 3 || n > total - 3
  let on_line = (n : Int32, expected : String, actual : String) => {
    if expected != actual {
      println("line \{n} differs:")
      println("  expected  \{expected}")
      println("  actual    \{actual}")
    } else if show(n) {
      println("ok \{n}\t\{actual}")
    } else if n == 4 {
      println("...")
    }
  }
  let report = @nes.run_nestest(rom, log, on_line~) catch {
    e => abort("cannot load nestest.nes: \{e.message()}")
  }
  println("")
  println(
    "compared PC, opcode bytes, disassembly, A/X/Y/P/SP, PPU dot and CPU cycle",
  )
  println("\{report.matched} / \{report.total} lines match nestest.log")
  println(
    "nestest error codes: $02 = \{report.error_official}, $03 = \{report.error_unofficial} (0 = all passed)",
  )
}
