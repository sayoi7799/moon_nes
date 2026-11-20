// Delta modulation channel: a 7-bit level moved by 1-bit deltas, fed by a
// memory reader that fetches sample bytes through DMA.
// Reference: https://www.nesdev.org/wiki/APU_DMC, https://www.nesdev.org/wiki/DMA

///|
/// NTSC output rates in CPU cycles.
let dmc_rates : FixedArray[Int32] = [
  428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54,
]

///|
priv struct Dmc {
  mut irq_enabled : Bool
  mut looping : Bool
  mut rate : Int32
  /// APU cycles until the next output clock.
  mut timer : Int32
  mut level : Int32
  mut sample_address : Int32
  mut sample_length : Int32
  mut address : Int32
  mut remaining : Int32
  mut buffer : Int32
  mut buffer_full : Bool
  mut shift : Int32
  mut bits_left : Int32
  mut silent : Bool
  mut irq : Bool
  /// CPU cycles until a load DMA (started by $4015) may halt the CPU.
  mut load_delay : Int32
}

///|
fn Dmc::new() -> Dmc {
  {
    irq_enabled: false,
    looping: false,
    rate: dmc_rates[0],
    timer: 0,
    level: 0,
    sample_address: 0xC000,
    sample_length: 1,
    address: 0xC000,
    remaining: 0,
    buffer: 0,
    buffer_full: false,
    shift: 0,
    bits_left: 8,
    silent: true,
    irq: false,
    load_delay: 0,
  }
}

///|
/// Writes $4010-$4013; `reg` is the address & 3.
fn Dmc::write(self : Dmc, reg : Int32, value : Int32) -> Unit {
  match reg {
    0 => {
      self.irq_enabled = (value & 0x80) != 0
      if !self.irq_enabled {
        self.irq = false
      }
      self.looping = (value & 0x40) != 0
      self.rate = dmc_rates[value & 0x0F]
    }
    1 => self.level = value & 0x7F
    2 => self.sample_address = 0xC000 | (value << 6)
    _ => self.sample_length = (value << 4) + 1
  }
}

///|
fn Dmc::restart(self : Dmc) -> Unit {
  self.address = self.sample_address
  self.remaining = self.sample_length
}

///|
/// $4015 bit 4. Enabling restarts a finished sample; the first byte is
/// fetched by a load DMA a few cycles later if the buffer is empty.
fn Dmc::set_enabled(self : Dmc, enabled : Bool) -> Unit {
  self.irq = false
  if !enabled {
    self.remaining = 0
  } else if self.remaining == 0 {
    self.restart()
    if !self.buffer_full {
      self.load_delay = 2
    }
  }
}

///|
/// Counts down a pending load DMA, one call per CPU cycle. The DMA halts
/// the CPU on a get cycle, so the delay ends only after a put cycle.
fn Dmc::step_load_delay(self : Dmc, get_cycle : Bool) -> Unit {
  if self.load_delay > 0 {
    self.load_delay -= 1
    if self.load_delay == 0 && get_cycle {
      self.load_delay = 1
    }
  }
}

///|
/// Clocked on every get cycle (once per APU cycle).
fn Dmc::clock_timer(self : Dmc) -> Unit {
  if self.timer > 0 {
    self.timer -= 1
    return
  }
  self.timer = self.rate / 2 - 1
  if !self.silent {
    if (self.shift & 1) != 0 {
      if self.level <= 125 {
        self.level += 2
      }
    } else if self.level >= 2 {
      self.level -= 2
    }
  }
  self.shift = self.shift >> 1
  self.bits_left -= 1
  if self.bits_left == 0 {
    self.bits_left = 8
    if self.buffer_full {
      self.shift = self.buffer
      self.buffer_full = false
      self.silent = false
    } else {
      self.silent = true
    }
  }
}

///|
/// True when the memory reader wants the CPU halted for a sample fetch.
fn Dmc::dma_pending(self : Dmc) -> Bool {
  self.remaining > 0 && !self.buffer_full && self.load_delay == 0
}

///|
/// Stores a fetched sample byte and advances the memory reader.
fn Dmc::fill(self : Dmc, value : Int32) -> Unit {
  self.buffer = value
  self.buffer_full = true
  self.address = if self.address == 0xFFFF { 0x8000 } else { self.address + 1 }
  self.remaining -= 1
  if self.remaining == 0 {
    if self.looping {
      self.restart()
    } else if self.irq_enabled {
      self.irq = true
    }
  }
}
