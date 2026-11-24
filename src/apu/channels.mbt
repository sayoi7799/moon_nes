// The tone channels: two pulse waves, the triangle and the noise channel.
// Each channel produces a 4-bit level; mixing happens in mixer.mbt.
// Reference: https://www.nesdev.org/wiki/APU_Envelope,
// https://www.nesdev.org/wiki/APU_Pulse, https://www.nesdev.org/wiki/APU_Triangle,
// https://www.nesdev.org/wiki/APU_Noise

///|
/// Duty sequences, read in the order 0, 7, 6, ..., 1 by the sequencer.
let duty_table : FixedArray[Int32] = [0x01, 0x03, 0x0F, 0xFC]

///|
/// NTSC noise periods in CPU cycles.
let noise_periods : FixedArray[Int32] = [
  4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068,
]

///|
/// Volume envelope shared by the pulse and noise channels.
priv struct Envelope {
  mut start : Bool
  mut divider : Int32
  mut decay : Int32
  mut looping : Bool
  mut constant : Bool
  mut volume : Int32
}

///|
fn Envelope::new() -> Envelope {
  {
    start: false,
    divider: 0,
    decay: 0,
    looping: false,
    constant: false,
    volume: 0,
  }
}

///|
/// $4000/$4004/$400C bits 5-0.
fn Envelope::write(self : Envelope, value : Int32) -> Unit {
  self.looping = (value & 0x20) != 0
  self.constant = (value & 0x10) != 0
  self.volume = value & 0x0F
}

///|
/// Quarter-frame clock.
fn Envelope::clock(self : Envelope) -> Unit {
  if self.start {
    self.start = false
    self.decay = 15
    self.divider = self.volume
  } else if self.divider == 0 {
    self.divider = self.volume
    if self.decay > 0 {
      self.decay -= 1
    } else if self.looping {
      self.decay = 15
    }
  } else {
    self.divider -= 1
  }
}

///|
fn Envelope::output(self : Envelope) -> Int32 {
  if self.constant {
    self.volume
  } else {
    self.decay
  }
}

///|
priv struct Pulse {
  /// Pulse 1 negates with ones' complement, pulse 2 with two's complement.
  ones_complement : Bool
  envelope : Envelope
  mut duty : Int32
  mut step : Int32
  mut period : Int32
  mut timer : Int32
  mut sweep_enabled : Bool
  mut sweep_period : Int32
  mut sweep_negate : Bool
  mut sweep_shift : Int32
  mut sweep_reload : Bool
  mut sweep_counter : Int32
}

///|
fn Pulse::new(ones_complement : Bool) -> Pulse {
  {
    ones_complement,
    envelope: Envelope::new(),
    duty: 0,
    step: 0,
    period: 0,
    timer: 0,
    sweep_enabled: false,
    sweep_period: 0,
    sweep_negate: false,
    sweep_shift: 0,
    sweep_reload: false,
    sweep_counter: 0,
  }
}

///|
/// Writes one of the four pulse registers; `reg` is the address & 3.
fn Pulse::write(self : Pulse, reg : Int32, value : Int32) -> Unit {
  match reg {
    0 => {
      self.duty = value >> 6
      self.envelope.write(value)
    }
    1 => {
      self.sweep_enabled = (value & 0x80) != 0
      self.sweep_period = (value >> 4) & 7
      self.sweep_negate = (value & 0x08) != 0
      self.sweep_shift = value & 7
      self.sweep_reload = true
    }
    2 => self.period = (self.period & 0x700) | value
    _ => {
      self.period = (self.period & 0xFF) | ((value & 7) << 8)
      self.step = 0
      self.envelope.start = true
    }
  }
}

///|
/// The period the sweep unit would set next.
fn Pulse::sweep_target(self : Pulse) -> Int32 {
  let change = self.period >> self.sweep_shift
  if self.sweep_negate {
    let target = self.period -
      change -
      (if self.ones_complement { 1 } else { 0 })
    if target < 0 {
      0
    } else {
      target
    }
  } else {
    self.period + change
  }
}

///|
/// Short periods and sweep overflow silence the channel, even with the
/// sweep disabled.
fn Pulse::muted(self : Pulse) -> Bool {
  self.period < 8 || self.sweep_target() > 0x7FF
}

