// NTSC palette, generated from the composite signal levels of the 2C02.
//
// Each color is a square wave between a low and a high voltage; the hue
// (bits 0-3) sets its phase and the level (bits 4-5) picks the voltages.
// Luma is the average voltage and saturation half the swing; the result is
// decoded as YIQ. Voltage levels are the measured ones documented at
// https://www.nesdev.org/wiki/NTSC_video

///|
let signal_low : FixedArray[Double] = [0.350, 0.518, 0.962, 1.550]

///|
let signal_high : FixedArray[Double] = [1.094, 1.506, 1.962, 1.962]

///|
let black_level : Double = 0.518

///|
let white_level : Double = 1.962

///|
fn to_channel(v : Double) -> Int32 {
  let c = (v * 255.0 + 0.5).to_int()
  if c < 0 {
    0
  } else if c > 255 {
    255
  } else {
    c
  }
}

///|
/// RGB (0xRRGGBB) for a 6-bit color without emphasis.
fn base_color(color : Int32) -> (Double, Double, Double) {
  let hue = color & 0x0F
  let level = (color >> 4) & 3
  let lo = signal_low[level]
  let hi = signal_high[level]
  let (low, high) = match hue {
    0 => (hi, hi)
    13 => (lo, lo)
    14 | 15 => (black_level, black_level)
    _ => (lo, hi)
  }
  let range = white_level - black_level
  let y = ((low + high) / 2.0 - black_level) / range
  let amp = if hue >= 1 && hue <= 12 { (high - low) / 2.0 / range } else { 0.0 }
  // 30 degrees per hue step; hue 6 sits near the red end of the I axis.
  let angle = ((6 - hue).to_double() * 30.0 + 10.0) * @math.PI / 180.0
  let i = amp * @math.cos(angle)
  let q = amp * @math.sin(angle)
  (
    y + 0.956 * i + 0.621 * q,
    y - 0.272 * i - 0.647 * q,
    y - 1.106 * i + 1.703 * q,
  )
}

///|
/// 512 entries: 64 colors for each of the 8 emphasis combinations.
/// Emphasis bits (PPUMASK 5-7) darken the channels that are not emphasized.
let rgb_table : FixedArray[Int32] = FixedArray::makei(512, entry => {
  let (r, g, b) = base_color(entry & 0x3F)
  let emphasis = entry >> 6
  let dim = 0.79
  let any = emphasis != 0 && (entry & 0x0E) != 0x0E
  let r = if any && (emphasis & 1) == 0 { r * dim } else { r }
  let g = if any && (emphasis & 2) == 0 { g * dim } else { g }
  let b = if any && (emphasis & 4) == 0 { b * dim } else { b }
  (to_channel(r) << 16) | (to_channel(g) << 8) | to_channel(b)
})

///|
/// RGB value (0xRRGGBB) of a framebuffer pixel.
pub fn pixel_rgb(pixel : Int32) -> Int32 {
  rgb_table[pixel & 0x1FF]
}
