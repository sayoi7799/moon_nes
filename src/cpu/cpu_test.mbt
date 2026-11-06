///|
/// Flat RAM with interrupt lines and a DMA request the test can drive.
struct TestBus {
  ram : @cpu.FlatBus
  mut nmi : Bool
  mut irq : Bool
  mut dma : Int32
  writes : Array[(Int32, Int32)]
}

///|
fn TestBus::new(program : Array[Int32]) -> TestBus {
  let ram = @cpu.FlatBus::new()
  ram.load(0x8000, program)
  // Reset -> $8000, NMI -> $9000, IRQ/BRK -> $A000.
  ram.load(0xFFFA, [0x00, 0x90, 0x00, 0x80, 0x00, 0xA0])
  { ram, nmi: false, irq: false, dma: -1, writes: [], }
}

///|
impl @cpu.CpuBus for TestBus with fn read(self, addr) {
  self.ram.read(addr)
}

///|
impl @cpu.CpuBus for TestBus with fn write(self, addr, value) {
  self.writes.push((addr, value))
  self.ram.write(addr, value)
}

///|
impl @cpu.CpuBus for TestBus with fn peek(self, addr) {
  self.ram.peek(addr)
}

///|
impl @cpu.CpuBus for TestBus with fn nmi_line(self) {
  self.nmi
}

///|
impl @cpu.CpuBus for TestBus with fn irq_line(self) {
  self.irq
}

///|
impl @cpu.CpuBus for TestBus with fn take_dma_request(self) {
  let p = self.dma
  self.dma = -1
  p
}

///|
fn boot(program : Array[Int32]) -> @cpu.Cpu[TestBus] {
  let cpu = @cpu.Cpu::new(TestBus::new(program))
  cpu.reset()
  cpu
}

///|
test "reset takes 7 cycles and loads the vector" {
  let cpu = boot([0xEA])
  assert_eq(cpu.cycles, 7L)
  assert_eq(cpu.pc, 0x8000)
  assert_eq(cpu.sp, 0xFD)
  assert_eq(cpu.p, 0x24)
}

///|
test "only the twelve JAM opcodes are undecoded" {
  let jams = [
    0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72, 0x92, 0xB2, 0xD2, 0xF2,
  ]
  for op in 0..<256 {
    let info = @cpu.opcode_info(op)
    assert_eq(info.mnemonic == "JAM", jams.contains(op))
  }
  let cpu = boot([0x02, 0xE8])
  cpu.step()
  assert_true(cpu.jammed)
  cpu.step()
  assert_eq(cpu.x, 0) // INX never runs
}

///|
test "NMI is edge triggered and pushes B clear" {
  let cpu = boot([0xEA, 0xEA, 0xEA, 0xEA])
  cpu.bus.nmi = true
  cpu.step() // NOP; the edge is seen during it
  cpu.step() // interrupt sequence
  assert_eq(cpu.pc, 0x9000)
  assert_eq(cpu.bus.ram.peek(0x1FB) & 0x30, 0x20)
  // Holding the line does not retrigger.
  cpu.bus.ram.write(0x9000, 0xEA)
  cpu.bus.ram.write(0x9001, 0xEA)
  cpu.step()
  cpu.step()
  assert_eq(cpu.pc, 0x9002)
}

///|
test "interrupt sequence is 7 cycles" {
  let cpu = boot([0xEA, 0xEA])
  cpu.bus.nmi = true
  cpu.step()
  let before = cpu.cycles
  cpu.step()
  assert_eq(cpu.cycles - before, 7L)
}

///|
test "IRQ respects the I flag and CLI takes effect one instruction late" {
  // CLI ; NOP ; NOP
  let cpu = boot([0x58, 0xEA, 0xEA])
  cpu.bus.irq = true
  cpu.step() // CLI: I was still set when polled
  assert_eq(cpu.pc, 0x8001)
  cpu.step() // NOP runs before the IRQ is taken
  assert_eq(cpu.pc, 0x8002)
  cpu.step() // IRQ sequence
  assert_eq(cpu.pc, 0xA000)
  assert_true((cpu.p & @cpu.FLAG_I) != 0)
}

