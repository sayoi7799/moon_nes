// Ricoh 2A03 CPU core: a MOS 6502 without decimal mode.
// Reference: https://www.nesdev.org/wiki/CPU and the 6502 cycle-by-cycle
// tables in https://www.nesdev.org/6502_cpu.txt
//
// Every bus access goes through `rd`/`wr`, which count one cycle and sample
// the interrupt lines at the end of that cycle. Instructions are written so
// that they perform exactly the accesses (including dummy ones) of the real
// chip, which makes cycle counts fall out naturally.

///|
pub const FLAG_C : Int32 = 0x01

///|
pub const FLAG_Z : Int32 = 0x02

///|
pub const FLAG_I : Int32 = 0x04

///|
pub const FLAG_D : Int32 = 0x08

///|
pub const FLAG_B : Int32 = 0x10

///|
pub const FLAG_U : Int32 = 0x20

///|
pub const FLAG_V : Int32 = 0x40

///|
pub const FLAG_N : Int32 = 0x80

///|
pub struct Cpu[B] {
  bus : B
  mut a : Int32
  mut x : Int32
  mut y : Int32
  mut sp : Int32
  mut pc : Int32
  /// Status register. Bit 5 is always set, bit 4 (B) is never stored.
  mut p : Int32
  /// CPU cycles elapsed since power-on.
  mut cycles : Int64
  /// Set by the JAM/KIL opcodes; the CPU then only burns cycles.
  mut jammed : Bool
  // Interrupt sampling. `*_now` is the state sampled at the end of the most
  // recent cycle, `*_prev` the one before it. An instruction acts on the
  // state sampled at the end of its second-to-last cycle, i.e. `*_prev`.
  priv mut nmi_line_was : Bool
  priv mut nmi_latched : Bool
  priv mut nmi_prev : Bool
  priv mut irq_now : Bool
  priv mut irq_prev : Bool
}

///|
pub fn[B] Cpu::new(bus : B) -> Cpu[B] {
  {
    bus,
    a: 0,
    x: 0,
    y: 0,
    sp: 0,
    pc: 0,
    p: FLAG_U | FLAG_I,
    cycles: 0,
    jammed: false,
    nmi_line_was: false,
    nmi_latched: false,
    nmi_prev: false,
    irq_now: false,
    irq_prev: false,
  }
}

///|
/// Samples the interrupt lines at the end of a cycle. `shift` is false only
/// for the one cycle that real hardware does not poll (taken branch that
/// stays on the same page).
fn[B : CpuBus] Cpu::poll(self : Cpu[B], shift : Bool) -> Unit {
  if shift {
    self.nmi_prev = self.nmi_latched
    self.irq_prev = self.irq_now
  }
  let line = self.bus.nmi_line()
  if line && !self.nmi_line_was {
    self.nmi_latched = true
  }
  self.nmi_line_was = line
  self.irq_now = self.bus.irq_line() && (self.p & FLAG_I) == 0
}

///|
#inline
fn[B : CpuBus] Cpu::rd(self : Cpu[B], addr : Int32) -> Int32 {
  self.dmc_dma(addr, false)
  let v = self.bus.read(addr)
  self.cycles += 1
  self.poll(true)
  v
}

///|
#inline
fn[B : CpuBus] Cpu::wr(self : Cpu[B], addr : Int32, value : Int32) -> Unit {
  self.bus.write(addr, value)
  self.cycles += 1
  self.poll(true)
}

///|
/// Reads the byte at PC and advances PC.
#inline
fn[B : CpuBus] Cpu::fetch(self : Cpu[B]) -> Int32 {
  let v = self.rd(self.pc)
  self.pc = (self.pc + 1) & 0xFFFF
  v
}

///|
fn[B : CpuBus] Cpu::push(self : Cpu[B], value : Int32) -> Unit {
  self.wr(0x100 | self.sp, value)
  self.sp = (self.sp - 1) & 0xFF
}

///|
fn[B : CpuBus] Cpu::pull(self : Cpu[B]) -> Int32 {
  self.sp = (self.sp + 1) & 0xFF
  self.rd(0x100 | self.sp)
}

///|
#inline
fn[B] Cpu::set_flag(self : Cpu[B], flag : Int32, on : Bool) -> Unit {
  self.p = if on { self.p | flag } else { self.p & (flag ^ 0xFF) }
}

///|
#inline
fn[B] Cpu::set_zn(self : Cpu[B], v : Int32) -> Unit {
  self.p = (self.p & (FLAG_Z | FLAG_N).lnot()) |
    (if v == 0 { FLAG_Z } else { 0 }) |
    (v & FLAG_N)
}

