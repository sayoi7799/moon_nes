// MMC3 (mapper 4, TxROM boards): 8 KiB PRG and 1/2 KiB CHR banking,
// switchable mirroring, PRG RAM protection and a scanline counter clocked
// by rises of PPU address line A12.
// Reference: https://www.nesdev.org/wiki/MMC3, blargg's mmc3_test readme

///|
/// A rise of A12 only clocks the counter after A12 has been low for a
/// while: the MMC3 waits for three falling edges of M2 (the CPU clock, one
/// per 3 PPU dots). The short low gaps between the sprite pattern fetches
/// of one line are filtered out this way, so a line clocks the counter once.
const A12_FILTER_DOTS : Int64 = 9

///|
priv struct Mmc3 {
  mem : Memory
  four_screen : Bool
  /// NES 2.0 submapper 4: the older MMC3A behavior, which raises the IRQ
  /// only when the counter becomes 0, not on every clock while it is 0.
  irq_on_transition_only : Bool
  /// Bank select ($8000): register index, PRG mode (bit 6), CHR A12
  /// inversion (bit 7).
  mut select : Int32
  /// R0-R7.
  regs : FixedArray[Int32]
  mut horizontal : Bool
  mut ram_enabled : Bool
  mut ram_write_protect : Bool
  mut irq_latch : Int32
  mut irq_counter : Int32
  mut irq_reload : Bool
  mut irq_enabled : Bool
  mut irq : Bool
  /// Whether A12 was high on the last access, and since when it is low.
  mut a12_high : Bool
  mut a12_low_since : Int64
}

///|
fn Mmc3::new(cart : @cartridge.Cartridge) -> &Mapper {
  {
    mem: Memory::new(cart),
    four_screen: cart.mirroring is FourScreen,
    irq_on_transition_only: cart.is_nes2 && cart.submapper == 4,
    select: 0,
    // The power-up bank registers are unspecified; these give distinct
    // banks for programs that read before writing them.
    regs: [0, 2, 4, 5, 6, 7, 0, 1],
    horizontal: cart.mirroring is Horizontal,
    ram_enabled: true,
    ram_write_protect: false,
    irq_latch: 0,
    irq_counter: 0,
    irq_reload: false,
    irq_enabled: false,
    irq: false,
    a12_high: false,
    a12_low_since: 0L,
  }
}

///|
/// 8 KiB PRG bank mapped at `addr` ($8000-$FFFF).
fn Mmc3::prg_bank(self : Mmc3, addr : Int32) -> Int32 {
  let last = self.mem.prg.length() / 0x2000 - 1
  let swap = (self.select & 0x40) != 0
  match (addr >> 13) & 3 {
    0 => if swap { last - 1 } else { self.regs[6] & 0x3F }
    1 => self.regs[7] & 0x3F
    2 => if swap { self.regs[6] & 0x3F } else { last - 1 }
    _ => last
  }
}

///|
/// 1 KiB CHR bank mapped at `addr` ($0000-$1FFF).
fn Mmc3::chr_bank(self : Mmc3, addr : Int32) -> Int32 {
  // With bit 7 set, the 2 KiB banks move to $1000 and the 1 KiB ones to
  // $0000; flipping A12 of the address gives the same mapping.
  let a = if (self.select & 0x80) != 0 { addr ^ 0x1000 } else { addr }
  let slot = (a >> 10) & 7
  match slot {
    0 | 1 => (self.regs[0] & 0xFE) | slot
    2 | 3 => (self.regs[1] & 0xFE) | (slot & 1)
    _ => self.regs[slot - 2]
  }
}

///|
impl Mapper for Mmc3 with fn cpu_read(self, addr) {
  if addr < 0x6000 {
    -1
  } else if addr < 0x8000 {
    if self.ram_enabled {
      self.mem.ram_read(addr)
    } else {
      -1
    }
  } else {
    self.mem.prg_at(self.prg_bank(addr), 0x2000, addr & 0x1FFF)
  }
}

///|
impl Mapper for Mmc3 with fn cpu_write(self, addr, value, _cycle) {
  if addr < 0x6000 {
    return
  }
  if addr < 0x8000 {
    if self.ram_enabled && !self.ram_write_protect {
      self.mem.ram_write(addr, value)
    }
    return
  }
  let odd = (addr & 1) != 0
  match ((addr >> 13) & 3, odd) {
    (0, false) => self.select = value
    (0, true) => self.regs[self.select & 7] = value
    (1, false) => self.horizontal = (value & 1) != 0
    (1, true) => {
      self.ram_enabled = (value & 0x80) != 0
      self.ram_write_protect = (value & 0x40) != 0
    }
    (2, false) => self.irq_latch = value
    (2, true) => {
      // Cleared now and reloaded from the latch on the next clock; this
      // does not raise the IRQ by itself.
      self.irq_counter = 0
      self.irq_reload = true
    }
    (_, false) => {
      self.irq_enabled = false
      self.irq = false
    }
    (_, true) => self.irq_enabled = true
  }
}

///|
impl Mapper for Mmc3 with fn ppu_read(self, addr) {
  self.mem.chr[self.mem.chr_index(self.chr_bank(addr), 0x400, addr & 0x3FF)].to_int()
}

///|
impl Mapper for Mmc3 with fn ppu_write(self, addr, value) {
  self.mem.chr_write(
    self.mem.chr_index(self.chr_bank(addr), 0x400, addr & 0x3FF),
    value,
  )
}

///|
impl Mapper for Mmc3 with fn mirroring(self) {
  if self.four_screen {
    FourScreen
  } else if self.horizontal {
    Horizontal
  } else {
    Vertical
  }
}

///|
/// One clock of the scanline counter.
fn Mmc3::clock_counter(self : Mmc3) -> Unit {
  let before = self.irq_counter
  let reloading = self.irq_counter == 0 || self.irq_reload
  if reloading {
    self.irq_counter = self.irq_latch
  } else {
    self.irq_counter -= 1
  }
  // MMC3B/C: every clock that leaves 0 raises the IRQ, also when the latch
  // is 0. MMC3A: only a change to 0, or a reload requested by $C001.
  let fires = if self.irq_on_transition_only {
    before != 0 || self.irq_reload
  } else {
    true
  }
  self.irq_reload = false
  if self.irq_counter == 0 && fires && self.irq_enabled {
    self.irq = true
  }
}

///|
impl Mapper for Mmc3 with fn ppu_bus(self, addr, dot) {
  let high = (addr & 0x1000) != 0
  if high && !self.a12_high && dot - self.a12_low_since >= A12_FILTER_DOTS {
    self.clock_counter()
  }
  if !high && self.a12_high {
    self.a12_low_since = dot
  }
  self.a12_high = high
}

///|
impl Mapper for Mmc3 with fn irq_line(self) {
  self.irq
}
