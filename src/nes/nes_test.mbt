///|
fn header(
  prg_banks : Int32,
  chr_banks : Int32,
  flags6 : Int32,
  flags7 : Int32,
) -> Bytes {
  let size = 16 + prg_banks * 16384 + chr_banks * 8192
  Bytes::makei(size, i => {
    match i {
      0 => b'N'
      1 => b'E'
      2 => b'S'
      3 => b'\x1A'
      4 => prg_banks.to_byte()
      5 => chr_banks.to_byte()
      6 => flags6.to_byte()
      7 => flags7.to_byte()
      _ => b'\x00'
    }
  })
}

///|
fn load_error(data : Bytes) -> @cartridge.RomError? {
  try {
    @nes.Nes::load_rom(data) |> ignore
    None
  } catch {
    e => Some(e)
  }
}

///|
test "load_rom rejects unsupported mappers with an error" {
  // Mapper 5 (MMC5): low nibble 5 in flags 6.
  let e = load_error(header(2, 1, 0x50, 0x00))
  assert_true(e is Some(UnsupportedMapper(5)))
  match e {
    Some(err) => assert_eq(err.message(), "mapper 5 is not supported")
    None => fail("expected an error")
  }
  // A NES 2.0 mapper number above 255.
  let data = header(2, 1, 0x00, 0x08).to_array()
  data[8] = b'\x01'
  assert_true(
    load_error(Bytes::from_array(data)) is Some(UnsupportedMapper(256)),
  )
}

///|
test "load_rom rejects truncated and non-iNES files" {
  let full = header(2, 1, 0, 0)
  let cut = Bytes::from_array(full.to_array()[:1000])
  assert_true(load_error(cut) is Some(Truncated(section="PRG ROM", ..)))
  assert_true(load_error(b"") is Some(TooShort(0)))
  assert_true(load_error(b"GIF89a, definitely not a ROM") is Some(BadMagic))
}

///|
test "a minimal NROM image boots and runs frames" {
  // PRG filled with zero (BRK) except vectors pointing at a JMP * loop.
  let data = header(1, 1, 0, 0).to_array()
  let prg = 16
  // $C000: JMP $C000
  data[prg] = b'\x4C'
  data[prg + 1] = b'\x00'
  data[prg + 2] = b'\xC0'
  // Reset vector at $FFFC -> $C000 (16 KiB mirrored, offset $3FFC).
  data[prg + 0x3FFC] = b'\x00'
  data[prg + 0x3FFD] = b'\xC0'
  let nes = @nes.Nes::load_rom(Bytes::from_array(data))
  for _ in 0..<3 {
    nes.run_frame()
  }
  assert_eq(nes.frame_count(), 2)
  assert_eq(nes.cpu.pc & 0xFFF0, 0xC000)
  assert_eq(nes.frame_buffer().length(), 256 * 240)
  let rgba = FixedArray::make(256 * 240 * 4, b'\x00')
  nes.write_rgba(rgba)
  assert_eq(rgba[3], b'\xFF')
}
