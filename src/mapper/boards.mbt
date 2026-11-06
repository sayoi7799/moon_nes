///|
/// Mapper 0: no bank switching. 16 KiB PRG is mirrored into $C000.
/// https://www.nesdev.org/wiki/NROM
priv struct Nrom {
  mem : Memory
  mirroring : @cartridge.Mirroring
}

///|
fn Nrom::new(cart : @cartridge.Cartridge) -> &Mapper {
  { mem: Memory::new(cart), mirroring: cart.mirroring, }
}

///|
impl Mapper for Nrom with fn cpu_read(self, addr) {
  if addr >= 0x8000 {
    self.mem.prg_at(0, 0x8000, addr - 0x8000)
  } else {
    self.mem.ram_read(addr)
  }
}

///|
impl Mapper for Nrom with fn cpu_write(self, addr, value, _) {
  self.mem.ram_write(addr, value)
}

///|
impl Mapper for Nrom with fn ppu_read(self, addr) {
  self.mem.chr[addr & 0x1FFF].to_int()
}

///|
impl Mapper for Nrom with fn ppu_write(self, addr, value) {
  self.mem.chr_write(addr & 0x1FFF, value)
}

///|
impl Mapper for Nrom with fn mirroring(self) {
  self.mirroring
}

///|
/// Mapper 2: switchable 16 KiB bank at $8000, last bank fixed at $C000.
/// https://www.nesdev.org/wiki/UxROM
priv struct Uxrom {
  mem : Memory
  mirroring : @cartridge.Mirroring
  mut bank : Int32
}

///|
fn Uxrom::new(cart : @cartridge.Cartridge) -> &Mapper {
  { mem: Memory::new(cart), mirroring: cart.mirroring, bank: 0, }
}

///|
impl Mapper for Uxrom with fn cpu_read(self, addr) {
  if addr >= 0xC000 {
    let last = self.mem.prg.length() / 0x4000 - 1
    self.mem.prg_at(last, 0x4000, addr - 0xC000)
  } else if addr >= 0x8000 {
    self.mem.prg_at(self.bank, 0x4000, addr - 0x8000)
  } else {
    self.mem.ram_read(addr)
  }
}

///|
impl Mapper for Uxrom with fn cpu_write(self, addr, value, _) {
  if addr >= 0x8000 {
    self.bank = value
  } else {
    self.mem.ram_write(addr, value)
  }
}

///|
impl Mapper for Uxrom with fn ppu_read(self, addr) {
  self.mem.chr[addr & 0x1FFF].to_int()
}

///|
impl Mapper for Uxrom with fn ppu_write(self, addr, value) {
  self.mem.chr_write(addr & 0x1FFF, value)
}

///|
impl Mapper for Uxrom with fn mirroring(self) {
  self.mirroring
}

///|
/// Mapper 3: fixed PRG, switchable 8 KiB CHR bank.
/// https://www.nesdev.org/wiki/CNROM
priv struct Cnrom {
  mem : Memory
  mirroring : @cartridge.Mirroring
  mut chr_bank : Int32
}

///|
fn Cnrom::new(cart : @cartridge.Cartridge) -> &Mapper {
  { mem: Memory::new(cart), mirroring: cart.mirroring, chr_bank: 0, }
}

///|
impl Mapper for Cnrom with fn cpu_read(self, addr) {
  if addr >= 0x8000 {
    self.mem.prg_at(0, 0x8000, addr - 0x8000)
  } else {
    self.mem.ram_read(addr)
  }
}

///|
impl Mapper for Cnrom with fn cpu_write(self, addr, value, _) {
  if addr >= 0x8000 {
    self.chr_bank = value
  } else {
    self.mem.ram_write(addr, value)
  }
}

///|
impl Mapper for Cnrom with fn ppu_read(self, addr) {
  self.mem.chr[self.mem.chr_index(self.chr_bank, 0x2000, addr & 0x1FFF)].to_int()
}

///|
impl Mapper for Cnrom with fn ppu_write(self, addr, value) {
  self.mem.chr_write(
    self.mem.chr_index(self.chr_bank, 0x2000, addr & 0x1FFF),
    value,
  )
}

///|
impl Mapper for Cnrom with fn mirroring(self) {
  self.mirroring
}

