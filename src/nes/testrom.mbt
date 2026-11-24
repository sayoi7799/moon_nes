// Automatic result detection for community test ROMs.

///|
pub(all) enum TestOutcome {
  Passed(String)
  Failed(Int32, String)
  TimedOut(String)
}

///|
pub fn TestOutcome::to_string(self : TestOutcome) -> String {
  match self {
    Passed(_) => "passed"
    Failed(code, text) => "failed (code \{code}) \{text}"
    TimedOut(why) => "timed out: \{why}"
  }
}

///|
fn Nes::read_text(self : Nes, start : Int32, limit : Int32) -> String {
  let s = StringBuilder()
  for addr in start..<(start + limit) {
    let c = self.peek(addr)
    if c == 0 {
      break
    }
    s.write_char(c.unsafe_to_char())
  }
  s.to_string().trim().to_owned()
}

///|
/// Newer blargg tests report through PRG RAM: once $6001-$6003 hold
/// DE B0 61, $6000 is $80 while running, $81 when the test wants the
/// reset button pressed, and the result code (0 = pass) when done. A text
/// log follows at $6004.
pub fn Nes::run_blargg_test(self : Nes, max_frames : Int32) -> TestOutcome {
  let mut reset_at = -1
  for frame in 0..<max_frames {
    self.run_frame()
    if self.peek(0x6001) != 0xDE ||
      self.peek(0x6002) != 0xB0 ||
      self.peek(0x6003) != 0x61 {
      continue
    }
    let status = self.peek(0x6000)
    if status == 0x80 {
      // Right after a reset $6000 still holds the old $81 until the test
      // starts again, so only a request seen after that counts.
      reset_at = -1
      continue
    }
    if status == 0x81 {
      // The test asks for a reset at least 100 ms later.
      if reset_at < 0 {
        reset_at = frame + 10
      } else if frame >= reset_at {
        self.reset()
        reset_at = -1
      }
      continue
    }
    let text = self.read_text(0x6004, 1024)
    return if status == 0 { Passed(text) } else { Failed(status, text) }
  }
  TimedOut(self.read_text(0x6004, 1024))
}

///|
/// Older (2005) blargg tests keep the result code in zero page, where 1
/// means passed, and park the CPU in a `JMP *` loop when finished. Some
/// also wait for NMI in a `JMP *` loop, so a zero result means "not yet".
pub fn Nes::run_legacy_test(
  self : Nes,
  max_frames : Int32,
  result_addr~ : Int32 = 0xF8,
) -> TestOutcome {
  for _ in 0..<max_frames {
    self.run_frame()
    let pc = self.cpu.pc
    let parked = self.peek(pc) == 0x4C &&
      (self.peek(pc + 1) | (self.peek(pc + 2) << 8)) == pc
    let code = self.peek(result_addr)
    if parked && code != 0 {
      return if code == 1 { Passed("") } else { Failed(code, "") }
    }
  }
  TimedOut("result code = \{self.peek(result_addr)}")
}

///|
/// Tests that only print their verdict: waits for "Passed", "Failed" or
/// "Error" to appear in the first nametable. The 2005 tests print them in
/// capitals.
pub fn Nes::run_screen_test(self : Nes, max_frames : Int32) -> TestOutcome {
  for _ in 0..<max_frames {
    self.run_frame()
    let text = self.screen_text()
    if text.contains("Passed") || text.contains("PASSED") {
      return Passed(text)
    }
    if text.contains("Failed") ||
      text.contains("FAILED") ||
      text.contains("Error") ||
      text.contains("ERROR") {
      return Failed(1, text)
    }
  }
  TimedOut(self.screen_text())
}

///|
/// Tests that print a CRC-32 of their output as 8 hex digits: passes when
/// the CRC is one of `expected`, fails on any other CRC.
pub fn Nes::run_screen_crc_test(
  self : Nes,
  max_frames : Int32,
  expected : Array[String],
) -> TestOutcome {
  for _ in 0..<max_frames {
    self.run_frame()
    let text = self.screen_text()
    for line in text.split("\n") {
      let word = line.trim(char_set=" ").to_owned()
      if word.length() == 8 && word.iter().all(c => c.is_ascii_hexdigit()) {
        return if expected.contains(word) {
          Passed(text)
        } else {
          Failed(1, text)
        }
      }
    }
  }
  TimedOut(self.screen_text())
}

///|
/// Value of a hex digit, or -1.
fn hex_digit(c : Char) -> Int32 {
  match c {
    '0'..<='9' => c.to_int() - '0'.to_int()
    'A'..<='F' => c.to_int() - 'A'.to_int() + 10
    _ => -1
  }
}

///|
/// Tests that print a result code as `$XX` once finished: $01 is passed,
/// anything else is the failure code.
pub fn Nes::run_screen_code_test(self : Nes, max_frames : Int32) -> TestOutcome {
  for _ in 0..<max_frames {
    self.run_frame()
    let text = self.screen_text()
    for line in text.split("\n") {
      let word = line.trim(char_set=" ")
      if word.length() != 3 || word[0] != '$' {
        continue
      }
      let hi = hex_digit(word[1].unsafe_to_char())
      let lo = hex_digit(word[2].unsafe_to_char())
      if hi < 0 || lo < 0 {
        continue
      }
      let code = hi * 16 + lo
      return if code == 1 { Passed(text) } else { Failed(code, text) }
    }
  }
  TimedOut(self.screen_text())
}

///|
/// Holy Mapperel prints the detected mapper as three digits at the top left
/// and a 4-digit detail code after ": " once its tests are done; 0000 means
/// all bank, mirroring and RAM checks matched the detected board.
pub fn Nes::run_mapperel_test(
  self : Nes,
  max_frames : Int32,
  mapper : Int32,
) -> TestOutcome {
  let expected_mapper = "00" + mapper.to_string()
  for _ in 0..<max_frames {
    self.run_frame()
    let text = self.screen_text()
    guard text.find(": ") is Some(i) else { continue }
    let code = text.clamped_view(start=i + 2, end=i + 6).to_owned()
    if code.length() != 4 || !code.iter().all(c => c >= '0' && c <= '9') {
      continue
    }
    let header = text
      .split("\n")
      .find_first(line => !line.trim().is_empty())
      .map(line => line.trim().to_owned())
      .unwrap_or("")
    return if code == "0000" && header.has_prefix(expected_mapper) {
      Passed(text)
    } else {
      Failed(1, "detail code \{code}, header: \{header}")
    }
  }
  TimedOut(self.screen_text())
}
