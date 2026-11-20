// The list of community test ROMs this emulator is checked against.

///|
pub(all) enum Protocol {
  /// Result at $6000 with the DE B0 61 signature.
  Blargg
  /// Result code in zero page ($F8 in the 2005.10 tests, $F0 in the
  /// 2005.09 ones), CPU parked in `JMP *`.
  Legacy(Int32)
  /// Verdict printed on screen only.
  Screen
  /// The test prints a CRC of its output on screen, and its source lists
  /// the CRCs seen on hardware. Passes if one of them appears.
  ScreenCrc(Array[String])
  /// Holy Mapperel: the 4-digit detail code on screen must be 0000 and the
  /// detected mapper must be the given one.
  Mapperel(Int32)
}

///|
pub struct SuiteRom {
  path : String
  area : String
  protocol : Protocol
  frames : Int32
}

///|
fn rom(
  path : String,
  area : String,
  protocol~ : Protocol = Blargg,
  frames~ : Int32 = 3000,
) -> SuiteRom {
  { path, area, protocol, frames, }
}

///|
/// Every test ROM that reports a result automatically, with paths relative
/// to test-roms/. `downloaded/` holds ROMs fetched by
/// scripts/fetch-test-roms.sh; `holy-mapperel/` is committed (zlib license).
pub let test_suite : Array[SuiteRom] = [
  rom("downloaded/instr_test-v5/rom_singles/01-basics.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/02-implied.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/03-immediate.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/04-zero_page.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/05-zp_xy.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/06-absolute.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/07-abs_xy.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/08-ind_x.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/09-ind_y.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/10-branches.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/11-stack.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/12-jmp_jsr.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/13-rts.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/14-rti.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/15-brk.nes", "CPU"),
  rom("downloaded/instr_test-v5/rom_singles/16-special.nes", "CPU"),
  rom("downloaded/instr_timing/rom_singles/1-instr_timing.nes", "CPU"),
  rom("downloaded/instr_timing/rom_singles/2-branch_timing.nes", "CPU"),
  rom("downloaded/instr_misc/rom_singles/01-abs_x_wrap.nes", "CPU"),
  rom("downloaded/instr_misc/rom_singles/02-branch_wrap.nes", "CPU"),
  rom("downloaded/instr_misc/rom_singles/03-dummy_reads.nes", "CPU"),
  rom("downloaded/instr_misc/rom_singles/04-dummy_reads_apu.nes", "CPU"),
  rom("downloaded/cpu_dummy_reads/cpu_dummy_reads.nes", "CPU", protocol=Screen),
  rom("downloaded/cpu_interrupts_v2/rom_singles/1-cli_latency.nes", "CPU"),
  rom("downloaded/cpu_interrupts_v2/rom_singles/2-nmi_and_brk.nes", "CPU"),
  rom("downloaded/cpu_interrupts_v2/rom_singles/3-nmi_and_irq.nes", "CPU"),
  rom("downloaded/cpu_interrupts_v2/rom_singles/4-irq_and_dma.nes", "CPU"),
  rom("downloaded/cpu_interrupts_v2/rom_singles/5-branch_delays_irq.nes", "CPU"),
  rom("downloaded/ppu_vbl_nmi/rom_singles/01-vbl_basics.nes", "PPU"),
  rom("downloaded/ppu_vbl_nmi/rom_singles/02-vbl_set_time.nes", "PPU"),
  rom("downloaded/ppu_vbl_nmi/rom_singles/03-vbl_clear_time.nes", "PPU"),
  rom("downloaded/ppu_vbl_nmi/rom_singles/04-nmi_control.nes", "PPU"),
  rom("downloaded/ppu_vbl_nmi/rom_singles/05-nmi_timing.nes", "PPU"),
  rom("downloaded/ppu_vbl_nmi/rom_singles/06-suppression.nes", "PPU"),
  rom("downloaded/ppu_vbl_nmi/rom_singles/07-nmi_on_timing.nes", "PPU"),
  rom("downloaded/ppu_vbl_nmi/rom_singles/08-nmi_off_timing.nes", "PPU"),
  rom("downloaded/ppu_vbl_nmi/rom_singles/09-even_odd_frames.nes", "PPU"),
  rom("downloaded/ppu_vbl_nmi/rom_singles/10-even_odd_timing.nes", "PPU"),
  rom(
    "downloaded/sprite_hit_tests_2005.10.05/01.basics.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_hit_tests_2005.10.05/02.alignment.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_hit_tests_2005.10.05/03.corners.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_hit_tests_2005.10.05/04.flip.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_hit_tests_2005.10.05/05.left_clip.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_hit_tests_2005.10.05/06.right_edge.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_hit_tests_2005.10.05/07.screen_bottom.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_hit_tests_2005.10.05/08.double_height.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_hit_tests_2005.10.05/09.timing_basics.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_hit_tests_2005.10.05/10.timing_order.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_hit_tests_2005.10.05/11.edge_timing.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_overflow_tests/1.Basics.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_overflow_tests/2.Details.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_overflow_tests/3.Timing.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_overflow_tests/4.Obscure.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/sprite_overflow_tests/5.Emulator.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "downloaded/blargg_ppu_tests_2005.09.15b/palette_ram.nes",
    "PPU",
    protocol=Legacy(0xF0),
  ),
  rom(
    "downloaded/blargg_ppu_tests_2005.09.15b/power_up_palette.nes",
    "PPU",
    protocol=Legacy(0xF0),
  ),
  rom(
    "downloaded/blargg_ppu_tests_2005.09.15b/sprite_ram.nes",
    "PPU",
    protocol=Legacy(0xF0),
  ),
  rom(
    "downloaded/blargg_ppu_tests_2005.09.15b/vbl_clear_time.nes",
    "PPU",
    protocol=Legacy(0xF0),
  ),
  rom(
    "downloaded/blargg_ppu_tests_2005.09.15b/vram_access.nes",
    "PPU",
    protocol=Legacy(0xF0),
  ),
  rom("downloaded/oam_read/oam_read.nes", "PPU"),
  rom("holy-mapperel/M0_P32K_C8K_V.nes", "Mapper", protocol=Mapperel(0)),
  rom("holy-mapperel/M0_P32K_CR8K_V.nes", "Mapper", protocol=Mapperel(0)),
  rom("holy-mapperel/M1_P128K_C32K.nes", "Mapper", protocol=Mapperel(1)),
  rom("holy-mapperel/M1_P128K_CR8K.nes", "Mapper", protocol=Mapperel(1)),
  rom("holy-mapperel/M1_P512K_CR8K_S8K.nes", "Mapper", protocol=Mapperel(1)),
  rom("holy-mapperel/M2_P128K_V.nes", "Mapper", protocol=Mapperel(2)),
  rom("holy-mapperel/M2_P128K_CR8K_V.nes", "Mapper", protocol=Mapperel(2)),
  rom("holy-mapperel/M3_P32K_C32K_H.nes", "Mapper", protocol=Mapperel(3)),
  rom("downloaded/ppu_open_bus/ppu_open_bus.nes", "PPU"),
  rom("downloaded/apu_test/rom_singles/7-dmc_basics.nes", "APU"),
  rom("downloaded/apu_test/rom_singles/8-dmc_rates.nes", "APU"),
  rom(
    "downloaded/dmc_dma_during_read4/dma_2007_read.nes",
    "APU",
    protocol=ScreenCrc(["159A7A8F", "5E3DF9C4"]),
  ),
  rom(
    "downloaded/dmc_dma_during_read4/dma_2007_write.nes",
    "APU",
    protocol=Screen,
  ),
  rom(
    "downloaded/dmc_dma_during_read4/dma_4016_read.nes",
    "APU",
    protocol=Screen,
  ),
  rom(
    "downloaded/dmc_dma_during_read4/double_2007_read.nes",
    "APU",
    protocol=ScreenCrc(["85CFD627", "F018C287", "440EF923", "E52F41A5"]),
  ),
  rom(
    "downloaded/dmc_dma_during_read4/read_write_2007.nes",
    "APU",
    protocol=Screen,
  ),
]

///|
pub fn Nes::run_suite_rom(self : Nes, rom : SuiteRom) -> TestOutcome {
  match rom.protocol {
    Blargg => self.run_blargg_test(rom.frames)
    Legacy(addr) => self.run_legacy_test(rom.frames, result_addr=addr)
    Screen => self.run_screen_test(rom.frames)
    ScreenCrc(crcs) => self.run_screen_crc_test(rom.frames, crcs)
    Mapperel(id) => self.run_mapperel_test(rom.frames, id)
  }
}
