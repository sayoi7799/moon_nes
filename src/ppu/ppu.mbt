// Ricoh 2C02 PPU, stepped one dot at a time.
// Reference: https://www.nesdev.org/wiki/PPU_rendering,
// https://www.nesdev.org/wiki/PPU_scrolling (loopy's v/t/x/w registers),
// https://www.nesdev.org/wiki/PPU_sprite_evaluation
//
// A frame is 262 scanlines of 341 dots. Scanlines 0-239 are visible, 240 is
// idle, 241-260 are vertical blank and 261 is the pre-render line.

///|
pub const WIDTH : Int32 = 256

///|
pub const HEIGHT : Int32 = 240

///|
const PRE_RENDER : Int32 = 261

///|
/// Palette RAM contents at power-on. Real chips power up with semi-random
/// values; these are the ones blargg's power_up_palette test expects.
let power_up_palette : Array[Int32] = [
  0x09, 0x01, 0x00, 0x01, 0x00, 0x02, 0x02, 0x0D, 0x08, 0x10, 0x08, 0x24, 0x00, 0x00,
  0x04, 0x2C, 0x09, 0x01, 0x34, 0x03, 0x00, 0x04, 0x00, 0x14, 0x08, 0x3A, 0x00, 0x02,
  0x00, 0x20, 0x2C, 0x08,
]

///|
pub struct Ppu {
  mapper : &@mapper.Mapper
  /// 256x240 pixels; each is a palette index (0-63) with the three color
  /// emphasis bits of PPUMASK in bits 6-8.
  frame : FixedArray[Int32]
  priv vram : FixedArray[Int32]
  priv palette : FixedArray[Int32]
  oam : FixedArray[Int32]
  // Registers.
  priv mut ctrl : Int32
  priv mut mask : Int32
  priv mut vblank : Bool
  priv mut sprite0_hit : Bool
  priv mut sprite_overflow : Bool
  priv mut oam_addr : Int32
  priv mut read_buffer : Int32
  /// The PPU's I/O data bus ("decay register"): what open-bus bits read as.
  priv mut io_latch : Int32
  /// Frame number at which each latch bit was last driven.
  priv io_refreshed : FixedArray[Int32]
  // Loopy registers: current VRAM address, temporary address, fine X and
  // the shared first/second write toggle of $2005/$2006.
  priv mut v : Int32
  priv mut t : Int32
  priv mut fine_x : Int32
  priv mut w : Bool
  // Position.
  mut scanline : Int32
  mut dot : Int32
  mut frame_count : Int32
  priv mut odd_frame : Bool
  priv mut skip_dot : Bool
  /// Set when vertical blank starts; cleared by `start_frame`.
  priv mut frame_done : Bool
  /// A $2002 read just before VBL set suppresses the flag for that frame.
  priv mut suppress_vbl : Bool
  // Background pipeline.
  priv mut nt_latch : Int32
  priv mut at_latch : Int32
  priv mut pt_lo_latch : Int32
  priv mut pt_hi_latch : Int32
  priv mut bg_lo : Int32
  priv mut bg_hi : Int32
  priv mut at_lo : Int32
  priv mut at_hi : Int32
  // Sprites for the line being drawn, prepared on the previous line.
  priv line_x : FixedArray[Int32]
  priv line_attr : FixedArray[Int32]
  priv line_lo : FixedArray[Int32]
  priv line_hi : FixedArray[Int32]
  priv mut line_count : Int32
  priv mut line_has_sprite0 : Bool
  // Result of evaluation on the current line, used for the next line.
  priv eval_index : FixedArray[Int32]
  priv mut eval_count : Int32
  priv mut eval_has_sprite0 : Bool
  /// Dot of the current line at which the overflow flag gets set, or -1.
  priv mut overflow_dot : Int32
}