///|
/// Mapper 1 (MMC1): registers are loaded serially, one bit per write, through
/// a 5-bit shift register. https://www.nesdev.org/wiki/MMC1
priv struct Mmc1 {
  mem : Memory
  mut shift : Int32
  mut shift_count : Int32
  mut control : Int32
  mut chr0 : Int32
  mut chr1 : Int32
  mut prg : Int32
  mut last_write_cycle : Int64
}

///|
fn Mmc1::new(cart : @cartridge.Cartridge) -> &Mapper {
  {
    mem: Memory::new(cart),
    shift: 0,
    shift_count: 0,
    // Power-up state: PRG mode 3 (last bank fixed at $C000).
    control: 0x0C,
    chr0: 0,
    chr1: 0,
    prg: 0,
    last_write_cycle: -2L,
  }
}

///|
/// PRG RAM is disabled by bit 4 of the PRG register (MMC1B), and on SNROM
/// (8 KiB CHR RAM, at most 256 KiB PRG) also by bit 4 of the CHR register.
fn Mmc1::ram_enabled(self : Mmc1) -> Bool {
  if (self.prg & 0x10) != 0 {
    return false
  }
  let snrom = self.mem.chr_writable &&
    self.mem.chr.length() == 0x2000 &&
    self.mem.prg.length() <= 0x40000
  !(snrom && (self.chr0 & 0x10) != 0)
}

///|
/// SUROM and friends use CHR register bit 4 to select a 256 KiB PRG half.
fn Mmc1::prg_outer(self : Mmc1) -> Int32 {
  if self.mem.prg.length() > 0x40000 {
    self.chr0 & 0x10
  } else {
    0
  }
}

///|
impl Mapper for Mmc1 with fn cpu_read(self, addr) {
  if addr < 0x8000 {
    return if self.ram_enabled() { self.mem.ram_read(addr) } else { -1 }
  }
  let outer = self.prg_outer()
  let bank = self.prg & 0x0F
  let offset = addr & 0x3FFF
  let b = match (self.control >> 2) & 3 {
    0 | 1 => (bank & 0x0E) + (if addr >= 0xC000 { 1 } else { 0 })
    2 => if addr >= 0xC000 { bank } else { 0 }
    _ => if addr >= 0xC000 { 0x0F } else { bank }
  }
  self.mem.prg_at(outer | b, 0x4000, offset)
}

///|
impl Mapper for Mmc1 with fn cpu_write(self, addr, value, cycle) {
  if addr < 0x8000 {
    if self.ram_enabled() {
      self.mem.ram_write(addr, value)
    }
    return
  }
  // The MMC1 ignores a write on the cycle right after another one, which is
  // what read-modify-write instructions do with their dummy write.
  let consecutive = cycle == self.last_write_cycle + 1L
  self.last_write_cycle = cycle
  if consecutive {
    return
  }
  if (value & 0x80) != 0 {
    self.shift = 0
    self.shift_count = 0
    self.control = self.control | 0x0C
    return
  }
  self.shift = self.shift | ((value & 1) << self.shift_count)
  self.shift_count += 1
  if self.shift_count < 5 {
    return
  }
  let data = self.shift
  self.shift = 0
  self.shift_count = 0
  match (addr >> 13) & 3 {
    0 => self.control = data
    1 => self.chr0 = data
    2 => self.chr1 = data
    _ => self.prg = data
  }
}

///|
fn Mmc1::chr_index(self : Mmc1, addr : Int32) -> Int32 {
  let a = addr & 0x1FFF
  if (self.control & 0x10) == 0 {
    self.mem.chr_index(self.chr0 >> 1, 0x2000, a)
  } else if a < 0x1000 {
    self.mem.chr_index(self.chr0, 0x1000, a)
  } else {
    self.mem.chr_index(self.chr1, 0x1000, a - 0x1000)
  }
}

///|
impl Mapper for Mmc1 with fn ppu_read(self, addr) {
  self.mem.chr[self.chr_index(addr)].to_int()
}

///|
impl Mapper for Mmc1 with fn ppu_write(self, addr, value) {
  self.mem.chr_write(self.chr_index(addr), value)
}

///|
impl Mapper for Mmc1 with fn mirroring(self) {
  match self.control & 3 {
    0 => SingleLow
    1 => SingleHigh
    2 => Vertical
    _ => Horizontal
  }
}
