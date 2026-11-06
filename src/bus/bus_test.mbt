///|
fn make_bus() -> @bus.Bus {
  let rom = Bytes::makei(16 + 16384 + 8192, i => {
    match i {
      0 => b'N'
      1 => b'E'
      2 => b'S'
      3 => b'\x1A'
      4 => b'\x01'
      5 => b'\x01'
      _ => b'\x00'
    }
  })
  let cart = @cartridge.parse(rom) catch { e => abort(e.message()) }
  let mapper = @mapper.create(cart) catch { e => abort(e.message()) }
  @bus.Bus::new(mapper)
}

///|
test "internal RAM is mirrored every 2 KiB" {
  let bus = make_bus()
  @cpu.CpuBus::write(bus, 0x0123, 0x5A)
  assert_eq(@cpu.CpuBus::read(bus, 0x0923), 0x5A)
  assert_eq(@cpu.CpuBus::read(bus, 0x1923), 0x5A)
}

///|
test "each access advances the PPU by three dots" {
  let bus = make_bus()
  let before = bus.ppu.dot
  @cpu.CpuBus::read(bus, 0) |> ignore
  assert_eq(bus.ppu.dot - before, 3)
  assert_eq(bus.cycles, 1L)
}

///|
test "controller reports A, B, Select, Start, Up, Down, Left, Right" {
  let bus = make_bus()
  // A + Start + Right.
  bus.pad1.set_buttons(0x01 | 0x08 | 0x80)
  @cpu.CpuBus::write(bus, 0x4016, 1)
  @cpu.CpuBus::write(bus, 0x4016, 0)
  let bits = Array::makei(10, _ => @cpu.CpuBus::read(bus, 0x4016) & 1)
  assert_eq(bits, [1, 0, 0, 1, 0, 0, 0, 1, 1, 1])
}

///|
test "controller keeps returning A while strobe is high" {
  let bus = make_bus()
  bus.pad1.set_buttons(0x01)
  @cpu.CpuBus::write(bus, 0x4016, 1)
  for _ in 0..<3 {
    assert_eq(@cpu.CpuBus::read(bus, 0x4016) & 1, 1)
  }
}

///|
test "writing $4014 requests DMA from that page" {
  let bus = make_bus()
  @cpu.CpuBus::write(bus, 0x4014, 0x02)
  assert_eq(@cpu.CpuBus::take_dma_request(bus), 2)
  assert_eq(@cpu.CpuBus::take_dma_request(bus), -1)
}

///|
test "unmapped reads return the last bus value" {
  let bus = make_bus()
  // NROM has nothing at $5000; the last value on the bus was $50 (the
  // high byte of the address on real hardware, here the previous read).
  @cpu.CpuBus::write(bus, 0x0000, 0x50)
  @cpu.CpuBus::read(bus, 0x0000) |> ignore
  assert_eq(@cpu.CpuBus::read(bus, 0x5000), 0x50)
}
