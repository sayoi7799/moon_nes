// Addressing modes and the opcode dispatch table.

///|
/// Address of the immediate operand (the byte at PC).
#inline
fn[B] Cpu::imm(self : Cpu[B]) -> Int32 {
  let a = self.pc
  self.pc = (self.pc + 1) & 0xFFFF
  a
}

///|
fn[B : CpuBus] Cpu::zp(self : Cpu[B]) -> Int32 {
  self.fetch()
}

///|
/// Zero page indexed: the base address is read once (dummy) before indexing.
fn[B : CpuBus] Cpu::zp_idx(self : Cpu[B], index : Int32) -> Int32 {
  let base = self.fetch()
  self.rd(base) |> ignore
  (base + index) & 0xFF
}

///|
fn[B : CpuBus] Cpu::abs(self : Cpu[B]) -> Int32 {
  let lo = self.fetch()
  let hi = self.fetch()
  lo | (hi << 8)
}

///|
/// Absolute indexed. Reads touch the un-carried address only when the page
/// is crossed; writes and read-modify-writes always do.
fn[B : CpuBus] Cpu::abs_idx(
  self : Cpu[B],
  index : Int32,
  always : Bool,
) -> Int32 {
  let base = self.abs()
  let addr = (base + index) & 0xFFFF
  if always || ((base ^ addr) & 0xFF00) != 0 {
    self.rd((base & 0xFF00) | (addr & 0xFF)) |> ignore
  }
  addr
}

///|
/// (zp,X): the pointer wraps inside the zero page.
fn[B : CpuBus] Cpu::ind_x(self : Cpu[B]) -> Int32 {
  let ptr = self.fetch()
  self.rd(ptr) |> ignore
  let p = (ptr + self.x) & 0xFF
  let lo = self.rd(p)
  let hi = self.rd((p + 1) & 0xFF)
  lo | (hi << 8)
}

///|
/// Pointer base for (zp),Y before Y is added.
fn[B : CpuBus] Cpu::ind_y_base(self : Cpu[B]) -> Int32 {
  let ptr = self.fetch()
  let lo = self.rd(ptr)
  let hi = self.rd((ptr + 1) & 0xFF)
  lo | (hi << 8)
}

///|
fn[B : CpuBus] Cpu::ind_y(self : Cpu[B], always : Bool) -> Int32 {
  let base = self.ind_y_base()
  let addr = (base + self.y) & 0xFFFF
  if always || ((base ^ addr) & 0xFF00) != 0 {
    self.rd((base & 0xFF00) | (addr & 0xFF)) |> ignore
  }
  addr
}

///|
/// Operations that read one operand byte.
priv enum ReadOp {
  Lda
  Ldx
  Ldy
  Ora
  And
  Eor
  Adc
  Sbc
  Cmp
  Cpx
  Cpy
  Bit
  Lax
  Nop
  Anc
  Alr
  Arr
  Axs
  Ane
  Lxa
}

///|
/// Read-modify-write operations, including the unofficial combined ones.
priv enum RmwOp {
  Asl
  Lsr
  Rol
  Ror
  Inc
  Dec
  Slo
  Rla
  Sre
  Rra
  Dcp
  Isc
}

///|
fn[B] Cpu::adc(self : Cpu[B], v : Int32) -> Unit {
  let sum = self.a + v + (self.p & FLAG_C)
  self.set_flag(FLAG_C, sum > 0xFF)
  self.set_flag(FLAG_V, ((self.a ^ sum) & (v ^ sum) & 0x80) != 0)
  self.a = sum & 0xFF
  self.set_zn(self.a)
}

///|
fn[B] Cpu::compare(self : Cpu[B], reg : Int32, v : Int32) -> Unit {
  self.set_flag(FLAG_C, reg >= v)
  self.set_zn((reg - v) & 0xFF)
}