///|
pub fn Ppu::new(mapper : &@mapper.Mapper) -> Ppu {
  {
    mapper,
    frame: FixedArray::make(WIDTH * HEIGHT, 0),
    vram: FixedArray::make(0x1000, 0),
    palette: FixedArray::from_array(power_up_palette),
    oam: FixedArray::make(256, 0),
    ctrl: 0,
    mask: 0,
    vblank: false,
    sprite0_hit: false,
    sprite_overflow: false,
    oam_addr: 0,
    read_buffer: 0,
    io_latch: 0,
    io_refreshed: FixedArray::make(8, 0),
    v: 0,
    t: 0,
    fine_x: 0,
    w: false,
    scanline: 0,
    dot: 0,
    frame_count: 0,
    odd_frame: false,
    skip_dot: false,
    frame_done: false,
    suppress_vbl: false,
    nt_latch: 0,
    at_latch: 0,
    pt_lo_latch: 0,
    pt_hi_latch: 0,
    bg_lo: 0,
    bg_hi: 0,
    at_lo: 0,
    at_hi: 0,
    line_x: FixedArray::make(8, 0),
    line_attr: FixedArray::make(8, 0),
    line_lo: FixedArray::make(8, 0),
    line_hi: FixedArray::make(8, 0),
    line_count: 0,
    line_has_sprite0: false,
    eval_index: FixedArray::make(8, 0),
    eval_count: 0,
    eval_has_sprite0: false,
    overflow_dot: -1,
  }
}

///|
/// Clears the end-of-frame flag before running the next frame.
pub fn Ppu::start_frame(self : Ppu) -> Unit {
  self.frame_done = false
}

///|
/// True once vertical blank has started since `start_frame`.
pub fn Ppu::frame_done(self : Ppu) -> Bool {
  self.frame_done
}

///|
/// Bits of the I/O latch that are not refreshed decay to 0 after about
/// 600 ms (36 frames).
fn Ppu::decayed_latch(self : Ppu) -> Int32 {
  for i in 0..<8 {
    if self.frame_count - self.io_refreshed[i] > 36 {
      self.io_latch = self.io_latch & (1 << i).lnot()
    }
  }
  self.io_latch
}

///|
/// Drives the latch bits selected by `mask` with `value`.
fn Ppu::refresh_latch(self : Ppu, value : Int32, mask : Int32) -> Unit {
  self.io_latch = (self.io_latch & mask.lnot()) | (value & mask)
  for i in 0..<8 {
    if (mask & (1 << i)) != 0 {
      self.io_refreshed[i] = self.frame_count
    }
  }
}

///|
/// Level of the NMI output: asserted while in vblank with NMI enabled.
pub fn Ppu::nmi_line(self : Ppu) -> Bool {
  self.vblank && (self.ctrl & 0x80) != 0
}

///|
#inline
fn Ppu::rendering(self : Ppu) -> Bool {
  (self.mask & 0x18) != 0
}

// ---------------------------------------------------------------------------
// PPU address space

///|
fn Ppu::nametable_index(self : Ppu, addr : Int32) -> Int32 {
  let table = (addr >> 10) & 3
  let physical = match self.mapper.mirroring() {
    Horizontal => table >> 1
    Vertical => table & 1
    SingleLow => 0
    SingleHigh => 1
    FourScreen => table
  }
  (physical << 10) | (addr & 0x3FF)
}

///|
fn palette_index(addr : Int32) -> Int32 {
  let i = addr & 0x1F
  // $3F10/$3F14/$3F18/$3F1C mirror the backdrop entries.
  if (i & 0x13) == 0x10 {
    i & 0x0F
  } else {
    i
  }
}

///|
fn Ppu::mem_read(self : Ppu, addr : Int32) -> Int32 {
  let a = addr & 0x3FFF
  if a < 0x2000 {
    self.mapper.ppu_read(a)
  } else if a < 0x3F00 {
    self.vram[self.nametable_index(a)]
  } else {
    self.palette[palette_index(a)]
  }
}

