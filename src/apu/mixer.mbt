// Non-linear channel mixer, using the lookup-table form of the formulas on
// https://www.nesdev.org/wiki/APU_Mixer. Only +, -, * and / are used, so
// every backend computes bit-identical values.

///|
/// pulse_table[n] = 95.52 / (8128 / n + 100), n = pulse1 + pulse2.
let pulse_table : FixedArray[Double] = FixedArray::makei(31, n => {
  if n == 0 {
    0.0
  } else {
    95.52 / (8128.0 / n.to_double() + 100.0)
  }
})

///|
/// tnd_table[n] = 163.67 / (24329 / n + 100), n = 3 * triangle + 2 * noise + dmc.
let tnd_table : FixedArray[Double] = FixedArray::makei(203, n => {
  if n == 0 {
    0.0
  } else {
    163.67 / (24329.0 / n.to_double() + 100.0)
  }
})

///|
/// Mixed output of all channels, from 0.0 up to about 1.0.
pub fn Apu::output(self : Apu) -> Double {
  let p1 = self.pulse1.output(self.length[0])
  let p2 = self.pulse2.output(self.length[1])
  let t = self.triangle.output()
  let n = self.noise.output(self.length[3])
  pulse_table[p1 + p2] + tnd_table[3 * t + 2 * n + self.dmc.level]
}
