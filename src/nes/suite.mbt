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
/// Every ROM fetched by scripts/fetch-test-roms.sh that reports a result
/// automatically, with paths relative to test-roms/downloaded/.
pub let test_suite : Array[SuiteRom] = [
  rom("instr_test-v5/rom_singles/01-basics.nes", "CPU"),
  rom("instr_test-v5/rom_singles/02-implied.nes", "CPU"),
  rom("instr_test-v5/rom_singles/03-immediate.nes", "CPU"),
  rom("instr_test-v5/rom_singles/04-zero_page.nes", "CPU"),
  rom("instr_test-v5/rom_singles/05-zp_xy.nes", "CPU"),
  rom("instr_test-v5/rom_singles/06-absolute.nes", "CPU"),
  rom("instr_test-v5/rom_singles/07-abs_xy.nes", "CPU"),
  rom("instr_test-v5/rom_singles/08-ind_x.nes", "CPU"),
  rom("instr_test-v5/rom_singles/09-ind_y.nes", "CPU"),
  rom("instr_test-v5/rom_singles/10-branches.nes", "CPU"),
  rom("instr_test-v5/rom_singles/11-stack.nes", "CPU"),
  rom("instr_test-v5/rom_singles/12-jmp_jsr.nes", "CPU"),
  rom("instr_test-v5/rom_singles/13-rts.nes", "CPU"),
  rom("instr_test-v5/rom_singles/14-rti.nes", "CPU"),
  rom("instr_test-v5/rom_singles/15-brk.nes", "CPU"),
  rom("instr_test-v5/rom_singles/16-special.nes", "CPU"),
  rom("instr_timing/rom_singles/1-instr_timing.nes", "CPU"),
  rom("instr_timing/rom_singles/2-branch_timing.nes", "CPU"),
  rom("instr_misc/rom_singles/01-abs_x_wrap.nes", "CPU"),
  rom("instr_misc/rom_singles/02-branch_wrap.nes", "CPU"),
  rom("instr_misc/rom_singles/03-dummy_reads.nes", "CPU"),
  rom("instr_misc/rom_singles/04-dummy_reads_apu.nes", "CPU"),
  rom("cpu_dummy_reads/cpu_dummy_reads.nes", "CPU", protocol=Screen),
  rom("cpu_interrupts_v2/rom_singles/1-cli_latency.nes", "CPU"),
  rom("cpu_interrupts_v2/rom_singles/2-nmi_and_brk.nes", "CPU"),
  rom("cpu_interrupts_v2/rom_singles/3-nmi_and_irq.nes", "CPU"),
  rom("cpu_interrupts_v2/rom_singles/4-irq_and_dma.nes", "CPU"),
  rom("cpu_interrupts_v2/rom_singles/5-branch_delays_irq.nes", "CPU"),
  rom("ppu_vbl_nmi/rom_singles/01-vbl_basics.nes", "PPU"),
  rom("ppu_vbl_nmi/rom_singles/02-vbl_set_time.nes", "PPU"),
  rom("ppu_vbl_nmi/rom_singles/03-vbl_clear_time.nes", "PPU"),
  rom("ppu_vbl_nmi/rom_singles/04-nmi_control.nes", "PPU"),
  rom("ppu_vbl_nmi/rom_singles/05-nmi_timing.nes", "PPU"),
  rom("ppu_vbl_nmi/rom_singles/06-suppression.nes", "PPU"),
  rom("ppu_vbl_nmi/rom_singles/07-nmi_on_timing.nes", "PPU"),
  rom("ppu_vbl_nmi/rom_singles/08-nmi_off_timing.nes", "PPU"),
  rom("ppu_vbl_nmi/rom_singles/09-even_odd_frames.nes", "PPU"),
  rom("ppu_vbl_nmi/rom_singles/10-even_odd_timing.nes", "PPU"),
  rom("sprite_hit_tests_2005.10.05/01.basics.nes", "PPU", protocol=Legacy(0xF8)),
  rom(
    "sprite_hit_tests_2005.10.05/02.alignment.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "sprite_hit_tests_2005.10.05/03.corners.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom("sprite_hit_tests_2005.10.05/04.flip.nes", "PPU", protocol=Legacy(0xF8)),
  rom(
    "sprite_hit_tests_2005.10.05/05.left_clip.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "sprite_hit_tests_2005.10.05/06.right_edge.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "sprite_hit_tests_2005.10.05/07.screen_bottom.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "sprite_hit_tests_2005.10.05/08.double_height.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "sprite_hit_tests_2005.10.05/09.timing_basics.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "sprite_hit_tests_2005.10.05/10.timing_order.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom(
    "sprite_hit_tests_2005.10.05/11.edge_timing.nes",
    "PPU",
    protocol=Legacy(0xF8),
  ),
  rom("sprite_overflow_tests/1.Basics.nes", "PPU", protocol=Legacy(0xF8)),
  rom("sprite_overflow_tests/2.Details.nes", "PPU", protocol=Legacy(0xF8)),
  rom("sprite_overflow_tests/3.Timing.nes", "PPU", protocol=Legacy(0xF8)),
  rom("sprite_overflow_tests/4.Obscure.nes", "PPU", protocol=Legacy(0xF8)),
  rom("sprite_overflow_tests/5.Emulator.nes", "PPU", protocol=Legacy(0xF8)),
  rom(
    "blargg_ppu_tests_2005.09.15b/palette_ram.nes",
    "PPU",
    protocol=Legacy(0xF0),
  ),
  rom(
    "blargg_ppu_tests_2005.09.15b/power_up_palette.nes",
    "PPU",
    protocol=Legacy(0xF0),
  ),
  rom(
    "blargg_ppu_tests_2005.09.15b/sprite_ram.nes",
    "PPU",
    protocol=Legacy(0xF0),
  ),
  rom(
    "blargg_ppu_tests_2005.09.15b/vbl_clear_time.nes",
    "PPU",
    protocol=Legacy(0xF0),
  ),
  rom(
    "blargg_ppu_tests_2005.09.15b/vram_access.nes",
    "PPU",
    protocol=Legacy(0xF0),
  ),
  rom("oam_read/oam_read.nes", "PPU"),
  rom("ppu_open_bus/ppu_open_bus.nes", "PPU"),
]

///|
pub fn Nes::run_suite_rom(self : Nes, rom : SuiteRom) -> TestOutcome {
  match rom.protocol {
    Blargg => self.run_blargg_test(rom.frames)
    Legacy(addr) => self.run_legacy_test(rom.frames, result_addr=addr)
    Screen => self.run_screen_test(rom.frames)
  }
}
