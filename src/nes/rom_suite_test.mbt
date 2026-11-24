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
  "downloaded/dmc_dma_during_read4/double_2007_read.nes": "back-to-back $2007 reads both advance the VRAM address",
  "downloaded/blargg_apu_2005.07.30/09.reset_timing.nes": "2005 test expects the first steps 1 cycle earlier than apu_reset/4017_timing does",
  "downloaded/blargg_apu_2005.07.30/10.len_halt_timing.nes": "halt write on the length clock cycle; the newer apu_test timing passes",
  "downloaded/blargg_apu_2005.07.30/11.len_reload_timing.nes": "length reload on the length clock cycle; the newer apu_test timing passes",
}

///|
fn load(path : String) -> @nes.Nes? raise {
  let full = rom_dir + path
  if !@fs.path_exists(full) {
    // Skipping is only fine when nothing was downloaded at all; a missing
    // file in a populated directory means the suite list has a bad path.
    if !path.has_prefix("downloaded/") ||
      @fs.path_exists(rom_dir + "downloaded") {
      fail("test ROM \{full} not found")
    }
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
test "APU test ROMs (apu_test, DMC DMA during reads)" {
  run_area("APU")
}

///|
test "PPU test ROMs (vbl/nmi, sprite 0 hit, sprite overflow, ...)" {
  run_area("PPU")
}