///|
test "BRK pushes B set and skips the padding byte" {
  let cpu = boot([0x00, 0xFF])
  cpu.step()
  assert_eq(cpu.pc, 0xA000)
  assert_eq(cpu.bus.ram.peek(0x1FB) & 0x30, 0x30)
  // Return address is BRK + 2.
  assert_eq(cpu.bus.ram.peek(0x1FD), 0x80)
  assert_eq(cpu.bus.ram.peek(0x1FC), 0x02)
}

///|
test "NMI during BRK hijacks the vector" {
  let cpu = boot([0x00, 0x00])
  let before = cpu.cycles
  // The edge is latched on BRK's first cycle, too late to be taken before
  // BRK but early enough to redirect its vector fetch.
  cpu.bus.nmi = true
  cpu.step()
  assert_eq(cpu.cycles - before, 7L)
  assert_eq(cpu.pc, 0x9000)
  // B flag still set in the pushed status: it was a BRK.
  assert_eq(cpu.bus.ram.peek(0x1FB) & 0x10, 0x10)
}

///|
test "OAM DMA takes 513 or 514 cycles and writes $2004" {
  // STA $4014 (A = 0)
  let cpu = boot([0x8D, 0x14, 0x40, 0x8D, 0x14, 0x40])
  for i in 0..<256 {
    cpu.bus.ram.write(0x0200 + i, i)
  }
  cpu.bus.writes.clear()
  cpu.bus.dma = 2
  let start = cpu.cycles
  cpu.step()
  let first = cpu.cycles - start - 4L
  let dma_writes = cpu.bus.writes.filter(w => w.0 == 0x2004)
  assert_eq(dma_writes.length(), 256)
  assert_eq(dma_writes[255], (0x2004, 255))
  cpu.bus.dma = 2
  let start = cpu.cycles
  cpu.step()
  let second = cpu.cycles - start - 4L
  // One of the two started on an odd cycle.
  assert_eq([first, second].contains(513L), true)
  assert_eq([first, second].contains(514L), true)
}

///|
test "page-crossing reads cost one extra cycle, writes always pay it" {
  // LDX #$FF ; LDA $80FF,X (crosses) ; LDA $8000,X (no cross) ; STA $8000,X
  let cpu = boot([
    0xA2, 0x01, 0xBD, 0xFF, 0x80, 0xBD, 0x00, 0x80, 0x9D, 0x00, 0x03,
  ])
  cpu.step()
  let c0 = cpu.cycles
  cpu.step()
  assert_eq(cpu.cycles - c0, 5L)
  let c1 = cpu.cycles
  cpu.step()
  assert_eq(cpu.cycles - c1, 4L)
  let c2 = cpu.cycles
  cpu.step()
  assert_eq(cpu.cycles - c2, 5L)
}

///|
test "taken branches cost 3 cycles, 4 across a page" {
  // CLC ; BCC +0 ; at $8003: BCC -> $80F0 region? use a backwards jump over page
  let program = Array::make(0x200, 0xEA)
  program[0] = 0x18
  program[1] = 0x90 // BCC +0
  program[2] = 0x00
  program[3] = 0x90 // BCC +$7F -> $8084 (same page)
  program[4] = 0x7F
  program[0x84] = 0x90 // BCC +$7F -> $8105 (crosses)
  program[0x85] = 0x7F
  let cpu = boot(program)
  cpu.step()
  let c = cpu.cycles
  cpu.step()
  assert_eq(cpu.cycles - c, 3L)
  let c = cpu.cycles
  cpu.step()
  assert_eq(cpu.pc, 0x8084)
  assert_eq(cpu.cycles - c, 3L)
  let c = cpu.cycles
  cpu.step()
  assert_eq(cpu.pc, 0x8105)
  assert_eq(cpu.cycles - c, 4L)
}
