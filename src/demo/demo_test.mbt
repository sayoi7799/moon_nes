///|
fn boot() -> @nes.Nes raise {
  let nes = @nes.Nes::load_rom(@demo.demo_rom()) catch {
    e => fail("demo ROM does not load: " + e.message())
  }
  for _ in 0..<10 {
    nes.run_frame()
  }
  nes
}

///|
test "demo ROM prints its title" {
  let nes = boot()
  let text = nes.screen_text()
  assert_true(text.contains("MOON NES"))
  assert_true(text.contains("A NES EMULATOR"))
  assert_true(text.contains("D-PAD: MOVE"))
}

///|
test "D-pad moves the sprite, A cycles its color" {
  let nes = boot()
  let x0 = nes.peek(0x01)
  let y0 = nes.peek(0x02)
  nes.set_buttons(0, @nes.BUTTON_RIGHT | @nes.BUTTON_DOWN)
  for _ in 0..<10 {
    nes.run_frame()
  }
  assert_eq(nes.peek(0x01), x0 + 10)
  assert_eq(nes.peek(0x02), y0 + 10)
  nes.set_buttons(0, @nes.BUTTON_LEFT | @nes.BUTTON_A)
  for _ in 0..<16 {
    nes.run_frame()
  }
  assert_eq(nes.peek(0x01), x0 - 6)
  assert_eq(nes.peek(0x04), 2) // 16 frames of A -> palette (16 >> 3) & 3
}

///|
test "demo frame hash" {
  let nes = boot()
  nes.set_buttons(0, @nes.BUTTON_UP | @nes.BUTTON_A)
  for _ in 0..<30 {
    nes.run_frame()
  }
  inspect(
    nes.frame_hash(),
    content=(
      #|2578976970
    ),
  )
}

///|
test "assembler resolves labels and rejects bad ones" {
  let a = @demo.Asm::new(0x8000)
  a.label("top")
  a.op(0xEA)
  a.branch(0xD0, "top")
  a.op_label(0x4C, "top")
  assert_eq(a.link(), [0xEA, 0xD0, 0xFD, 0x4C, 0x00, 0x80])
  let b = @demo.Asm::new(0x8000)
  b.branch(0xD0, "nowhere")
  let r = try {
    b.link() |> ignore
    "linked"
  } catch {
    e => e.message()
  }
  assert_eq(r, "undefined label nowhere")
}

///|
/// Runs `frames` frames and returns all samples, quantized to 16 bits so
/// the hash does not depend on how a backend prints doubles.
fn record(nes : @nes.Nes, frames : Int32) -> Array[Int32] {
  let out = []
  let buf = FixedArray::make(4096, 0.0)
  for _ in 0..<frames {
    nes.run_frame()
    let n = nes.take_samples(buf)
    for i in 0..<n {
      let v = (buf[i] * 32767.0).round().to_int()
      out.push(if v > 32767 { 32767 } else if v < -32768 { -32768 } else { v })
    }
  }
  out
}

///|
fn fnv1a(samples : Array[Int32]) -> UInt32 {
  let mut h : UInt32 = 0x811C9DC5
  for v in samples {
    h = (h ^ (v & 0xFF).reinterpret_as_uint()) * 0x01000193
    h = (h ^ ((v >> 8) & 0xFF).reinterpret_as_uint()) * 0x01000193
  }
  h
}

///|
test "demo plays music" {
  let nes = boot()
  let samples = record(nes, 120)
  // About 800 samples per frame at 48 kHz.
  assert_true(samples.length() > 119 * 790)
  let mut peak = 0
  for v in samples {
    peak = if v.abs() > peak { v.abs() } else { peak }
  }
  assert_true(peak > 3000)
}

///|
test "holding A plays the DMC drum" {
  let nes = boot()
  assert_eq(nes.bus.apu.peek_status() & 0x10, 0)
  nes.set_buttons(0, @nes.BUTTON_A)
  let mut playing = false
  for _ in 0..<20000 {
    nes.step()
    if (nes.bus.apu.peek_status() & 0x10) != 0 {
      playing = true
      break
    }
  }
  assert_true(playing)
}

///|
test "demo sample hash" {
  let nes = boot()
  nes.set_buttons(0, @nes.BUTTON_A)
  inspect(
    fnv1a(record(nes, 300)),
    content=(
      #|2450767127
    ),
  )
}
