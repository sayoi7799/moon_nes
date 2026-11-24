///|
/// Builds an iNES image where every byte of 16 KiB PRG bank `i` is `i` and
/// every byte of 4 KiB CHR bank `j` is `0x80 + j`.
fn rom(
  mapper : Int32,
  prg_banks : Int32,
  chr_banks : Int32,
  flags6 : Int32,
) -> Bytes {
  let prg = prg_banks * 0x4000
  let chr = chr_banks * 0x2000
  Bytes::makei(16 + prg + chr, i => {
    if i < 16 {
      [
        0x4E,
        0x45,
        0x53,
        0x1A,
        prg_banks,
        chr_banks,
        ((mapper & 0xF) << 4) | flags6,
        mapper & 0xF0,
      ]
      .get(i)
      .unwrap_or(0)
      .to_byte()
    } else if i < 16 + prg {
      ((i - 16) / 0x4000).to_byte()
    } else {
      (0x80 + (i - 16 - prg) / 0x1000).to_byte()
    }
  })
}

///|
fn board(
  mapper : Int32,
  prg_banks : Int32,
  chr_banks : Int32,
) -> &@mapper.Mapper {
  @mapper.create(@cartridge.parse(rom(mapper, prg_banks, chr_banks, 0))) catch {
    e => abort(e.message())
  }
}

///|
test "unsupported mapper is an error, not a crash" {
  let cart = @cartridge.parse(rom(5, 2, 1, 0))
  let r = try {
    @mapper.create(cart) |> ignore
    None
  } catch {
    e => Some(e)
  }
  assert_true(r is Some(UnsupportedMapper(5)))
  assert_false(@mapper.is_supported(5))
  assert_true(@mapper.is_supported(4))
}

///|
test "NROM-128 mirrors PRG and has PRG RAM" {
  let m = board(0, 1, 1)
  assert_eq(m.cpu_read(0x8000), 0)
  assert_eq(m.cpu_read(0xC000), 0)
  m.cpu_write(0x6123, 0x5A, 0L)
  assert_eq(m.cpu_read(0x6123), 0x5A)
  assert_eq(m.cpu_read(0x5000), -1)
  // CHR ROM is read-only.
  m.ppu_write(0x0010, 0x11)
  assert_eq(m.ppu_read(0x0010), 0x80)
}

///|
test "NROM with CHR RAM is writable" {
  let m = board(0, 2, 0)
  assert_eq(m.cpu_read(0xC000), 1)
  m.ppu_write(0x1FFF, 0x42)
  assert_eq(m.ppu_read(0x1FFF), 0x42)
}

///|
test "UxROM switches $8000 and fixes the last bank" {
  let m = board(2, 8, 0)
  assert_eq(m.cpu_read(0xC000), 7)
  m.cpu_write(0x8000, 5, 0L)
  assert_eq(m.cpu_read(0x8000), 5)
  assert_eq(m.cpu_read(0xFFFF), 7)
  // Bank numbers wrap around the ROM size.
  m.cpu_write(0x8000, 9, 0L)
  assert_eq(m.cpu_read(0x8000), 1)
}

///|
test "CNROM switches 8 KiB of CHR" {
  let m = board(3, 2, 4)
  assert_eq(m.ppu_read(0x0000), 0x80)
  m.cpu_write(0x8000, 2, 0L)
  assert_eq(m.ppu_read(0x0000), 0x84)
  assert_eq(m.ppu_read(0x1000), 0x85)
  assert_eq(m.cpu_read(0xC000), 1)
}

///|
/// Writes a 5-bit MMC1 register serially, on non-consecutive cycles.
fn mmc1_write(
  m : &@mapper.Mapper,
  addr : Int32,
  value : Int32,
  cycle : Int64,
) -> Unit {
  for i in 0..<5 {
    m.cpu_write(addr, (value >> i) & 1, cycle + (i * 2).to_int64())
  }
}

///|
test "MMC1 PRG modes" {
  let m = board(1, 8, 2)
  // Power-up: mode 3, last bank fixed at $C000.
  assert_eq(m.cpu_read(0xC000), 7)
  mmc1_write(m, 0xE000, 3, 0L)
  assert_eq(m.cpu_read(0x8000), 3)
  assert_eq(m.cpu_read(0xC000), 7)
  // Mode 2: first bank fixed at $8000, switch $C000.
  mmc1_write(m, 0x8000, 0x08, 100L)
  assert_eq(m.cpu_read(0x8000), 0)
  assert_eq(m.cpu_read(0xC000), 3)
  // Mode 0: 32 KiB switching ignores the low bit.
  mmc1_write(m, 0x8000, 0x00, 200L)
  assert_eq(m.cpu_read(0x8000), 2)
  assert_eq(m.cpu_read(0xC000), 3)
}

///|
test "MMC1 CHR modes and mirroring" {
  let m = board(1, 2, 2)
  // 8 KiB mode: chr0 >> 1 selects the pair.
  mmc1_write(m, 0xA000, 2, 0L)
  assert_eq(m.ppu_read(0x0000), 0x82)
  assert_eq(m.ppu_read(0x1000), 0x83)
  // 4 KiB mode with vertical mirroring.
  mmc1_write(m, 0x8000, 0x12, 100L)
  mmc1_write(m, 0xA000, 3, 200L)
  mmc1_write(m, 0xC000, 1, 300L)
  assert_eq(m.ppu_read(0x0000), 0x83)
  assert_eq(m.ppu_read(0x1000), 0x81)
  assert_eq(m.mirroring().to_string(), "vertical")
  mmc1_write(m, 0x8000, 0x13, 400L)
  assert_eq(m.mirroring().to_string(), "horizontal")
  mmc1_write(m, 0x8000, 0x10, 500L)
  assert_eq(m.mirroring().to_string(), "single-screen low")
}

///|
test "MMC1 reset bit and consecutive-cycle writes" {
  let m = board(1, 8, 0)
  mmc1_write(m, 0x8000, 0x00, 0L) // mode 0
  m.cpu_write(0x8000, 1, 50L) // partial shift...
  m.cpu_write(0x8000, 0x80, 52L) // ...discarded by reset, mode 3 restored
  assert_eq(m.cpu_read(0xC000), 7)
  // The second of two back-to-back writes is ignored.
  m.cpu_write(0xE000, 1, 60L)
  m.cpu_write(0xE000, 0, 61L)
  m.cpu_write(0xE000, 0, 63L)
  m.cpu_write(0xE000, 0, 65L)
  m.cpu_write(0xE000, 0, 67L)
  m.cpu_write(0xE000, 0, 69L)
  assert_eq(m.cpu_read(0x8000), 1)
}