///|
/// Half-frame clock.
fn Pulse::clock_sweep(self : Pulse) -> Unit {
  if self.sweep_counter == 0 &&
    self.sweep_enabled &&
    self.sweep_shift != 0 &&
    !self.muted() {
    self.period = self.sweep_target()
  }
  if self.sweep_counter == 0 || self.sweep_reload {
    self.sweep_counter = self.sweep_period
    self.sweep_reload = false
  } else {
    self.sweep_counter -= 1
  }
}

///|
/// Clocked once per APU cycle (every second CPU cycle).
fn Pulse::clock_timer(self : Pulse) -> Unit {
  if self.timer == 0 {
    self.timer = self.period
    self.step = (self.step - 1) & 7
  } else {
    self.timer -= 1
  }
}

///|
fn Pulse::output(self : Pulse, length : Int32) -> Int32 {
  if length == 0 ||
    self.muted() ||
    ((duty_table[self.duty] >> self.step) & 1) == 0 {
    0
  } else {
    self.envelope.output()
  }
}

///|
priv struct Triangle {
  mut control : Bool
  mut reload_value : Int32
  mut linear : Int32
  mut reload : Bool
  mut period : Int32
  mut timer : Int32
  mut step : Int32
}

///|
fn Triangle::new() -> Triangle {
  {
    control: false,
    reload_value: 0,
    linear: 0,
    reload: false,
    period: 0,
    timer: 0,
    step: 0,
  }
}

///|
/// Writes $4008-$400B; `reg` is the address & 3.
fn Triangle::write(self : Triangle, reg : Int32, value : Int32) -> Unit {
  match reg {
    0 => {
      self.control = (value & 0x80) != 0
      self.reload_value = value & 0x7F
    }
    1 => ()
    2 => self.period = (self.period & 0x700) | value
    _ => {
      self.period = (self.period & 0xFF) | ((value & 7) << 8)
      self.reload = true
    }
  }
}

///|
/// Quarter-frame clock of the linear counter.
fn Triangle::clock_linear(self : Triangle) -> Unit {
  if self.reload {
    self.linear = self.reload_value
  } else if self.linear > 0 {
    self.linear -= 1
  }
  if !self.control {
    self.reload = false
  }
}

///|
/// Clocked every CPU cycle. Periods below 2 would produce an ultrasonic
/// tone that only adds noise after filtering, so the sequencer holds
/// instead, as most emulators do.
fn Triangle::clock_timer(self : Triangle, length : Int32) -> Unit {
  if self.timer == 0 {
    self.timer = self.period
    if self.linear > 0 && length > 0 && self.period >= 2 {
      self.step = (self.step + 1) & 31
    }
  } else {
    self.timer -= 1
  }
}

///|
/// 15, 14, ..., 0, 0, 1, ..., 15. A halted triangle keeps its last level.
fn Triangle::output(self : Triangle) -> Int32 {
  if self.step < 16 {
    15 - self.step
  } else {
    self.step - 16
  }
}

///|
priv struct Noise {
  envelope : Envelope
  mut short_mode : Bool
  mut period : Int32
  mut timer : Int32
  mut shift : Int32
}

///|
fn Noise::new() -> Noise {
  {
    envelope: Envelope::new(),
    short_mode: false,
    period: noise_periods[0],
    timer: 0,
    shift: 1,
  }
}

///|
/// Writes $400C-$400F; `reg` is the address & 3.
fn Noise::write(self : Noise, reg : Int32, value : Int32) -> Unit {
  match reg {
    0 => self.envelope.write(value)
    1 => ()
    2 => {
      self.short_mode = (value & 0x80) != 0
      self.period = noise_periods[value & 0x0F]
    }
    _ => self.envelope.start = true
  }
}

///|
/// Clocked every CPU cycle; the shift register moves once per period.
fn Noise::clock_timer(self : Noise) -> Unit {
  if self.timer == 0 {
    self.timer = self.period - 1
    let tap = if self.short_mode { 6 } else { 1 }
    let feedback = (self.shift ^ (self.shift >> tap)) & 1
    self.shift = (self.shift >> 1) | (feedback << 14)
  } else {
    self.timer -= 1
  }
}

///|
fn Noise::output(self : Noise, length : Int32) -> Int32 {
  if length == 0 || (self.shift & 1) != 0 {
    0
  } else {
    self.envelope.output()
  }
}