///|
fn Ppu::mem_write(self : Ppu, addr : Int32, value : Int32) -> Unit {
  let a = addr & 0x3FFF
  if a < 0x2000 {
    self.mapper.ppu_write(a, value)
  } else if a < 0x3F00 {
    self.vram[self.nametable_index(a)] = value
  } else {
    self.palette[palette_index(a)] = value & 0x3F
  }
}

// ---------------------------------------------------------------------------
// CPU-visible registers ($2000-$2007, mirrored every 8 bytes)

///|
pub fn Ppu::read_register(self : Ppu, reg : Int32) -> Int32 {
  self.decayed_latch() |> ignore
  match reg & 7 {
    2 => {
      // A read on the very dot the VBL flag would be set returns it clear
      // and keeps it from being set this frame, so no NMI happens either.
      // (CPU accesses happen just before the PPU processes `self.dot`.)
      if self.scanline == 241 && self.dot == 1 {
        self.suppress_vbl = true
      }
      let status = (if self.vblank { 0x80 } else { 0 }) |
        (if self.sprite0_hit { 0x40 } else { 0 }) |
        (if self.sprite_overflow { 0x20 } else { 0 })
      self.vblank = false
      self.w = false
      self.refresh_latch(status, 0xE0)
    }
    4 => {
      let v = self.oam[self.oam_addr]
      // Attribute bytes have no bits 2-4.
      self.refresh_latch(
        if (self.oam_addr & 3) == 2 {
          v & 0xE3
        } else {
          v
        },
        0xFF,
      )
    }
    7 => {
      let addr = self.v & 0x3FFF
      if addr >= 0x3F00 {
        // Palette reads are immediate; the buffer gets the nametable byte
        // "underneath" the palette.
        self.refresh_latch(self.mem_read(addr), 0x3F)
        self.read_buffer = self.mem_read(addr - 0x1000)
      } else {
        self.refresh_latch(self.read_buffer, 0xFF)
        self.read_buffer = self.mem_read(addr)
      }
      self.increment_after_access()
    }
    _ => ()
  }
  self.io_latch
}

///|
pub fn Ppu::write_register(self : Ppu, reg : Int32, value : Int32) -> Unit {
  self.refresh_latch(value, 0xFF)
  match reg & 7 {
    0 => {
      self.ctrl = value
      self.t = (self.t & 0x73FF) | ((value & 3) << 10)
    }
    1 => self.mask = value
    3 => self.oam_addr = value
    4 => {
      self.oam[self.oam_addr] = value
      self.oam_addr = (self.oam_addr + 1) & 0xFF
    }
    5 =>
      if !self.w {
        self.t = (self.t & 0x7FE0) | (value >> 3)
        self.fine_x = value & 7
        self.w = true
      } else {
        self.t = (self.t & 0x0C1F) | ((value & 7) << 12) | ((value & 0xF8) << 2)
        self.w = false
      }
    6 =>
      if !self.w {
        self.t = (self.t & 0x00FF) | ((value & 0x3F) << 8)
        self.w = true
      } else {
        self.t = (self.t & 0x7F00) | value
        self.v = self.t
        self.w = false
      }
    7 => {
      self.mem_write(self.v, value)
      self.increment_after_access()
    }
    _ => ()
  }
}

///|
/// Reads PPU memory ($0000-$3FFF) without side effects.
pub fn Ppu::peek_memory(self : Ppu, addr : Int32) -> Int32 {
  self.mem_read(addr)
}

///|
/// Reads a register without side effects (for debugging and tracing).
pub fn Ppu::peek_register(self : Ppu, reg : Int32) -> Int32 {
  match reg & 7 {
    2 =>
      (if self.vblank { 0x80 } else { 0 }) |
      (if self.sprite0_hit { 0x40 } else { 0 }) |
      (if self.sprite_overflow { 0x20 } else { 0 }) |
      (self.io_latch & 0x1F)
    4 => self.oam[self.oam_addr]
    _ => self.io_latch
  }
}

