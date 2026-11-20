// The 2A03 APU: frame counter, frame IRQ, length counters and the sound
// channels (channels.mbt).
//
// The frame counter is also the CPU's only IRQ source on these boards, and
// many CPU test ROMs use it as a clock.
// Reference: https://www.nesdev.org/wiki/APU_Frame_Counter,
// https://www.nesdev.org/wiki/APU_Length_Counter

///|
let length_table : FixedArray[Int32] = [
  10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14, 12, 16, 24, 18, 48,
  20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30,
]

///|
pub struct Apu {
  /// Remaining length of pulse 1, pulse 2, triangle and noise.
  priv length : FixedArray[Int32]
  priv halt : FixedArray[Bool]
  priv enabled : FixedArray[Bool]
  priv mut five_step : Bool
  priv mut irq_inhibit : Bool
  priv mut frame_irq : Bool
  /// CPU cycles since the frame sequencer was last reset.
  priv mut counter : Int32
  /// Cycles until a pending $4017 write takes effect, or -1.
  priv mut reset_delay : Int32
  priv mut pending_mode : Int32
  priv mut cycle_parity : Bool
  priv pulse1 : Pulse
  priv pulse2 : Pulse
  priv triangle : Triangle
  priv noise : Noise
}

///|
pub fn Apu::new() -> Apu {
  {
    length: FixedArray::make(4, 0),
    halt: FixedArray::make(4, false),
    enabled: FixedArray::make(4, false),
    five_step: false,
    irq_inhibit: false,
    frame_irq: false,
    counter: 0,
    reset_delay: -1,
    pending_mode: 0,
    cycle_parity: false,
    pulse1: Pulse::new(true),
    pulse2: Pulse::new(false),
    triangle: Triangle::new(),
    noise: Noise::new(),
  }
}

///|
/// IRQ output of the frame counter.
pub fn Apu::irq_line(self : Apu) -> Bool {
  self.frame_irq
}

///|
/// Quarter-frame clock: envelopes and the triangle's linear counter.
fn Apu::clock_quarter_frame(self : Apu) -> Unit {
  self.pulse1.envelope.clock()
  self.pulse2.envelope.clock()
  self.noise.envelope.clock()
  self.triangle.clock_linear()
}

///|
/// Half-frame clock: length counters and sweep units. Every half frame is
/// also a quarter frame.
fn Apu::clock_half_frame(self : Apu) -> Unit {
  self.clock_quarter_frame()
  for i in 0..<4 {
    if !self.halt[i] && self.length[i] > 0 {
      self.length[i] -= 1
    }
  }
  self.pulse1.clock_sweep()
  self.pulse2.clock_sweep()
}

///|
/// Advances the APU by one CPU cycle.
pub fn Apu::step(self : Apu) -> Unit {
  self.cycle_parity = !self.cycle_parity
  if self.cycle_parity {
    self.pulse1.clock_timer()
    self.pulse2.clock_timer()
  }
  self.triangle.clock_timer(self.length[2])
  self.noise.clock_timer()
  self.step_frame_counter()
}

///|
/// Advances the frame sequencer by one CPU cycle. The step numbers are the
/// wiki's APU cycles times two plus one.
fn Apu::step_frame_counter(self : Apu) -> Unit {
  if self.reset_delay > 0 {
    self.reset_delay -= 1
    if self.reset_delay == 0 {
      self.reset_delay = -1
      self.five_step = (self.pending_mode & 0x80) != 0
      self.counter = 0
      if self.five_step {
        self.clock_half_frame()
      }
      return
    }
  }
  self.counter += 1
  let c = self.counter
  if c == 7457 || c == 22371 {
    self.clock_quarter_frame()
  }
  if self.five_step {
    if c == 14913 || c == 37281 {
      self.clock_half_frame()
    } else if c >= 37282 {
      self.counter = 0
    }
  } else {
    if c == 14913 || c == 29829 {
      self.clock_half_frame()
    }
    if c >= 29828 && !self.irq_inhibit {
      self.frame_irq = true
    }
    if c >= 29830 {
      self.counter = 0
    }
  }
}

///|
/// $4015 read: length counter status and frame IRQ (which the read clears).
pub fn Apu::read_status(self : Apu) -> Int32 {
  let mut v = 0
  for i in 0..<4 {
    if self.length[i] > 0 {
      v = v | (1 << i)
    }
  }
  if self.frame_irq {
    v = v | 0x40
  }
  self.frame_irq = false
  v
}

///|
pub fn Apu::peek_status(self : Apu) -> Int32 {
  let mut v = if self.frame_irq { 0x40 } else { 0 }
  for i in 0..<4 {
    if self.length[i] > 0 {
      v = v | (1 << i)
    }
  }
  v
}

///|
/// Writes to $4000-$4013, $4015 and $4017.
pub fn Apu::write(self : Apu, addr : Int32, value : Int32) -> Unit {
  match addr {
    0x4000..<=0x4003 => self.pulse1.write(addr & 3, value)
    0x4004..<=0x4007 => self.pulse2.write(addr & 3, value)
    0x4008..<=0x400B => self.triangle.write(addr & 3, value)
    0x400C..<=0x400F => self.noise.write(addr & 3, value)
    _ => ()
  }
  match addr {
    // Length counter halt bits.
    0x4000 => self.halt[0] = (value & 0x20) != 0
    0x4004 => self.halt[1] = (value & 0x20) != 0
    0x4008 => self.halt[2] = (value & 0x80) != 0
    0x400C => self.halt[3] = (value & 0x20) != 0
    // Length counter loads.
    0x4003 | 0x4007 | 0x400B | 0x400F => {
      let ch = (addr - 0x4003) >> 2
      if self.enabled[ch] {
        self.length[ch] = length_table[value >> 3]
      }
    }
    0x4015 =>
      for i in 0..<4 {
        self.enabled[i] = (value & (1 << i)) != 0
        if !self.enabled[i] {
          self.length[i] = 0
        }
      }
    0x4017 => {
      self.irq_inhibit = (value & 0x40) != 0
      if self.irq_inhibit {
        self.frame_irq = false
      }
      // The sequencer restarts 3 or 4 CPU cycles later, depending on
      // whether the write lands on an APU cycle boundary.
      self.pending_mode = value
      self.reset_delay = if self.cycle_parity { 4 } else { 3 }
    }
    _ => ()
  }
}