///|
fn[B] Cpu::apply_read(self : Cpu[B], op : ReadOp, v : Int32) -> Unit {
  match op {
    Lda => {
      self.a = v
      self.set_zn(v)
    }
    Ldx => {
      self.x = v
      self.set_zn(v)
    }
    Ldy => {
      self.y = v
      self.set_zn(v)
    }
    Ora => {
      self.a = self.a | v
      self.set_zn(self.a)
    }
    And => {
      self.a = self.a & v
      self.set_zn(self.a)
    }
    Eor => {
      self.a = self.a ^ v
      self.set_zn(self.a)
    }
    Adc => self.adc(v)
    Sbc => self.adc(v ^ 0xFF)
    Cmp => self.compare(self.a, v)
    Cpx => self.compare(self.x, v)
    Cpy => self.compare(self.y, v)
    Bit => {
      self.set_flag(FLAG_Z, (self.a & v) == 0)
      self.p = (self.p & 0x3F) | (v & 0xC0)
    }
    Lax => {
      self.a = v
      self.x = v
      self.set_zn(v)
    }
    Nop => ()
    Anc => {
      self.a = self.a & v
      self.set_zn(self.a)
      self.set_flag(FLAG_C, (self.a & 0x80) != 0)
    }
    Alr => {
      let t = self.a & v
      self.set_flag(FLAG_C, (t & 1) != 0)
      self.a = t >> 1
      self.set_zn(self.a)
    }
    Arr => {
      let t = self.a & v
      self.a = (t >> 1) | ((self.p & FLAG_C) << 7)
      self.set_zn(self.a)
      self.set_flag(FLAG_C, (self.a & 0x40) != 0)
      self.set_flag(FLAG_V, (((self.a >> 6) ^ (self.a >> 5)) & 1) != 0)
    }
    Axs => {
      let t = (self.a & self.x) - v
      self.set_flag(FLAG_C, t >= 0)
      self.x = t & 0xFF
      self.set_zn(self.x)
    }
    // Unstable on real chips; these use the commonly observed constants.
    Ane => {
      self.a = (self.a | 0xEE) & self.x & v
      self.set_zn(self.a)
    }
    Lxa => {
      self.a = (self.a | 0xEE) & v
      self.x = self.a
      self.set_zn(self.a)
    }
  }
}

///|
fn[B] Cpu::apply_rmw(self : Cpu[B], op : RmwOp, v : Int32) -> Int32 {
  match op {
    Asl | Slo => {
      self.set_flag(FLAG_C, (v & 0x80) != 0)
      let r = (v << 1) & 0xFF
      if op is Slo {
        self.apply_read(Ora, r)
      } else {
        self.set_zn(r)
      }
      r
    }
    Lsr | Sre => {
      self.set_flag(FLAG_C, (v & 1) != 0)
      let r = v >> 1
      if op is Sre {
        self.apply_read(Eor, r)
      } else {
        self.set_zn(r)
      }
      r
    }
    Rol | Rla => {
      let r = ((v << 1) | (self.p & FLAG_C)) & 0xFF
      self.set_flag(FLAG_C, (v & 0x80) != 0)
      if op is Rla {
        self.apply_read(And, r)
      } else {
        self.set_zn(r)
      }
      r
    }
    Ror | Rra => {
      let r = (v >> 1) | ((self.p & FLAG_C) << 7)
      self.set_flag(FLAG_C, (v & 1) != 0)
      if op is Rra {
        self.adc(r)
      } else {
        self.set_zn(r)
      }
      r
    }
    Inc | Isc => {
      let r = (v + 1) & 0xFF
      if op is Isc {
        self.adc(r ^ 0xFF)
      } else {
        self.set_zn(r)
      }
      r
    }
    Dec | Dcp => {
      let r = (v - 1) & 0xFF
      if op is Dcp {
        self.compare(self.a, r)
      } else {
        self.set_zn(r)
      }
      r
    }
  }
}

///|
#inline
fn[B : CpuBus] Cpu::read_op(self : Cpu[B], op : ReadOp, addr : Int32) -> Unit {
  self.apply_read(op, self.rd(addr))
}

