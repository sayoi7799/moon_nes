// The whole console and its platform-independent API.

///|
pub const SCREEN_WIDTH : Int32 = 256

///|
pub const SCREEN_HEIGHT : Int32 = 240

///|
/// Controller button bits for `set_buttons`.
pub const BUTTON_A : Int32 = 0x01

///|
pub const BUTTON_B : Int32 = 0x02

///|
pub const BUTTON_SELECT : Int32 = 0x04

///|
pub const BUTTON_START : Int32 = 0x08

///|
pub const BUTTON_UP : Int32 = 0x10

///|
pub const BUTTON_DOWN : Int32 = 0x20

///|
pub const BUTTON_LEFT : Int32 = 0x40

///|
pub const BUTTON_RIGHT : Int32 = 0x80

///|
pub struct Nes {
  cartridge : @cartridge.Cartridge
  bus : @bus.Bus
  cpu : @cpu.Cpu[@bus.Bus]
}

///|
/// Parses an iNES image and powers the console on. Malformed files and
/// unsupported mappers raise `RomError`.
pub fn Nes::load_rom(data : Bytes) -> Nes raise @cartridge.RomError {
  let cartridge = @cartridge.parse(data)
  let mapper = @mapper.create(cartridge)
  let bus = @bus.Bus::new(mapper)
  let cpu = @cpu.Cpu::new(bus)
  cpu.reset()
  { cartridge, bus, cpu, }
}

///|
/// Presses the reset button. RAM and PPU memory keep their contents.
pub fn Nes::reset(self : Nes) -> Unit {
  self.cpu.reset()
}

///|
/// Runs until the PPU starts the next vertical blank, i.e. one frame.
pub fn Nes::run_frame(self : Nes) -> Unit {
  let ppu = self.bus.ppu
  ppu.start_frame()
  while !ppu.frame_done() {
    self.cpu.step()
  }
}

///|
/// Executes a single CPU instruction (or interrupt sequence).
pub fn Nes::step(self : Nes) -> Unit {
  self.cpu.step()
}

///|
/// The 256x240 framebuffer. Each pixel is a 6-bit NES color in bits 0-5
/// plus the PPUMASK emphasis bits in bits 6-8; see `pixel_rgb`.
pub fn Nes::frame_buffer(self : Nes) -> FixedArray[Int32] {
  self.bus.ppu.frame
}

///|
/// Writes the frame as RGBA bytes (256*240*4) into `out`.
pub fn Nes::write_rgba(self : Nes, out : FixedArray[Byte]) -> Unit {
  let frame = self.bus.ppu.frame
  for i in 0..<frame.length() {
    let rgb = pixel_rgb(frame[i])
    out[i * 4] = (rgb >> 16).to_byte()
    out[i * 4 + 1] = (rgb >> 8).to_byte()
    out[i * 4 + 2] = rgb.to_byte()
    out[i * 4 + 3] = b'\xFF'
  }
}

///|
/// Sets the held buttons of controller `player` (0 or 1) as a bit mask of
/// the BUTTON_* constants.
pub fn Nes::set_buttons(self : Nes, player : Int32, buttons : Int32) -> Unit {
  let pad = if player == 0 { self.bus.pad1 } else { self.bus.pad2 }
  pad.set_buttons(buttons)
}

///|
/// Reads CPU memory without side effects.
pub fn Nes::peek(self : Nes, addr : Int32) -> Int32 {
  @cpu.CpuBus::peek(self.bus, addr & 0xFFFF)
}

///|
pub fn Nes::frame_count(self : Nes) -> Int32 {
  self.bus.ppu.frame_count
}

///|
/// Sets the audio output rate in Hz (default 48000), or 0 to turn sound
/// generation off. Front ends may nudge the rate slightly every frame to
/// keep their audio buffer at a steady level.
pub fn Nes::set_sample_rate(self : Nes, rate : Double) -> Unit {
  self.bus.apu.set_sample_rate(rate)
}

///|
/// Number of audio samples produced and not yet taken, about 800 per frame
/// at 48 kHz. The buffer keeps the latest second.
pub fn Nes::samples_available(self : Nes) -> Int32 {
  self.bus.apu.samples_available()
}

///|
/// Moves up to `out.length()` mono samples (roughly -1.0..1.0, oldest
/// first) into `out` and returns how many were written.
pub fn Nes::take_samples(self : Nes, out : FixedArray[Double]) -> Int32 {
  self.bus.apu.take_samples(out)
}

///|
/// 32-bit FNV-1a hash of the framebuffer, for regression tests.
pub fn Nes::frame_hash(self : Nes) -> UInt32 {
  let mut h : UInt32 = 0x811C9DC5
  for p in self.bus.ppu.frame {
    h = (h ^ (p & 0xFF).reinterpret_as_uint()) * 0x01000193
    h = (h ^ (p >> 8).reinterpret_as_uint()) * 0x01000193
  }
  h
}

///|
/// The first nametable as 30 lines of 32 characters, treating tile numbers
/// $20-$7E as ASCII. Test ROMs that print text use this layout.
pub fn Nes::screen_text(self : Nes) -> String {
  let s = StringBuilder()
  for row in 0..<30 {
    for col in 0..<32 {
      let t = self.bus.ppu.peek_memory(0x2000 + row * 32 + col)
      s.write_char(if t >= 0x20 && t < 0x7F { t.unsafe_to_char() } else { ' ' })
    }
    s.write_char('\n')
  }
  s.to_string()
}
