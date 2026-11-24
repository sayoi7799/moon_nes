// Cartridge boards. A mapper decides what the CPU sees at $4020-$FFFF and
// what the PPU sees at $0000-$1FFF, and which nametable mirroring is active.
// Reference: https://www.nesdev.org/wiki/Mapper

///|
pub(open) trait Mapper {
  /// CPU read in $4020-$FFFF. Returns -1 for open bus (nothing drives it).
  fn cpu_read(Self, Int32) -> Int32
  /// CPU write in $4020-$FFFF. `cycle` is the CPU cycle of the write, so
  /// boards that react to write timing (MMC1) can see consecutive writes.
  fn cpu_write(Self, Int32, Int32, Int64) -> Unit
  /// PPU pattern table read, $0000-$1FFF.
  fn ppu_read(Self, Int32) -> Int32
  fn ppu_write(Self, Int32, Int32) -> Unit
  fn mirroring(Self) -> @cartridge.Mirroring
  /// Address the PPU puts on its bus, at PPU dot `dot` (a running count).
  /// Called for every pattern table fetch ($0000-$1FFF; other fetches have
  /// A12 low) and whenever $2006/$2007 move the VRAM address. Boards that
  /// watch the address lines (MMC3 counts rises of A12) override it.
  fn ppu_bus(Self, addr : Int32, dot : Int64) -> Unit = _
  /// IRQ output of the board (true = asserted).
  fn irq_line(Self) -> Bool = _
}

///|
impl Mapper with fn ppu_bus(_, _, _) {
  ()
}

///|
impl Mapper with fn irq_line(_) {
  false
}

///|
/// Picks the board implementation for a parsed cartridge.
pub fn create(cart : @cartridge.Cartridge) -> &Mapper raise @cartridge.RomError {
  match cart.mapper_id {
    0 => Nrom::new(cart)
    1 => Mmc1::new(cart)
    2 => Uxrom::new(cart)
    3 => Cnrom::new(cart)
    4 => Mmc3::new(cart)
    id => raise @cartridge.UnsupportedMapper(id)
  }
}

///|
pub fn is_supported(mapper_id : Int32) -> Bool {
  mapper_id >= 0 && mapper_id <= 4
}

///|
/// Banked memory shared by every board: PRG ROM, CHR ROM/RAM and PRG RAM.
priv struct Memory {
  prg : FixedArray[Byte]
  chr : FixedArray[Byte]
  chr_writable : Bool
  prg_ram : FixedArray[Byte]
}

///|
fn Memory::new(cart : @cartridge.Cartridge) -> Memory {
  let ram_size = if cart.prg_ram_size > 0 { cart.prg_ram_size } else { 8192 }
  {
    prg: cart.prg_rom,
    chr: cart.chr,
    chr_writable: cart.chr_is_ram,
    prg_ram: FixedArray::make(ram_size, b'\x00'),
  }
}

///|
/// Reads PRG ROM through a bank of `bank_size` bytes; bank numbers wrap
/// around the ROM size, as on boards with fewer address lines.
#inline
fn Memory::prg_at(
  self : Memory,
  bank : Int32,
  bank_size : Int32,
  offset : Int32,
) -> Int32 {
  let banks = self.prg.length() / bank_size
  let b = if banks == 0 { 0 } else { bank % banks }
  self.prg[(b * bank_size + offset) % self.prg.length()].to_int()
}

///|
#inline
fn Memory::chr_index(
  self : Memory,
  bank : Int32,
  bank_size : Int32,
  offset : Int32,
) -> Int32 {
  let banks = self.chr.length() / bank_size
  let b = if banks == 0 { 0 } else { bank % banks }
  (b * bank_size + offset) % self.chr.length()
}

///|
fn Memory::ram_read(self : Memory, addr : Int32) -> Int32 {
  if addr >= 0x6000 {
    self.prg_ram[(addr - 0x6000) % self.prg_ram.length()].to_int()
  } else {
    -1
  }
}

///|
fn Memory::ram_write(self : Memory, addr : Int32, value : Int32) -> Unit {
  if addr >= 0x6000 && addr < 0x8000 {
    self.prg_ram[(addr - 0x6000) % self.prg_ram.length()] = value.to_byte()
  }
}

///|
fn Memory::chr_write(self : Memory, index : Int32, value : Int32) -> Unit {
  if self.chr_writable {
    self.chr[index] = value.to_byte()
  }
}
