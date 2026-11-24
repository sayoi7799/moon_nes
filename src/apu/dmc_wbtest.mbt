///|
fn steps(apu : Apu, n : Int32) -> Unit {
  for _ in 0..<n {
    apu.step()
  }
}

///|
test "enabling the DMC schedules a load DMA on a get cycle 3-4 cycles later" {
  for offset in 0..<2 {
    let apu = Apu::new()
    steps(apu, offset)
    apu.write(0x4013, 0x00) // 1-byte sample
    apu.write(0x4015, 0x10)
    assert_eq(apu.read_status() & 0x10, 0x10)
    let mut wait = 0
    while !apu.dmc_dma_pending() {
      apu.step()
      wait += 1
    }
    // The DMA halts on the next cycle, which must be a get cycle.
    assert_true(wait == 2 || wait == 3)
    assert_false(apu.get_cycle())
  }
}

///|
test "a 1-byte sample ends after one fetch and raises the IRQ if enabled" {
  let apu = Apu::new()
  apu.write(0x4010, 0x80)
  apu.write(0x4012, 0x01) // $C040
  apu.write(0x4013, 0x00)
  apu.write(0x4015, 0x10)
  steps(apu, 4)
  assert_true(apu.dmc_dma_pending())
  assert_eq(apu.dmc_dma_address(), 0xC040)
  apu.dmc_dma_fill(0xFF)
  assert_false(apu.dmc_dma_pending())
  // Reading $4015 does not clear the DMC IRQ; writing it does.
  assert_eq(apu.read_status() & 0x90, 0x80)
  assert_true(apu.irq_line())
  apu.write(0x4015, 0x00)
  assert_false(apu.irq_line())
}

///|
test "looped samples restart from $4012 and never raise the IRQ" {
  let apu = Apu::new()
  apu.write(0x4010, 0xC0)
  apu.write(0x4013, 0x00)
  apu.write(0x4015, 0x10)
  steps(apu, 4)
  apu.dmc_dma_fill(0x00)
  assert_eq(apu.dmc_dma_address(), 0xC000)
  assert_eq(apu.read_status() & 0x90, 0x10)
}

///|
test "output level moves by 2 per bit at the selected rate" {
  let apu = Apu::new()
  apu.write(0x4010, 0x0F) // rate 54 CPU cycles
  apu.write(0x4011, 0x40)
  apu.write(0x4013, 0x00)
  apu.write(0x4015, 0x10)
  steps(apu, 4)
  apu.dmc_dma_fill(0xFF)
  // The byte enters the shift register when the current 8 silent bits
  // end, then each bit raises the level by 2.
  steps(apu, 54 * 9)
  assert_true(apu.dmc.level > 0x40)
  assert_true(apu.dmc.level <= 0x40 + 16)
  steps(apu, 54 * 16)
  assert_eq(apu.dmc.level, 0x40 + 16)
}

///|
test "the reader wraps from $FFFF to $8000" {
  let dmc = Dmc::new()
  dmc.write(2, 0xFF) // $FFC0
  dmc.write(3, 0x04) // 65 bytes
  dmc.set_enabled(true)
  for _ in 0..<64 {
    dmc.fill(0)
    dmc.buffer_full = false
  }
  assert_eq(dmc.address, 0x8000)
}
