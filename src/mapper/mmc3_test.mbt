///|
/// An MMC3 image with 128 KiB PRG (16 banks of 8 KiB, each filled with its
/// bank number) and 128 KiB CHR ROM (128 banks of 1 KiB, likewise).
/// `submapper` >= 0 makes it a NES 2.0 image with that submapper.
fn mmc3(submapper~ : Int32 = -1, flags6~ : Int32 = 0) -> &@mapper.Mapper {
  let prg = 0x20000
  let chr = 0x20000
  let nes2 = submapper >= 0
  let header = [
    0x4E,
    0x45,
    0x53,
    0x1A,
    prg / 0x4000,
    chr / 0x2000,
    0x40 | flags6,
    if nes2 {
      0x08
    } else {
      0
    },
    if nes2 {
      submapper << 4
    } else {
      0
    },
  ]
  let image = Bytes::makei(16 + prg + chr, i => {
    if i < 16 {
      header.get(i).unwrap_or(0).to_byte()
    } else if i < 16 + prg {
      ((i - 16) / 0x2000).to_byte()
    } else {
      ((i - 16 - prg) / 0x400).to_byte()
    }
  })
  @mapper.create(@cartridge.parse(image)) catch {
    e => abort(e.message())
  }
}

///|
fn set_bank(
  m : &@mapper.Mapper,
  select : Int32,
  reg : Int32,
  bank : Int32,
) -> Unit {
  m.cpu_write(0x8000, select | reg, 0L)
  m.cpu_write(0x8001, bank, 0L)
}

///|
test "MMC3 PRG banks in both modes" {
  let m = mmc3()
  set_bank(m, 0x00, 6, 3)
  set_bank(m, 0x00, 7, 5)
  assert_eq(
    [
      m.cpu_read(0x8000),
      m.cpu_read(0xA000),
      m.cpu_read(0xC000),
      m.cpu_read(0xE000),
    ],
    [3, 5, 14, 15],
  )
  // PRG mode 1 swaps $8000 and $C000.
  m.cpu_write(0x8000, 0x40, 0L)
  assert_eq(
    [
      m.cpu_read(0x8000),
      m.cpu_read(0xA000),
      m.cpu_read(0xC000),
      m.cpu_read(0xE000),
    ],
    [14, 5, 3, 15],
  )
  // The registers are mirrored over each 8 KiB range by A0 alone.
  m.cpu_write(0x9FFE, 0x47, 0L)
  m.cpu_write(0x9FFF, 9, 0L)
  assert_eq(m.cpu_read(0xA000), 9)
}

///|
test "MMC3 CHR banks, with and without A12 inversion" {
  let m = mmc3()
  for reg, bank in [10, 21, 40, 41, 42, 43] {
    set_bank(m, 0, reg, bank)
  }
  let banks = () => Array::makei(8, i => m.ppu_read(i * 0x400))
  // R0 and R1 are 2 KiB banks; their low bit is ignored.
  assert_eq(banks(), [10, 11, 20, 21, 40, 41, 42, 43])
  m.cpu_write(0x8000, 0x80, 0L)
  assert_eq(banks(), [40, 41, 42, 43, 10, 11, 20, 21])
}

///|
test "MMC3 mirroring control, and four-screen boards ignore it" {
  let m = mmc3()
  m.cpu_write(0xA000, 0, 0L)
  assert_true(m.mirroring() is Vertical)
  m.cpu_write(0xA000, 1, 0L)
  assert_true(m.mirroring() is Horizontal)
  let four = mmc3(flags6=0x08)
  four.cpu_write(0xA000, 1, 0L)
  assert_true(four.mirroring() is FourScreen)
}

///|
test "MMC3 PRG RAM enable and write protect" {
  let m = mmc3()
  m.cpu_write(0x6000, 0x12, 0L)
  assert_eq(m.cpu_read(0x6000), 0x12)
  m.cpu_write(0xA001, 0xC0, 0L) // enabled, write protected
  m.cpu_write(0x6000, 0x34, 0L)
  assert_eq(m.cpu_read(0x6000), 0x12)
  m.cpu_write(0xA001, 0x00, 0L) // disabled: open bus
  assert_eq(m.cpu_read(0x6000), -1)
  m.cpu_write(0xA001, 0x80, 0L)
  m.cpu_write(0x6000, 0x56, 0L)
  assert_eq(m.cpu_read(0x6000), 0x56)
}

///|
/// Drives one well-separated A12 rise at dot `t`.
fn rise(m : &@mapper.Mapper, t : Int64) -> Unit {
  m.ppu_bus(0x0FF0, t)
  m.ppu_bus(0x1FF0, t + 20L)
}

///|
test "MMC3 counter reloads, counts down and raises the IRQ at 0" {
  let m = mmc3()
  m.cpu_write(0xC000, 2, 0L) // latch
  m.cpu_write(0xC001, 0, 0L) // reload on the next clock
  m.cpu_write(0xE001, 0, 0L) // enable
  let mut t = 0L
  let lines = []
  for _ in 0..<6 {
    t += 100L
    rise(m, t)
    lines.push(m.irq_line())
    if m.irq_line() {
      m.cpu_write(0xE000, 0, 0L) // acknowledge
      m.cpu_write(0xE001, 0, 0L)
    }
  }
  // Reload to 2, 1, 0 (IRQ), reload to 2, 1, 0 (IRQ).
  assert_eq(lines, [false, false, true, false, false, true])
}

///|
test "MMC3 ignores A12 rises after a short low period" {
  let m = mmc3()
  m.cpu_write(0xC000, 1, 0L)
  m.cpu_write(0xC001, 0, 0L)
  m.cpu_write(0xE001, 0, 0L)
  rise(m, 100L) // reload to 1
  // Low for only 4 dots, like the gaps between sprite fetches.
  m.ppu_bus(0x0000, 200L)
  m.ppu_bus(0x1000, 204L)
  assert_false(m.irq_line())
  rise(m, 300L) // 1 -> 0
  assert_true(m.irq_line())
}

///|
test "MMC3 with latch 0: IRQ every clock (MMC3B/C) or once (MMC3A)" {
  let count = (m : &@mapper.Mapper) => {
    m.cpu_write(0xC000, 0, 0L)
    m.cpu_write(0xC001, 0, 0L)
    m.cpu_write(0xE001, 0, 0L)
    let mut irqs = 0
    for i in 0..<4 {
      rise(m, (i + 1).to_int64() * 100L)
      if m.irq_line() {
        irqs += 1
        m.cpu_write(0xE000, 0, 0L)
        m.cpu_write(0xE001, 0, 0L)
      }
    }
    irqs
  }
  assert_eq(count(mmc3()), 4)
  assert_eq(count(mmc3(submapper=4)), 1)
}
