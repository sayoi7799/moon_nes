// Turns the per-cycle mixer output into samples at an output rate.
//
// Each output sample is the average of the CPU cycles it covers, which
// also acts as the anti-aliasing filter. The result then goes through the
// console's own filters: a first-order 90 Hz high-pass and a first-order
// 14 kHz low-pass (https://www.nesdev.org/wiki/APU_Mixer). Coefficients use
// only arithmetic, no exp, so all backends produce identical samples.

///|
pub const CPU_CLOCK : Double = 1789773.0

///|
let pi : Double = 3.141592653589793

///|
priv struct Resampler {
  /// Output rate in Hz; 0 disables sampling.
  mut rate : Double
  /// CPU cycles per output sample.
  mut step : Double
  mut phase : Double
  mut sum : Double
  mut count : Int32
  mut hp_alpha : Double
  mut hp_in : Double
  mut hp_out : Double
  mut lp_alpha : Double
  mut lp_out : Double
  /// Ring buffer of finished samples, one second long.
  mut buffer : FixedArray[Double]
  mut read_pos : Int32
  mut write_pos : Int32
  mut available : Int32
}

///|
fn Resampler::new(rate : Double) -> Resampler {
  let r = {
    rate: 0.0,
    step: 0.0,
    phase: 0.0,
    sum: 0.0,
    count: 0,
    hp_alpha: 0.0,
    hp_in: 0.0,
    hp_out: 0.0,
    lp_alpha: 0.0,
    lp_out: 0.0,
    buffer: FixedArray::make(1, 0.0),
    read_pos: 0,
    write_pos: 0,
    available: 0,
  }
  r.set_rate(rate)
  r
}

///|
/// Changes the output rate. Small changes (for rate control) keep the
/// buffered samples and the filter state.
fn Resampler::set_rate(self : Resampler, rate : Double) -> Unit {
  self.rate = if rate > 0.0 { rate } else { 0.0 }
  if self.rate == 0.0 {
    return
  }
  self.step = CPU_CLOCK / self.rate
  let dt = 1.0 / self.rate
  let hp_rc = 1.0 / (2.0 * pi * 90.0)
  let lp_rc = 1.0 / (2.0 * pi * 14000.0)
  self.hp_alpha = hp_rc / (hp_rc + dt)
  self.lp_alpha = dt / (lp_rc + dt)
  let capacity = self.rate.to_int() + 1
  if self.buffer.length() < capacity {
    let bigger = FixedArray::make(capacity, 0.0)
    for i in 0..<self.available {
      bigger[i] = self.buffer[(self.read_pos + i) % self.buffer.length()]
    }
    self.buffer = bigger
    self.read_pos = 0
    self.write_pos = self.available
  }
}

///|
/// Adds the mixer output of one CPU cycle.
#inline
fn Resampler::add(self : Resampler, value : Double) -> Unit {
  if self.rate == 0.0 {
    return
  }
  self.sum += value
  self.count += 1
  self.phase += 1.0
  if self.phase >= self.step {
    self.phase -= self.step
    self.emit(self.sum / self.count.to_double())
    self.sum = 0.0
    self.count = 0
  }
}

///|
fn Resampler::emit(self : Resampler, value : Double) -> Unit {
  self.hp_out = self.hp_alpha * (self.hp_out + value - self.hp_in)
  self.hp_in = value
  self.lp_out = self.lp_out + self.lp_alpha * (self.hp_out - self.lp_out)
  let capacity = self.buffer.length()
  self.buffer[self.write_pos] = self.lp_out
  self.write_pos = (self.write_pos + 1) % capacity
  if self.available == capacity {
    // Nobody is reading: drop the oldest sample.
    self.read_pos = (self.read_pos + 1) % capacity
  } else {
    self.available += 1
  }
}

///|
fn Resampler::take(self : Resampler, out : FixedArray[Double]) -> Int32 {
  let n = if self.available < out.length() {
    self.available
  } else {
    out.length()
  }
  let capacity = self.buffer.length()
  for i in 0..<n {
    out[i] = self.buffer[(self.read_pos + i) % capacity]
  }
  self.read_pos = (self.read_pos + n) % capacity
  self.available -= n
  n
}

///|
/// Sets the output sample rate in Hz (default 48000). 0 stops sampling,
/// which saves time in headless runs that do not need sound.
pub fn Apu::set_sample_rate(self : Apu, rate : Double) -> Unit {
  self.resampler.set_rate(rate)
}

///|
/// Number of finished samples waiting to be taken.
pub fn Apu::samples_available(self : Apu) -> Int32 {
  self.resampler.available
}

///|
/// Moves up to `out.length()` samples into `out`, oldest first, and returns
/// how many were written. Samples are roughly in -1.0..1.0.
pub fn Apu::take_samples(self : Apu, out : FixedArray[Double]) -> Int32 {
  self.resampler.take(out)
}