///|
/// Read-modify-write: read, write the old value back (dummy), write result.
fn[B : CpuBus] Cpu::rmw(self : Cpu[B], op : RmwOp, addr : Int32) -> Unit {
  let v = self.rd(addr)
  self.wr(addr, v)
  self.wr(addr, self.apply_rmw(op, v))
}

///|
fn[B : CpuBus] Cpu::rmw_acc(self : Cpu[B], op : RmwOp) -> Unit {
  self.rd(self.pc) |> ignore
  self.a = self.apply_rmw(op, self.a)
}

///|
/// Two-cycle implied instruction: the second cycle is a dummy read of PC.
#inline
fn[B : CpuBus] Cpu::implied(self : Cpu[B]) -> Unit {
  self.rd(self.pc) |> ignore
}

///|
fn[B : CpuBus] Cpu::branch(self : Cpu[B], taken : Bool) -> Unit {
  let off = self.fetch()
  if !taken {
    return
  }
  // A taken branch that stays on the same page does not poll interrupts
  // on its extra cycle, delaying a pending interrupt by one instruction.
  let target = (self.pc + (if off >= 0x80 { off - 0x100 } else { off })) &
    0xFFFF
  self.bus.read(self.pc) |> ignore
  self.cycles += 1
  if ((target ^ self.pc) & 0xFF00) != 0 {
    self.poll(true)
    self.rd((self.pc & 0xFF00) | (target & 0xFF)) |> ignore
  } else {
    self.poll(false)
  }
  self.pc = target
}

///|
/// SHA/SHX/SHY/TAS: store `value & (high byte of base + 1)`. When the index
/// carries into the high byte, that same value replaces the high byte.
fn[B : CpuBus] Cpu::store_high_and(
  self : Cpu[B],
  base : Int32,
  index : Int32,
  value : Int32,
) -> Unit {
  let addr = (base + index) & 0xFFFF
  self.rd((base & 0xFF00) | (addr & 0xFF)) |> ignore
  let v = value & ((base >> 8) + 1) & 0xFF
  let target = if ((base ^ addr) & 0xFF00) != 0 {
    (v << 8) | (addr & 0xFF)
  } else {
    addr
  }
  self.wr(target, v)
}