///|
fn Ppu::increment_after_access(self : Ppu) -> Unit {
  let on_render_line = self.scanline < 240 || self.scanline == PRE_RENDER
  if self.rendering() && on_render_line {
    // During rendering the address increments as if fetching.
    self.inc_coarse_x()
    self.inc_y()
  } else {
    self.v = (self.v + (if (self.ctrl & 0x04) != 0 { 32 } else { 1 })) & 0x7FFF
  }
}

// ---------------------------------------------------------------------------
// Scrolling helpers on v (yyy NN YYYYY XXXXX)

///|
fn Ppu::inc_coarse_x(self : Ppu) -> Unit {
  if (self.v & 0x001F) == 31 {
    self.v = (self.v & 0x7FE0) ^ 0x0400
  } else {
    self.v += 1
  }
}

///|
fn Ppu::inc_y(self : Ppu) -> Unit {
  if (self.v & 0x7000) != 0x7000 {
    self.v += 0x1000
    return
  }
  self.v = self.v & 0x0FFF
  let coarse_y = (self.v & 0x03E0) >> 5
  let y = if coarse_y == 29 {
    self.v = self.v ^ 0x0800
    0
  } else if coarse_y == 31 {
    0
  } else {
    coarse_y + 1
  }
  self.v = (self.v & 0x7C1F) | (y << 5)
}

///|
fn Ppu::copy_x(self : Ppu) -> Unit {
  self.v = (self.v & 0x7BE0) | (self.t & 0x041F)
}

///|
fn Ppu::copy_y(self : Ppu) -> Unit {
  self.v = (self.v & 0x041F) | (self.t & 0x7BE0)
}

// ---------------------------------------------------------------------------
// Background pipeline

///|
fn Ppu::reload_shifters(self : Ppu) -> Unit {
  self.bg_lo = (self.bg_lo & 0xFF00) | self.pt_lo_latch
  self.bg_hi = (self.bg_hi & 0xFF00) | self.pt_hi_latch
  self.at_lo = (self.at_lo & 0xFF00) |
    (if (self.at_latch & 1) != 0 { 0xFF } else { 0 })
  self.at_hi = (self.at_hi & 0xFF00) |
    (if (self.at_latch & 2) != 0 { 0xFF } else { 0 })
}

///|
fn Ppu::shift_background(self : Ppu) -> Unit {
  self.bg_lo = (self.bg_lo << 1) & 0xFFFF
  self.bg_hi = (self.bg_hi << 1) & 0xFFFF
  self.at_lo = (self.at_lo << 1) & 0xFFFF
  self.at_hi = (self.at_hi << 1) & 0xFFFF
}

///|
/// One step of the 8-dot tile fetch cycle.
fn Ppu::fetch_background(self : Ppu) -> Unit {
  match (self.dot - 1) & 7 {
    0 => {
      self.reload_shifters()
      self.nt_latch = self.mem_read(0x2000 | (self.v & 0x0FFF))
    }
    2 => {
      let v = self.v
      let at = self.mem_read(
        0x23C0 | (v & 0x0C00) | ((v >> 4) & 0x38) | ((v >> 2) & 0x07),
      )
      let shift = ((v >> 4) & 4) | (v & 2)
      self.at_latch = (at >> shift) & 3
    }
    4 => {
      let base = ((self.ctrl & 0x10) << 8) | (self.nt_latch << 4)
      self.pt_lo_latch = self.mem_read(base | ((self.v >> 12) & 7))
    }
    6 => {
      let base = ((self.ctrl & 0x10) << 8) | (self.nt_latch << 4)
      self.pt_hi_latch = self.mem_read(base | ((self.v >> 12) & 7) | 8)
    }
    7 => self.inc_coarse_x()
    _ => ()
  }
}

