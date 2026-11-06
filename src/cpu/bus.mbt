///|
/// What the CPU sees of the rest of the machine.
///
/// Every `read` and `write` is exactly one CPU cycle: the implementation is
/// expected to advance the rest of the system (PPU, mapper timers) by one CPU
/// cycle as part of the access. Dummy reads and writes of the real 6502 are
/// issued too, so side effects on I/O registers happen as on hardware.
pub(open) trait CpuBus {
  fn read(Self, Int32) -> Int32
  fn write(Self, Int32, Int32) -> Unit
  /// Reads memory without side effects and without consuming a cycle.
  /// Used only for tracing and disassembly.
  fn peek(Self, Int32) -> Int32
  /// Level of the NMI line (true = asserted). The CPU detects the edge.
  fn nmi_line(Self) -> Bool
  /// Level of the IRQ line (true = asserted).
  fn irq_line(Self) -> Bool
  /// Returns the page written to $4014 since the last call, or -1.
  fn take_dma_request(Self) -> Int32
}

///|
/// A flat 64 KiB RAM bus, handy for unit tests and for nestest.
pub struct FlatBus {
  mem : FixedArray[Int32]
  mut dma_page : Int32
}

///|
pub fn FlatBus::new() -> FlatBus {
  { mem: FixedArray::make(0x10000, 0), dma_page: -1, }
}

///|
pub fn FlatBus::load(
  self : FlatBus,
  addr : Int32,
  data : ArrayView[Int32],
) -> Unit {
  for i, b in data {
    self.mem[(addr + i) & 0xFFFF] = b & 0xFF
  }
}

///|
pub impl CpuBus for FlatBus with fn read(self, addr) {
  self.mem[addr]
}

///|
pub impl CpuBus for FlatBus with fn write(self, addr, value) {
  self.mem[addr] = value
}

///|
pub impl CpuBus for FlatBus with fn peek(self, addr) {
  self.mem[addr]
}

///|
pub impl CpuBus for FlatBus with fn nmi_line(_) {
  false
}

///|
pub impl CpuBus for FlatBus with fn irq_line(_) {
  false
}

///|
pub impl CpuBus for FlatBus with fn take_dma_request(self) {
  let p = self.dma_page
  self.dma_page = -1
  p
}
