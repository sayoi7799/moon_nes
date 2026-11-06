///|
/// Builds an image: 16-byte header followed by `body_len` filler bytes.
fn image(header : Array[Int32], body_len : Int32) -> Bytes {
  let h = header.copy()
  while h.length() < 16 {
    h.push(0)
  }
  Bytes::makei(16 + body_len, i => {
    if i < 16 {
      h[i].to_byte()
    } else {
      (i & 0xFF).to_byte()
    }
  })
}

///|
fn parse_err(data : Bytes) -> @cartridge.RomError? {
  try {
    @cartridge.parse(data) |> ignore
    None
  } catch {
    e => Some(e)
  }
}

///|
test "plain iNES NROM-256 with CHR ROM" {
  let cart = @cartridge.parse(
    image([0x4E, 0x45, 0x53, 0x1A, 2, 1, 0x01, 0x00], 32768 + 8192),
  )
  assert_eq(cart.mapper_id, 0)
  assert_false(cart.is_nes2)
  assert_eq(cart.prg_rom.length(), 32768)
  assert_eq(cart.chr.length(), 8192)
  assert_false(cart.chr_is_ram)
  assert_eq(cart.mirroring.to_string(), "vertical")
  assert_eq(cart.prg_ram_size, 8192)
  // PRG data starts right after the header.
  assert_eq(cart.prg_rom[0].to_int(), 16)
  assert_eq(cart.chr[0].to_int(), (16 + 32768) & 0xFF)
}

///|
test "mapper number, battery, trainer and CHR RAM" {
  // Mapper 0x12 = low nibble 2 (flags6) | high nibble 1 (flags7).
  let cart = @cartridge.parse(
    image([0x4E, 0x45, 0x53, 0x1A, 1, 0, 0x26, 0x10], 512 + 16384),
  )
  assert_eq(cart.mapper_id, 0x12)
  assert_true(cart.has_battery)
  assert_true(cart.trainer is Some(_))
  assert_true(cart.chr_is_ram)
  assert_eq(cart.chr.length(), 8192)
  assert_eq(cart.mirroring.to_string(), "horizontal")
  // PRG starts after header + trainer.
  assert_eq(cart.prg_rom[0].to_int(), (16 + 512) & 0xFF)
}

///|
test "four-screen flag wins over the mirroring bit" {
  let cart = @cartridge.parse(
    image([0x4E, 0x45, 0x53, 0x1A, 1, 1, 0x09], 16384 + 8192),
  )
  assert_eq(cart.mirroring.to_string(), "four-screen")
}

///|
test "NES 2.0 header" {
  // flags7 = 0x18: NES 2.0 marker, mapper high nibble 1.
  // byte8 = 0x31: submapper 3, mapper bits 8-11 = 1 -> mapper 0x113.
  // byte10 = 0x07: 64 << 7 = 8 KiB PRG RAM. byte11 = 0x09: 32 KiB CHR RAM.
  let cart = @cartridge.parse(
    image(
      [0x4E, 0x45, 0x53, 0x1A, 2, 0, 0x30, 0x18, 0x31, 0, 0x07, 0x09],
      32768,
    ),
  )
  assert_true(cart.is_nes2)
  assert_eq(cart.mapper_id, 0x113)
  assert_eq(cart.submapper, 3)
  assert_eq(cart.prg_ram_size, 8192)
  assert_eq(cart.chr.length(), 32768)
}

///|
test "NES 2.0 exponent-multiplier size" {
  // byte4 = 0x0E: E = 3, M = 2 -> 2^3 * 5 = 40 bytes; byte9 low nibble $F.
  let cart = @cartridge.parse(
    image([0x4E, 0x45, 0x53, 0x1A, 0x0E, 0, 0, 0x08, 0, 0x0F], 40),
  )
  assert_eq(cart.prg_rom.length(), 40)
}

///|
test "DiskDude garbage in the header tail ignores the high mapper nibble" {
  let header = [0x4E, 0x45, 0x53, 0x1A, 1, 1, 0x10, 0x44]
  for c in "isk".iter() {
    header.push(c.to_int())
  }
  header.push(0x44)
  header.push(0x75)
  let cart = @cartridge.parse(image(header, 16384 + 8192))
  assert_eq(cart.mapper_id, 1)
}

///|
test "empty and short files" {
  assert_true(parse_err(b"") is Some(TooShort(0)))
  assert_true(parse_err(b"NES\x1a") is Some(TooShort(4)))
}

///|
test "bad signature" {
  assert_true(
    parse_err(image([0x4E, 0x45, 0x53, 0x00, 1], 16384)) is Some(BadMagic),
  )
}

///|
test "truncated PRG, CHR and trainer" {
  let e = parse_err(image([0x4E, 0x45, 0x53, 0x1A, 2, 0], 20000))
  assert_true(
    e is Some(Truncated(section="PRG ROM", expected=32768, actual=20000)),
  )
  let e = parse_err(image([0x4E, 0x45, 0x53, 0x1A, 1, 1], 16384 + 100))
  assert_true(
    e is Some(Truncated(section="CHR ROM", expected=8192, actual=100)),
  )
  let e = parse_err(image([0x4E, 0x45, 0x53, 0x1A, 1, 0, 0x04], 10))
  assert_true(e is Some(Truncated(section="trainer", ..)))
}

///|
test "zero PRG ROM" {
  assert_true(
    parse_err(image([0x4E, 0x45, 0x53, 0x1A, 0, 1], 8192)) is Some(NoPrgRom),
  )
}

///|
test "error messages are human readable" {
  match parse_err(b"hello world, not a rom") {
    Some(e) =>
      assert_eq(e.message(), "missing \"NES\\x1A\" signature, not an iNES file")
    None => fail("expected an error")
  }
}