// ---------------------------------------------------------------------------
// Sprites

///|
fn Ppu::sprite_height(self : Ppu) -> Int32 {
  if (self.ctrl & 0x20) != 0 {
    16
  } else {
    8
  }
}

///|
/// Sprite evaluation for the next line, including the hardware bug that
/// makes the overflow search step diagonally through OAM. Each probe of a
/// Y coordinate costs 2 dots and copying an in-range sprite 8 dots, starting
/// at dot 65; that is used to time the overflow flag.
fn Ppu::evaluate_sprites(self : Ppu) -> Unit {
  let height = self.sprite_height()
  let line = self.scanline
  self.eval_count = 0
  self.eval_has_sprite0 = false
  self.overflow_dot = -1
  let mut n = 0
  let mut time = 65
  while n < 64 && self.eval_count < 8 {
    let y = self.oam[n * 4]
    let row = line - y
    if row >= 0 && row < height {
      self.eval_index[self.eval_count] = n
      self.eval_count += 1
      if n == 0 {
        self.eval_has_sprite0 = true
      }
      time += 8
    } else {
      time += 2
    }
    n += 1
  }
  // Overflow search: m should stay 0, but the PPU increments it alongside n.
  let mut m = 0
  while n < 64 {
    let y = self.oam[n * 4 + m]
    let row = line - y
    if row >= 0 && row < height {
      self.overflow_dot = if time > 256 { 256 } else { time }
      break
    }
    n += 1
    m = (m + 1) & 3
    time += 2
  }
}

///|
fn reverse_bits(b : Int32) -> Int32 {
  let mut r = 0
  for i in 0..<8 {
    if (b & (1 << i)) != 0 {
      r = r | (0x80 >> i)
    }
  }
  r
}

///|
/// Fetches pattern data for the sprites found by evaluation (dots 257-320).
fn Ppu::fetch_sprites(self : Ppu) -> Unit {
  let height = self.sprite_height()
  let line = self.scanline
  for i in 0..<self.eval_count {
    let base = self.eval_index[i] * 4
    let y = self.oam[base]
    let tile = self.oam[base + 1]
    let attr = self.oam[base + 2]
    let mut row = line - y
    if (attr & 0x80) != 0 {
      row = height - 1 - row
    }
    let addr = if height == 16 {
      let table = (tile & 1) << 12
      let t = (tile & 0xFE) + (if row >= 8 { 1 } else { 0 })
      table | (t << 4) | (row & 7)
    } else {
      ((self.ctrl & 0x08) << 9) | (tile << 4) | row
    }
    let mut lo = self.mem_read(addr)
    let mut hi = self.mem_read(addr + 8)
    if (attr & 0x40) != 0 {
      lo = reverse_bits(lo)
      hi = reverse_bits(hi)
    }
    self.line_x[i] = self.oam[base + 3]
    self.line_attr[i] = attr
    self.line_lo[i] = lo
    self.line_hi[i] = hi
  }
  self.line_count = self.eval_count
  self.line_has_sprite0 = self.eval_has_sprite0
}

// ---------------------------------------------------------------------------
// Pixel output

