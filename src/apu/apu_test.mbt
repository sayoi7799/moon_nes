///|
fn run(apu : @apu.Apu, cycles : Int32) -> Unit {
  for _ in 0..<cycles {
    apu.step()
  }
}

///|
test "4-step mode raises the frame IRQ every 29830 cycles" {
  let apu = @apu.Apu::new()
  run(apu, 29827)
  assert_false(apu.irq_line())
  run(apu, 1)
  assert_true(apu.irq_line())
  // The flag is (re)asserted on three consecutive cycles, 29828-29830.
  run(apu, 2)
  // Reading $4015 reports and clears the flag.
  assert_eq(apu.read_status() & 0x40, 0x40)
  assert_false(apu.irq_line())
  run(apu, 29827)
  assert_false(apu.irq_line())
  run(apu, 1)
  assert_true(apu.irq_line())
}

///|
test "IRQ inhibit and 5-step mode never raise the IRQ" {
  let apu = @apu.Apu::new()
  apu.write(0x4017, 0x40)
  run(apu, 100000)
  assert_false(apu.irq_line())
  apu.write(0x4017, 0x80)
  run(apu, 100000)
  assert_false(apu.irq_line())
}

///|
test "length counters load, count down on half frames and halt" {
  let apu = @apu.Apu::new()
  apu.write(0x4015, 0x0F)
  // Index 1 of the length table is 254.
  apu.write(0x4003, 0x08)
  // Triangle with the halt (control) flag set.
  apu.write(0x4008, 0x80)
  apu.write(0x400B, 0x08)
  assert_eq(apu.peek_status() & 0x0F, 0x05)
  // Two half-frame clocks per 4-step sequence.
  run(apu, 29830 * 127)
  assert_eq(apu.peek_status() & 0x0F, 0x04)
  // Disabling a channel clears its counter.
  apu.write(0x4015, 0x00)
  assert_eq(apu.peek_status() & 0x0F, 0)
}

///|
test "length counter does not load while the channel is disabled" {
  let apu = @apu.Apu::new()
  apu.write(0x400F, 0xF8)
  assert_eq(apu.peek_status() & 0x08, 0)
}
