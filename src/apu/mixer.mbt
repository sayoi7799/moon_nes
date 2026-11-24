// Non-linear channel mixer, using the exact formulas of
// https://www.nesdev.org/wiki/APU_Mixer:
//
//   pulse_out = 95.88 / (8128 / (pulse1 + pulse2) + 100)
//   tnd_out   = 159.79 / (1 / (triangle / 8227 + noise / 12241 + dmc / 22638) + 100)
//
// Both are precomputed into tables. The wiki's single-index approximation
// of tnd_out bends the DMC curve differently, which the apu_mixer tests
// (they cancel each channel against the DMC) can hear. Only +, -, * and /
// are used, so every backend computes bit-identical values.

///|
let pulse_table : FixedArray[Double] = FixedArray::makei(31, n => {
  if n == 0 {
    0.0
  } else {
    95.88 / (8128.0 / n.to_double() + 100.0)
  }
})

///|
/// Indexed by (triangle * 16 + noise) * 128 + dmc.
let tnd_table : FixedArray[Double] = FixedArray::makei(16 * 16 * 128, i => {
  let t = (i >> 11).to_double()
  let n = ((i >> 7) & 15).to_double()
  let d = (i & 127).to_double()
  let sum = t / 8227.0 + n / 12241.0 + d / 22638.0
  if sum == 0.0 {
    0.0
  } else {
    159.79 / (1.0 / sum + 100.0)
  }
})

///|
/// Mixed output of all channels, from 0.0 up to about 1.0.
pub fn Apu::output(self : Apu) -> Double {
  let p1 = self.pulse1.output(self.length[0])
  let p2 = self.pulse2.output(self.length[1])
  let t = self.triangle.output()
  let n = self.noise.output(self.length[3])
  pulse_table[p1 + p2] + tnd_table[(t << 11) | (n << 7) | self.dmc.level]
}
