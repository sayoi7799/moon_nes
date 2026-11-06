// iNES / NES 2.0 file parsing.
// Reference: https://www.nesdev.org/wiki/INES and https://www.nesdev.org/wiki/NES_2.0

///|
/// Nametable mirroring arrangement selected by the cartridge.
pub(all) enum Mirroring {
  Horizontal
  Vertical
  SingleLow
  SingleHigh
  FourScreen
}

///|
pub fn Mirroring::to_string(self : Mirroring) -> String {
  match self {
    Horizontal => "horizontal"
    Vertical => "vertical"
    SingleLow => "single-screen low"
    SingleHigh => "single-screen high"
    FourScreen => "four-screen"
  }
}

///|
/// Every way loading a ROM image can fail. Parsing never aborts the program.
pub(all) suberror RomError {
  TooShort(Int32)
  BadMagic
  Truncated(section~ : String, expected~ : Int32, actual~ : Int32)
  NoPrgRom
  UnsupportedMapper(Int32)
}

///|
pub fn RomError::message(self : RomError) -> String {
  match self {
    TooShort(n) => "file is \{n} bytes, smaller than the 16-byte iNES header"
    BadMagic => "missing \"NES\\x1A\" signature, not an iNES file"
    Truncated(section~, expected~, actual~) =>
      "file truncated in \{section}: needs \{expected} bytes, only \{actual} available"
    NoPrgRom => "header declares zero bytes of PRG ROM"
    UnsupportedMapper(id) => "mapper \{id} is not supported"
  }
}

///|
pub struct Cartridge {
  mapper_id : Int32
  submapper : Int32
  is_nes2 : Bool
  prg_rom : FixedArray[Byte]
  /// CHR ROM contents, or zero-filled CHR RAM when `chr_is_ram`.
  chr : FixedArray[Byte]
  chr_is_ram : Bool
  prg_ram_size : Int32
  mirroring : Mirroring
  has_battery : Bool
  trainer : FixedArray[Byte]?
}

///|
let header_size = 16

///|
let trainer_size = 512

///|
/// NES 2.0 ROM size: a 12-bit unit count, or exponent-multiplier form when
/// the high nibble is $F (size = 2^E * (M*2+1)).
fn nes2_rom_size(lsb : Int32, msb : Int32, unit : Int32) -> Int32 {
  if msb == 0xF {
    let exponent = lsb >> 2
    let multiplier = (lsb & 3) * 2 + 1
    (1 << exponent) * multiplier
  } else {
    ((msb << 8) | lsb) * unit
  }
}

///|
/// NES 2.0 RAM size nibble: 0 means none, otherwise 64 << n bytes.
fn nes2_ram_size(shift : Int32) -> Int32 {
  if shift == 0 {
    0
  } else {
    64 << shift
  }
}

///|
fn slice(
  data : Bytes,
  offset : Int32,
  len : Int32,
  section : String,
) -> FixedArray[Byte] raise RomError {
  let available = data.length() - offset
  if available < len {
    raise Truncated(
      section~,
      expected=len,
      actual=if available < 0 { 0 } else { available },
    )
  }
  let out = FixedArray::make(len, b'\x00')
  out.blit_from_bytes(0, data, offset, len)
  out
}

///|
/// Parses an iNES or NES 2.0 image. The mapper number is reported as-is;
/// whether it is supported is decided by the mapper package.
pub fn parse(data : Bytes) -> Cartridge raise RomError {
  if data.length() < header_size {
    raise TooShort(data.length())
  }
  if data[0] != b'N' || data[1] != b'E' || data[2] != b'S' || data[3] != b'\x1A' {
    raise BadMagic
  }
  let h = FixedArray::makei(header_size, i => data[i].to_int())
  let flags6 = h[6]
  let flags7 = h[7]
  let is_nes2 = (flags7 & 0x0C) == 0x08
  // Old dumps sometimes carry "DiskDude!" garbage in bytes 7-15; if the tail
  // of a plain iNES header is dirty, the high mapper nibble is not trustworthy.
  let dirty_tail = !is_nes2 && (h[12] | h[13] | h[14] | h[15]) != 0
  let mapper_low = flags6 >> 4
  let mapper_high = if dirty_tail { 0 } else { flags7 & 0xF0 }
  let mut mapper_id = mapper_high | mapper_low
  let mut submapper = 0
  let mut prg_size = h[4] * 16384
  let mut chr_size = h[5] * 8192
  let mut prg_ram_size = 8192
  let mut chr_ram_size = 8192
  if is_nes2 {
    mapper_id = mapper_id | ((h[8] & 0x0F) << 8)
    submapper = h[8] >> 4
    prg_size = nes2_rom_size(h[4], h[9] & 0x0F, 16384)
    chr_size = nes2_rom_size(h[5], h[9] >> 4, 8192)
    prg_ram_size = nes2_ram_size(h[10] & 0x0F) + nes2_ram_size(h[10] >> 4)
    chr_ram_size = nes2_ram_size(h[11] & 0x0F) + nes2_ram_size(h[11] >> 4)
  } else if !dirty_tail && h[8] != 0 {
    prg_ram_size = h[8] * 8192
  }
  if prg_size == 0 {
    raise NoPrgRom
  }
  let mut offset = header_size
  let trainer = if (flags6 & 0x04) != 0 {
    let t = slice(data, offset, trainer_size, "trainer")
    offset += trainer_size
    Some(t)
  } else {
    None
  }
  let prg_rom = slice(data, offset, prg_size, "PRG ROM")
  offset += prg_size
  let chr_is_ram = chr_size == 0
  let chr = if chr_is_ram {
    // Boards with CHR RAM always have at least 8 KiB of it in practice.
    let size = if chr_ram_size < 8192 { 8192 } else { chr_ram_size }
    FixedArray::make(size, b'\x00')
  } else {
    slice(data, offset, chr_size, "CHR ROM")
  }
  let mirroring = if (flags6 & 0x08) != 0 {
    FourScreen
  } else if (flags6 & 0x01) != 0 {
    Vertical
  } else {
    Horizontal
  }
  {
    mapper_id,
    submapper,
    is_nes2,
    prg_rom,
    chr,
    chr_is_ram,
    prg_ram_size,
    mirroring,
    has_battery: (flags6 & 0x02) != 0,
    trainer,
  }
}
