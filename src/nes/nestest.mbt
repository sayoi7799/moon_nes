// Running nestest in automation mode and comparing with nestest.log.

///|
pub struct NestestReport {
  /// Number of log lines that matched before the first difference.
  matched : Int32
  total : Int32
  /// (line number, expected, actual) of the first difference, if any.
  first_mismatch : (Int32, String, String)?
  /// nestest's own error codes: $02 (official) and $03 (unofficial).
  error_official : Int32
  error_unofficial : Int32
}

///|
/// The current CPU state as a nestest.log line, with the real PPU position.
pub fn Nes::trace_line(self : Nes) -> String {
  self.cpu.trace_line((self.bus.ppu.scanline, self.bus.ppu.dot))
}

///|
/// Runs nestest from $C000 (its automated mode) and compares each executed
/// instruction with the corresponding line of `log`. `on_line` is called
/// with (line number, expected, actual) for every compared line.
pub fn run_nestest(
  rom : Bytes,
  log : String,
  on_line? : (Int32, String, String) -> Unit,
) -> NestestReport raise @cartridge.RomError {
  let nes = Nes::load_rom(rom)
  nes.cpu.set_pc(0xC000)
  let lines = log.split("\n").filter(l => !l.is_empty()).collect()
  let mut matched = 0
  let mut mismatch = None
  for i, expected in lines {
    let actual = nes.trace_line()
    let expected = expected.trim_end(chars="\r").to_owned()
    if on_line is Some(f) {
      f(i + 1, expected, actual)
    }
    if actual != expected {
      mismatch = Some((i + 1, expected, actual))
      break
    }
    matched += 1
    nes.step()
  }
  {
    matched,
    total: lines.length(),
    first_mismatch: mismatch,
    error_official: nes.peek(0x02),
    error_unofficial: nes.peek(0x03),
  }
}
