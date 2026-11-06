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
