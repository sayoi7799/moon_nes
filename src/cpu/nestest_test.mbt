///|
/// Path of the downloaded test ROM tree, relative to the module root.
let rom_dir = "test-roms/downloaded"

///|
/// Flat RAM, except that the write-only APU/IO registers read back as $FF
/// like they do in the emulator that produced nestest.log.
struct NestestBus {
  ram : @cpu.FlatBus
}

///|
impl @cpu.CpuBus for NestestBus with fn read(self, addr) {
  self.ram.read(addr)
}

///|
impl @cpu.CpuBus for NestestBus with fn write(self, addr, value) {
  self.ram.write(addr, value)
}

///|
impl @cpu.CpuBus for NestestBus with fn peek(self, addr) {
  if addr >= 0x4000 && addr < 0x4020 {
    0xFF
  } else {
    self.ram.peek(addr)
  }
}

///|
impl @cpu.CpuBus for NestestBus with fn nmi_line(_) {
  false
}

///|
impl @cpu.CpuBus for NestestBus with fn irq_line(_) {
  false
}

///|
impl @cpu.CpuBus for NestestBus with fn take_dma_request(_) {
  -1
}

///|
/// Runs nestest on the flat bus and compares every line with nestest.log.
/// The PPU position is derived from the cycle count (3 dots per cycle,
/// 341 dots per scanline); the log covers less than one frame.
test "nestest.log matches line by line" {
  let rom_path = rom_dir + "/other/nestest.nes"
  if !@fs.path_exists(rom_path) {
    println("skip: \{rom_path} missing, run scripts/fetch-test-roms.sh")
    return
  }
  let rom = @fs.read_file_to_bytes(rom_path)
  let log = @fs.read_file_to_string(rom_dir + "/other/nestest.log")
  let bus = @cpu.FlatBus::new()
  // nestest is NROM-128: 16 KiB of PRG mirrored at $8000 and $C000.
  let prg = Array::makei(16384, i => rom[16 + i].to_int())
  bus.load(0x8000, prg)
  bus.load(0xC000, prg)
  let cpu = @cpu.Cpu::new(NestestBus::{ ram: bus, })
  cpu.reset()
  cpu.set_pc(0xC000)
  let mut checked = 0
  for expected in log.split("\n") {
    if expected.is_empty() {
      continue
    }
    let dots = cpu.cycles.to_int() * 3
    let actual = cpu.trace_line((dots / 341, dots % 341))
    if actual != expected.to_owned() {
      fail(
        "line \{checked + 1} differs\n  expected: \{expected}\n  actual:   \{actual}",
      )
    }
    cpu.step()
    checked += 1
  }
  assert_eq(checked, 8991)
  // nestest leaves its error codes in $02 (official) and $03 (unofficial).
  assert_eq(bus.peek(0x02), 0)
  assert_eq(bus.peek(0x03), 0)
}