///|
fn Ppu::render_pixel(self : Ppu) -> Unit {
  let x = self.dot - 1
  let mut bg = 0
  let mut bg_palette = 0
  if (self.mask & 0x08) != 0 && (x >= 8 || (self.mask & 0x02) != 0) {
    let bit = 15 - self.fine_x
    bg = (((self.bg_hi >> bit) & 1) << 1) | ((self.bg_lo >> bit) & 1)
    bg_palette = (((self.at_hi >> bit) & 1) << 1) | ((self.at_lo >> bit) & 1)
  }
  let mut spr = 0
  let mut spr_palette = 0
  let mut spr_behind = false
  if (self.mask & 0x10) != 0 && (x >= 8 || (self.mask & 0x04) != 0) {
    for i in 0..<self.line_count {
      let col = x - self.line_x[i]
      if col < 0 || col > 7 {
        continue
      }
      let shift = 7 - col
      let p = (((self.line_hi[i] >> shift) & 1) << 1) |
        ((self.line_lo[i] >> shift) & 1)
      if p == 0 {
        continue
      }
      if i == 0 && self.line_has_sprite0 && bg != 0 && x != 255 {
        self.sprite0_hit = true
      }
      spr = p
      spr_palette = self.line_attr[i] & 3
      spr_behind = (self.line_attr[i] & 0x20) != 0
      break
    }
  }
  let index = if bg == 0 && spr == 0 {
    0
  } else if spr != 0 && (bg == 0 || !spr_behind) {
    0x10 | (spr_palette << 2) | spr
  } else {
    (bg_palette << 2) | bg
  }
  self.output(x, self.palette[index])
}

///|
fn Ppu::output(self : Ppu, x : Int32, color : Int32) -> Unit {
  let c = if (self.mask & 0x01) != 0 { color & 0x30 } else { color }
  self.frame[self.scanline * WIDTH + x] = c | ((self.mask & 0xE0) << 1)
}

// ---------------------------------------------------------------------------
// Main stepping

///|
/// Advances the PPU by one dot.
pub fn Ppu::step(self : Ppu) -> Unit {
  let line = self.scanline
  let dot = self.dot
  let visible = line < 240
  let pre = line == PRE_RENDER
  if self.rendering() && (visible || pre) {
    if (dot >= 2 && dot <= 257) || (dot >= 322 && dot <= 337) {
      self.shift_background()
    }
    if visible && dot >= 1 && dot <= 256 {
      self.render_pixel()
    }
    if (dot >= 1 && dot <= 256) || (dot >= 321 && dot <= 336) {
      self.fetch_background()
    }
    if dot == 256 {
      self.inc_y()
    } else if dot == 257 {
      self.reload_shifters()
      self.copy_x()
    }
    if pre && dot >= 280 && dot <= 304 {
      self.copy_y()
    }
    if visible {
      if dot == 65 {
        self.evaluate_sprites()
      }
      if dot == self.overflow_dot {
        self.sprite_overflow = true
      }
      if dot == 257 {
        self.fetch_sprites()
      }
    } else if dot == 257 {
      // Nothing is evaluated on the pre-render line: line 0 has no sprites.
      self.line_count = 0
      self.line_has_sprite0 = false
    }
  } else if visible && dot >= 1 && dot <= 256 {
    // Rendering disabled: show the backdrop, or the palette entry v points
    // at when v is inside palette RAM.
    let color = if (self.v & 0x3F00) == 0x3F00 {
      self.palette[palette_index(self.v)]
    } else {
      self.palette[0]
    }
    self.output(dot - 1, color)
  }
  if line == 241 && dot == 1 {
    if !self.suppress_vbl {
      self.vblank = true
    }
    self.suppress_vbl = false
    self.frame_done = true
  } else if pre && dot == 1 {
    self.vblank = false
    self.sprite0_hit = false
    self.sprite_overflow = false
  }
  self.advance()
}

///|
fn Ppu::advance(self : Ppu) -> Unit {
  // On odd frames with rendering on, the pre-render line is one dot short.
  // Whether rendering is on is sampled one dot before the skipped dot.
  if self.scanline == PRE_RENDER {
    if self.dot == 338 {
      self.skip_dot = self.odd_frame && self.rendering()
    } else if self.dot == 339 && self.skip_dot {
      self.dot = 340
    }
  }
  self.dot += 1
  if self.dot > 340 {
    self.dot = 0
    self.scanline += 1
    if self.scanline > PRE_RENDER {
      self.scanline = 0
      self.odd_frame = !self.odd_frame
      self.frame_count += 1
    }
  }
}
