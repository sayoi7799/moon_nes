// The CPU address space of the NES.
// Reference: https://www.nesdev.org/wiki/CPU_memory_map
//
//   $0000-$1FFF  2 KiB internal RAM, mirrored every $800
//   $2000-$3FFF  PPU registers, mirrored every 8 bytes
//   $4000-$4017  APU timing registers ($4015 status, $4017 frame counter)
//   $4014        OAM DMA
//   $4016/$4017  controllers
//   $4020-$FFFF  cartridge (mapper)

///|
/// Standard controller: an 8-bit shift register loaded while strobe is high.
/// Bit order: A, B, Select, Start, Up, Down, Left, Right.
pub struct Controller {
  priv mut buttons : Int32
  priv mut shift : Int32
  priv mut strobe : Bool
}

///|
pub fn Controller::new() -> Controller {
  { buttons: 0, shift: 0, strobe: false, }
}

///|
/// Sets the buttons currently held, as a bit mask (bit 0 = A ... 7 = Right).
pub fn Controller::set_buttons(self : Controller, buttons : Int32) -> Unit {
  self.buttons = buttons & 0xFF
}

///|
fn Controller::write_strobe(self : Controller, value : Int32) -> Unit {
  self.strobe = (value & 1) != 0
  if self.strobe {
    self.shift = self.buttons
  }
}

///|
fn Controller::read_bit(self : Controller) -> Int32 {
  if self.strobe {
    return self.buttons & 1
  }
  let bit = self.shift & 1
  // After eight reads an official controller returns 1s.
  self.shift = (self.shift >> 1) | 0x80
  bit
}

///|
pub struct Bus {
  ram : FixedArray[Int32]
  ppu : @ppu.Ppu
  apu : @apu.Apu
  mapper : &@mapper.Mapper
  pad1 : Controller
  pad2 : Controller
  /// CPU cycles executed, kept by the bus so the mapper can see them.
  mut cycles : Int64
  /// Last value on the CPU data bus, returned for unmapped reads.
  priv mut open_bus : Int32
  priv mut dma_page : Int32
}

///|
pub fn Bus::new(mapper : &@mapper.Mapper) -> Bus {
  {
    ram: FixedArray::make(0x800, 0),
    ppu: @ppu.Ppu::new(mapper),
    apu: @apu.Apu::new(),
    mapper,
    pad1: Controller::new(),
    pad2: Controller::new(),
    cycles: 0,
    open_bus: 0,
    dma_page: -1,
  }
}

///|
/// One CPU cycle is three PPU dots. The access itself lands after the
/// second dot; the CPU samples NMI at the end of the cycle, one dot later.
/// This split is what the ppu_vbl_nmi timing tests require.
#inline
fn Bus::before_access(self : Bus) -> Unit {
  self.ppu.step()
  self.ppu.step()
  self.apu.step()
  self.cycles += 1L
}

///|
#inline
fn Bus::after_access(self : Bus) -> Unit {
  self.ppu.step()
}

///|
fn Bus::access_read(self : Bus, addr : Int32) -> Int32 {
  if addr < 0x2000 {
    self.ram[addr & 0x7FF]
  } else if addr < 0x4000 {
    self.ppu.read_register(addr)
  } else if addr == 0x4016 {
    (self.open_bus & 0xE0) | self.pad1.read_bit()
  } else if addr == 0x4017 {
    (self.open_bus & 0xE0) | self.pad2.read_bit()
  } else if addr == 0x4015 {
    self.apu.read_status() | (self.open_bus & 0x20)
  } else if addr < 0x4020 {
    // The other APU registers are write-only.
    self.open_bus
  } else {
    let v = self.mapper.cpu_read(addr)
    if v < 0 {
      self.open_bus
    } else {
      v
    }
  }
}

///|
pub impl @cpu.CpuBus for Bus with fn read(self, addr) {
  self.before_access()
  let v = self.access_read(addr)
  // $4015 is inside the CPU, so reading it leaves the external bus alone.
  if addr != 0x4015 {
    self.open_bus = v
  }
  self.after_access()
  v
}

///|
pub impl @cpu.CpuBus for Bus with fn write(self, addr, value) {
  self.before_access()
  self.access_write(addr, value)
  self.after_access()
}

///|
fn Bus::access_write(self : Bus, addr : Int32, value : Int32) -> Unit {
  self.open_bus = value
  if addr < 0x2000 {
    self.ram[addr & 0x7FF] = value
  } else if addr < 0x4000 {
    self.ppu.write_register(addr, value)
  } else if addr == 0x4014 {
    self.dma_page = value
  } else if addr == 0x4016 {
    self.pad1.write_strobe(value)
    self.pad2.write_strobe(value)
  } else if addr < 0x4018 {
    self.apu.write(addr, value)
  } else if addr >= 0x4020 {
    self.mapper.cpu_write(addr, value, self.cycles)
  }
}

///|
pub impl @cpu.CpuBus for Bus with fn peek(self, addr) {
  if addr < 0x2000 {
    self.ram[addr & 0x7FF]
  } else if addr < 0x4000 {
    self.ppu.peek_register(addr)
  } else if addr < 0x4020 {
    // I/O registers are not peekable; show $FF like nestest.log does.
    0xFF
  } else {
    let v = self.mapper.cpu_read(addr)
    if v < 0 {
      0xFF
    } else {
      v
    }
  }
}

///|
pub impl @cpu.CpuBus for Bus with fn nmi_line(self) {
  self.ppu.nmi_line()
}

///|
pub impl @cpu.CpuBus for Bus with fn irq_line(self) {
  self.apu.irq_line()
}

///|
pub impl @cpu.CpuBus for Bus with fn take_dma_request(self) {
  let p = self.dma_page
  self.dma_page = -1
  p
}