///|
fn[B] Cpu::set_p_from_stack(self : Cpu[B], v : Int32) -> Unit {
  self.p = (v & (FLAG_B ^ 0xFF)) | FLAG_U
}

///|
/// Runs the 7-cycle reset sequence: three suppressed stack pushes, then the
/// reset vector at $FFFC.
pub fn[B : CpuBus] Cpu::reset(self : Cpu[B]) -> Unit {
  self.rd(self.pc) |> ignore
  self.rd(self.pc) |> ignore
  for _ in 0..<3 {
    self.rd(0x100 | self.sp) |> ignore
    self.sp = (self.sp - 1) & 0xFF
  }
  self.set_flag(FLAG_I, true)
  let lo = self.rd(0xFFFC)
  let hi = self.rd(0xFFFD)
  self.pc = lo | (hi << 8)
  self.jammed = false
  self.nmi_latched = false
  self.nmi_prev = false
  self.irq_prev = false
}

///|
/// The shared tail of BRK, NMI and IRQ: push PC and P, then load a vector.
/// An NMI that arrives while the pushes are happening hijacks the vector.
fn[B : CpuBus] Cpu::interrupt(self : Cpu[B], brk : Bool) -> Unit {
  self.push(self.pc >> 8)
  self.push(self.pc & 0xFF)
  let vector = if self.nmi_latched {
    self.nmi_latched = false
    0xFFFA
  } else {
    0xFFFE
  }
  self.push(self.p | FLAG_U | (if brk { FLAG_B } else { 0 }))
  self.set_flag(FLAG_I, true)
  let lo = self.rd(vector)
  let hi = self.rd(vector + 1)
  self.pc = lo | (hi << 8)
  // The first instruction of a handler always runs before another
  // interrupt is recognised.
  self.nmi_prev = false
  self.irq_prev = false
}

///|
/// Executes one unit of work: a pending interrupt sequence, or one
/// instruction followed by any OAM DMA it triggered.
pub fn[B : CpuBus] Cpu::step(self : Cpu[B]) -> Unit {
  if self.jammed {
    self.rd(0xFFFF) |> ignore
    return
  }
  if self.nmi_prev || self.irq_prev {
    // Hardware interrupt: two dummy reads of PC, then the push sequence.
    self.rd(self.pc) |> ignore
    self.rd(self.pc) |> ignore
    self.interrupt(false)
    return
  }
  let opcode = self.fetch()
  self.execute(opcode)
  let page = self.bus.take_dma_request()
  if page >= 0 {
    self.oam_dma(page)
  }
}

///|
/// OAM DMA: one halt cycle, one alignment cycle on odd cycles, then 256
/// read/write pairs into $2004. 513 or 514 cycles total.
///
/// DMA cycles still see the interrupt lines but are not an instruction's
/// polling point, so an IRQ raised during DMA is taken only after the
/// instruction that follows it.
fn[B : CpuBus] Cpu::oam_dma(self : Cpu[B], page : Int32) -> Unit {
  self.dma_read(self.pc) |> ignore
  if self.cycles % 2L == 1L {
    self.dma_read(self.pc) |> ignore
  }
  let base = page << 8
  for i in 0..<256 {
    if self.bus.dmc_dma_pending() {
      // The DMC takes the get cycle; OAM DMA then needs one cycle to
      // realign its read with the next get cycle.
      self.dmc_dma(base | i, true)
      self.dma_read(base | i) |> ignore
    }
    let v = self.dma_read(base | i)
    self.bus.write(0x2004, v)
    self.cycles += 1
    self.poll(false)
  }
}

///|
fn[B : CpuBus] Cpu::dma_read(self : Cpu[B], addr : Int32) -> Int32 {
  let v = self.bus.read(addr)
  self.cycles += 1
  self.poll(false)
  v
}

///|
/// DMC DMA: when a sample fetch is pending, the CPU is halted before the
/// read of `addr` for 3 or 4 cycles (halt, dummy, optional alignment, get),
/// or 1 or 2 when OAM DMA has already halted it. Like OAM DMA, these
/// cycles see the interrupt lines without being a polling point.
#inline
fn[B : CpuBus] Cpu::dmc_dma(
  self : Cpu[B],
  addr : Int32,
  in_oam_dma : Bool,
) -> Unit {
  if !self.bus.dmc_dma_pending() {
    return
  }
  while true {
    let done = self.bus.dmc_dma_cycle(addr, in_oam_dma)
    self.cycles += 1
    self.poll(false)
    if done {
      break
    }
  }
}

///|
/// Moves the program counter, e.g. to start nestest in automation mode.
pub fn[B] Cpu::set_pc(self : Cpu[B], pc : Int32) -> Unit {
  self.pc = pc & 0xFFFF
}