///|
fn[B : CpuBus] Cpu::execute(self : Cpu[B], op : Int32) -> Unit {
  match op {
    // --- loads, ALU ops and compares (official) ---
    0xA9 => self.read_op(Lda, self.imm())
    0xA5 => self.read_op(Lda, self.zp())
    0xB5 => self.read_op(Lda, self.zp_idx(self.x))
    0xAD => self.read_op(Lda, self.abs())
    0xBD => self.read_op(Lda, self.abs_idx(self.x, false))
    0xB9 => self.read_op(Lda, self.abs_idx(self.y, false))
    0xA1 => self.read_op(Lda, self.ind_x())
    0xB1 => self.read_op(Lda, self.ind_y(false))
    0xA2 => self.read_op(Ldx, self.imm())
    0xA6 => self.read_op(Ldx, self.zp())
    0xB6 => self.read_op(Ldx, self.zp_idx(self.y))
    0xAE => self.read_op(Ldx, self.abs())
    0xBE => self.read_op(Ldx, self.abs_idx(self.y, false))
    0xA0 => self.read_op(Ldy, self.imm())
    0xA4 => self.read_op(Ldy, self.zp())
    0xB4 => self.read_op(Ldy, self.zp_idx(self.x))
    0xAC => self.read_op(Ldy, self.abs())
    0xBC => self.read_op(Ldy, self.abs_idx(self.x, false))
    0x09 => self.read_op(Ora, self.imm())
    0x05 => self.read_op(Ora, self.zp())
    0x15 => self.read_op(Ora, self.zp_idx(self.x))
    0x0D => self.read_op(Ora, self.abs())
    0x1D => self.read_op(Ora, self.abs_idx(self.x, false))
    0x19 => self.read_op(Ora, self.abs_idx(self.y, false))
    0x01 => self.read_op(Ora, self.ind_x())
    0x11 => self.read_op(Ora, self.ind_y(false))
    0x29 => self.read_op(And, self.imm())
    0x25 => self.read_op(And, self.zp())
    0x35 => self.read_op(And, self.zp_idx(self.x))
    0x2D => self.read_op(And, self.abs())
    0x3D => self.read_op(And, self.abs_idx(self.x, false))
    0x39 => self.read_op(And, self.abs_idx(self.y, false))
    0x21 => self.read_op(And, self.ind_x())
    0x31 => self.read_op(And, self.ind_y(false))
    0x49 => self.read_op(Eor, self.imm())
    0x45 => self.read_op(Eor, self.zp())
    0x55 => self.read_op(Eor, self.zp_idx(self.x))
    0x4D => self.read_op(Eor, self.abs())
    0x5D => self.read_op(Eor, self.abs_idx(self.x, false))
    0x59 => self.read_op(Eor, self.abs_idx(self.y, false))
    0x41 => self.read_op(Eor, self.ind_x())
    0x51 => self.read_op(Eor, self.ind_y(false))
    0x69 => self.read_op(Adc, self.imm())
    0x65 => self.read_op(Adc, self.zp())
    0x75 => self.read_op(Adc, self.zp_idx(self.x))
    0x6D => self.read_op(Adc, self.abs())
    0x7D => self.read_op(Adc, self.abs_idx(self.x, false))
    0x79 => self.read_op(Adc, self.abs_idx(self.y, false))
    0x61 => self.read_op(Adc, self.ind_x())
    0x71 => self.read_op(Adc, self.ind_y(false))
    0xE9 | 0xEB => self.read_op(Sbc, self.imm())
    0xE5 => self.read_op(Sbc, self.zp())
    0xF5 => self.read_op(Sbc, self.zp_idx(self.x))
    0xED => self.read_op(Sbc, self.abs())
    0xFD => self.read_op(Sbc, self.abs_idx(self.x, false))
    0xF9 => self.read_op(Sbc, self.abs_idx(self.y, false))
    0xE1 => self.read_op(Sbc, self.ind_x())
    0xF1 => self.read_op(Sbc, self.ind_y(false))
    0xC9 => self.read_op(Cmp, self.imm())
    0xC5 => self.read_op(Cmp, self.zp())
    0xD5 => self.read_op(Cmp, self.zp_idx(self.x))
    0xCD => self.read_op(Cmp, self.abs())
    0xDD => self.read_op(Cmp, self.abs_idx(self.x, false))
    0xD9 => self.read_op(Cmp, self.abs_idx(self.y, false))
    0xC1 => self.read_op(Cmp, self.ind_x())
    0xD1 => self.read_op(Cmp, self.ind_y(false))
    0xE0 => self.read_op(Cpx, self.imm())
    0xE4 => self.read_op(Cpx, self.zp())
    0xEC => self.read_op(Cpx, self.abs())
    0xC0 => self.read_op(Cpy, self.imm())
    0xC4 => self.read_op(Cpy, self.zp())
    0xCC => self.read_op(Cpy, self.abs())
    0x24 => self.read_op(Bit, self.zp())
    0x2C => self.read_op(Bit, self.abs())

    // --- stores ---
    0x85 => self.wr(self.zp(), self.a)
    0x95 => self.wr(self.zp_idx(self.x), self.a)
    0x8D => self.wr(self.abs(), self.a)
    0x9D => self.wr(self.abs_idx(self.x, true), self.a)
    0x99 => self.wr(self.abs_idx(self.y, true), self.a)
    0x81 => self.wr(self.ind_x(), self.a)
    0x91 => self.wr(self.ind_y(true), self.a)
    0x86 => self.wr(self.zp(), self.x)
    0x96 => self.wr(self.zp_idx(self.y), self.x)
    0x8E => self.wr(self.abs(), self.x)
    0x84 => self.wr(self.zp(), self.y)
    0x94 => self.wr(self.zp_idx(self.x), self.y)
    0x8C => self.wr(self.abs(), self.y)

    // --- read-modify-write (official) ---
    0x0A => self.rmw_acc(Asl)
    0x06 => self.rmw(Asl, self.zp())
    0x16 => self.rmw(Asl, self.zp_idx(self.x))
    0x0E => self.rmw(Asl, self.abs())
    0x1E => self.rmw(Asl, self.abs_idx(self.x, true))
    0x4A => self.rmw_acc(Lsr)
    0x46 => self.rmw(Lsr, self.zp())
    0x56 => self.rmw(Lsr, self.zp_idx(self.x))
    0x4E => self.rmw(Lsr, self.abs())
    0x5E => self.rmw(Lsr, self.abs_idx(self.x, true))
    0x2A => self.rmw_acc(Rol)
    0x26 => self.rmw(Rol, self.zp())
    0x36 => self.rmw(Rol, self.zp_idx(self.x))
    0x2E => self.rmw(Rol, self.abs())
    0x3E => self.rmw(Rol, self.abs_idx(self.x, true))
    0x6A => self.rmw_acc(Ror)
    0x66 => self.rmw(Ror, self.zp())
    0x76 => self.rmw(Ror, self.zp_idx(self.x))
    0x6E => self.rmw(Ror, self.abs())
    0x7E => self.rmw(Ror, self.abs_idx(self.x, true))
    0xE6 => self.rmw(Inc, self.zp())
    0xF6 => self.rmw(Inc, self.zp_idx(self.x))
    0xEE => self.rmw(Inc, self.abs())
    0xFE => self.rmw(Inc, self.abs_idx(self.x, true))
    0xC6 => self.rmw(Dec, self.zp())
    0xD6 => self.rmw(Dec, self.zp_idx(self.x))
    0xCE => self.rmw(Dec, self.abs())
    0xDE => self.rmw(Dec, self.abs_idx(self.x, true))

    // --- register transfers, increments, flags ---
    0xAA => {
      self.implied()
      self.x = self.a
      self.set_zn(self.x)
    }
    0xA8 => {
      self.implied()
      self.y = self.a
      self.set_zn(self.y)
    }
    0x8A => {
      self.implied()
      self.a = self.x
      self.set_zn(self.a)
    }
    0x98 => {
      self.implied()
      self.a = self.y
      self.set_zn(self.a)
    }
    0xBA => {
      self.implied()
      self.x = self.sp
      self.set_zn(self.x)
    }
    0x9A => {
      self.implied()
      self.sp = self.x
    }
    0xE8 => {
      self.implied()
      self.x = (self.x + 1) & 0xFF
      self.set_zn(self.x)
    }
    0xC8 => {
      self.implied()
      self.y = (self.y + 1) & 0xFF
      self.set_zn(self.y)
    }
    0xCA => {
      self.implied()
      self.x = (self.x - 1) & 0xFF
      self.set_zn(self.x)
    }
    0x88 => {
      self.implied()
      self.y = (self.y - 1) & 0xFF
      self.set_zn(self.y)
    }
    0x18 => {
      self.implied()
      self.set_flag(FLAG_C, false)
    }
    0x38 => {
      self.implied()
      self.set_flag(FLAG_C, true)
    }
    0x58 => {
      self.implied()
      self.set_flag(FLAG_I, false)
    }
    0x78 => {
      self.implied()
      self.set_flag(FLAG_I, true)
    }
    0xB8 => {
      self.implied()
      self.set_flag(FLAG_V, false)
    }
    0xD8 => {
      self.implied()
      self.set_flag(FLAG_D, false)
    }
    0xF8 => {
      self.implied()
      self.set_flag(FLAG_D, true)
    }
    0xEA | 0x1A | 0x3A | 0x5A | 0x7A | 0xDA | 0xFA => self.implied()

    // --- stack ---
    0x48 => {
      self.implied()
      self.push(self.a)
    }
    0x08 => {
      self.implied()
      self.push(self.p | FLAG_B | FLAG_U)
    }
    0x68 => {
      self.implied()
      self.rd(0x100 | self.sp) |> ignore
      self.a = self.pull()
      self.set_zn(self.a)
    }
    0x28 => {
      self.implied()
      self.rd(0x100 | self.sp) |> ignore
      let v = self.pull()
      self.set_p_from_stack(v)
    }

    // --- jumps, calls, returns ---
    0x4C => self.pc = self.abs()
    0x6C => {
      let ptr = self.abs()
      // The 6502 does not carry into the pointer's high byte.
      let lo = self.rd(ptr)
      let hi = self.rd((ptr & 0xFF00) | ((ptr + 1) & 0xFF))
      self.pc = lo | (hi << 8)
    }
    0x20 => {
      let lo = self.fetch()
      self.rd(0x100 | self.sp) |> ignore
      self.push(self.pc >> 8)
      self.push(self.pc & 0xFF)
      let hi = self.rd(self.pc)
      self.pc = lo | (hi << 8)
    }
    0x60 => {
      self.implied()
      self.rd(0x100 | self.sp) |> ignore
      let lo = self.pull()
      let hi = self.pull()
      self.pc = lo | (hi << 8)
      self.fetch() |> ignore
    }
    0x40 => {
      self.implied()
      self.rd(0x100 | self.sp) |> ignore
      let v = self.pull()
      self.set_p_from_stack(v)
      let lo = self.pull()
      let hi = self.pull()
      self.pc = lo | (hi << 8)
    }
    0x00 => {
      self.fetch() |> ignore
      self.interrupt(true)
    }

    // --- branches ---
    0x10 => self.branch((self.p & FLAG_N) == 0)
    0x30 => self.branch((self.p & FLAG_N) != 0)
    0x50 => self.branch((self.p & FLAG_V) == 0)
    0x70 => self.branch((self.p & FLAG_V) != 0)
    0x90 => self.branch((self.p & FLAG_C) == 0)
    0xB0 => self.branch((self.p & FLAG_C) != 0)
    0xD0 => self.branch((self.p & FLAG_Z) == 0)
    0xF0 => self.branch((self.p & FLAG_Z) != 0)

    // --- unofficial: NOPs that read an operand ---
    0x80 | 0x82 | 0x89 | 0xC2 | 0xE2 => self.read_op(Nop, self.imm())
    0x04 | 0x44 | 0x64 => self.read_op(Nop, self.zp())
    0x14 | 0x34 | 0x54 | 0x74 | 0xD4 | 0xF4 =>
      self.read_op(Nop, self.zp_idx(self.x))
    0x0C => self.read_op(Nop, self.abs())
    0x1C | 0x3C | 0x5C | 0x7C | 0xDC | 0xFC =>
      self.read_op(Nop, self.abs_idx(self.x, false))

    // --- unofficial: LAX / SAX ---
    0xA7 => self.read_op(Lax, self.zp())
    0xB7 => self.read_op(Lax, self.zp_idx(self.y))
    0xAF => self.read_op(Lax, self.abs())
    0xBF => self.read_op(Lax, self.abs_idx(self.y, false))
    0xA3 => self.read_op(Lax, self.ind_x())
    0xB3 => self.read_op(Lax, self.ind_y(false))
    0x87 => self.wr(self.zp(), self.a & self.x)
    0x97 => self.wr(self.zp_idx(self.y), self.a & self.x)
    0x8F => self.wr(self.abs(), self.a & self.x)
    0x83 => self.wr(self.ind_x(), self.a & self.x)

    // --- unofficial: immediate oddities ---
    0x0B | 0x2B => self.read_op(Anc, self.imm())
    0x4B => self.read_op(Alr, self.imm())
    0x6B => self.read_op(Arr, self.imm())
    0xCB => self.read_op(Axs, self.imm())
    0x8B => self.read_op(Ane, self.imm())
    0xAB => self.read_op(Lxa, self.imm())

    // --- unofficial: combined read-modify-write ---
    0x07 => self.rmw(Slo, self.zp())
    0x17 => self.rmw(Slo, self.zp_idx(self.x))
    0x0F => self.rmw(Slo, self.abs())
    0x1F => self.rmw(Slo, self.abs_idx(self.x, true))
    0x1B => self.rmw(Slo, self.abs_idx(self.y, true))
    0x03 => self.rmw(Slo, self.ind_x())
    0x13 => self.rmw(Slo, self.ind_y(true))
    0x27 => self.rmw(Rla, self.zp())
    0x37 => self.rmw(Rla, self.zp_idx(self.x))
    0x2F => self.rmw(Rla, self.abs())
    0x3F => self.rmw(Rla, self.abs_idx(self.x, true))
    0x3B => self.rmw(Rla, self.abs_idx(self.y, true))
    0x23 => self.rmw(Rla, self.ind_x())
    0x33 => self.rmw(Rla, self.ind_y(true))
    0x47 => self.rmw(Sre, self.zp())
    0x57 => self.rmw(Sre, self.zp_idx(self.x))
    0x4F => self.rmw(Sre, self.abs())
    0x5F => self.rmw(Sre, self.abs_idx(self.x, true))
    0x5B => self.rmw(Sre, self.abs_idx(self.y, true))
    0x43 => self.rmw(Sre, self.ind_x())
    0x53 => self.rmw(Sre, self.ind_y(true))
    0x67 => self.rmw(Rra, self.zp())
    0x77 => self.rmw(Rra, self.zp_idx(self.x))
    0x6F => self.rmw(Rra, self.abs())
    0x7F => self.rmw(Rra, self.abs_idx(self.x, true))
    0x7B => self.rmw(Rra, self.abs_idx(self.y, true))
    0x63 => self.rmw(Rra, self.ind_x())
    0x73 => self.rmw(Rra, self.ind_y(true))
    0xC7 => self.rmw(Dcp, self.zp())
    0xD7 => self.rmw(Dcp, self.zp_idx(self.x))
    0xCF => self.rmw(Dcp, self.abs())
    0xDF => self.rmw(Dcp, self.abs_idx(self.x, true))
    0xDB => self.rmw(Dcp, self.abs_idx(self.y, true))
    0xC3 => self.rmw(Dcp, self.ind_x())
    0xD3 => self.rmw(Dcp, self.ind_y(true))
    0xE7 => self.rmw(Isc, self.zp())
    0xF7 => self.rmw(Isc, self.zp_idx(self.x))
    0xEF => self.rmw(Isc, self.abs())
    0xFF => self.rmw(Isc, self.abs_idx(self.x, true))
    0xFB => self.rmw(Isc, self.abs_idx(self.y, true))
    0xE3 => self.rmw(Isc, self.ind_x())
    0xF3 => self.rmw(Isc, self.ind_y(true))

    // --- unofficial: high-byte-AND stores and LAS ---
    0x9C => self.store_high_and(self.abs(), self.x, self.y)
    0x9E => self.store_high_and(self.abs(), self.y, self.x)
    0x9F => self.store_high_and(self.abs(), self.y, self.a & self.x)
    0x93 => self.store_high_and(self.ind_y_base(), self.y, self.a & self.x)
    0x9B => {
      self.sp = self.a & self.x
      self.store_high_and(self.abs(), self.y, self.sp)
    }
    0xBB => {
      let v = self.rd(self.abs_idx(self.y, false)) & self.sp
      self.a = v
      self.x = v
      self.sp = v
      self.set_zn(v)
    }

    // --- JAM: the CPU locks up until reset ---
    _ => {
      self.rd(self.pc) |> ignore
      self.jammed = true
    }
  }
}
