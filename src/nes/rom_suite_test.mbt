// Runs the community test ROMs downloaded by scripts/fetch-test-roms.sh.
// A ROM that has not been fetched is skipped with a message.

///|
let rom_dir = "test-roms/"

///|
/// ROMs that are known not to pass yet, with the reason. The test fails if
/// one of these starts passing, so the list (and the README table) stays
/// accurate.
let known_failures : Map[String, String] = {
  "downloaded/blargg_ppu_tests_2005.09.15b/vbl_clear_time.nes": "NMI latency margin of the 2005 test",
}

///|
fn load(path : String) -> @nes.Nes? raise {
  let full = rom_dir + path
  if !@fs.path_exists(full) {
    println("skip: \{full} missing, run scripts/fetch-test-roms.sh")
    return None
  }
  Some(@nes.Nes::load_rom(@fs.read_file_to_bytes(full)))
}

///|
fn run_area(area : String) -> Unit raise {
  let problems = []
  for rom in @nes.test_suite {
    if rom.area != area {
      continue
    }
    guard load(rom.path) is Some(nes) else { continue }
    let passed = nes.run_suite_rom(rom) is Passed(_)
    match (passed, known_failures.get(rom.path)) {
      (false, None) => problems.push("regression: \{rom.path}")
      (true, Some(_)) =>
        problems.push("now passes, remove from known_failures: \{rom.path}")
      _ => ()
    }
  }
  if !problems.is_empty() {
    fail(problems.join("\n"))
  }
}

///|
test "CPU test ROMs (blargg instr_test, instr_misc, interrupts, ...)" {
  run_area("CPU")
}

///|
test "mapper test ROMs (Holy Mapperel for NROM, MMC1, UxROM, CNROM)" {
  run_area("Mapper")
}

///|
test "PPU test ROMs (vbl/nmi, sprite 0 hit, sprite overflow, ...)" {
  run_area("PPU")
}
