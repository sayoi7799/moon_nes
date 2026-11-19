// Disassembler and nestest.log-compatible trace output.

///|
pub(all) enum Mode {
  Imp
  Acc
  Imm
  Zp
  Zpx
  Zpy
  Abs
  Abx
  Aby
  Ind
  Izx
  Izy
  Rel
}

///|
/// Instruction length in bytes for an addressing mode.
pub fn Mode::length(self : Mode) -> Int32 {
  match self {
    Imp | Acc => 1
    Imm | Zp | Zpx | Zpy | Izx | Izy | Rel => 2
    Abs | Abx | Aby | Ind => 3
  }
}

///|
/// One row per opcode. A leading `*` marks unofficial opcodes, using the
/// same mnemonics as nestest.log.
let opcode_table : FixedArray[String] = [
  "BRK imp", "ORA izx", "*JAM imp", "*SLO izx", "*NOP zp", "ORA zp", "ASL zp", "*SLO zp",
  "PHP imp", "ORA imm", "ASL acc", "*ANC imm", "*NOP abs", "ORA abs", "ASL abs",
  "*SLO abs", "BPL rel", "ORA izy", "*JAM imp", "*SLO izy", "*NOP zpx", "ORA zpx",
  "ASL zpx", "*SLO zpx", "CLC imp", "ORA aby", "*NOP imp", "*SLO aby", "*NOP abx",
  "ORA abx", "ASL abx", "*SLO abx", "JSR abs", "AND izx", "*JAM imp", "*RLA izx",
  "BIT zp", "AND zp", "ROL zp", "*RLA zp", "PLP imp", "AND imm", "ROL acc", "*ANC imm",
  "BIT abs", "AND abs", "ROL abs", "*RLA abs", "BMI rel", "AND izy", "*JAM imp",
  "*RLA izy", "*NOP zpx", "AND zpx", "ROL zpx", "*RLA zpx", "SEC imp", "AND aby",
  "*NOP imp", "*RLA aby", "*NOP abx", "AND abx", "ROL abx", "*RLA abx", "RTI imp",
  "EOR izx", "*JAM imp", "*SRE izx", "*NOP zp", "EOR zp", "LSR zp", "*SRE zp", "PHA imp",
  "EOR imm", "LSR acc", "*ALR imm", "JMP abs", "EOR abs", "LSR abs", "*SRE abs",
  "BVC rel", "EOR izy", "*JAM imp", "*SRE izy", "*NOP zpx", "EOR zpx", "LSR zpx",
  "*SRE zpx", "CLI imp", "EOR aby", "*NOP imp", "*SRE aby", "*NOP abx", "EOR abx",
  "LSR abx", "*SRE abx", "RTS imp", "ADC izx", "*JAM imp", "*RRA izx", "*NOP zp",
  "ADC zp", "ROR zp", "*RRA zp", "PLA imp", "ADC imm", "ROR acc", "*ARR imm", "JMP ind",
  "ADC abs", "ROR abs", "*RRA abs", "BVS rel", "ADC izy", "*JAM imp", "*RRA izy",
  "*NOP zpx", "ADC zpx", "ROR zpx", "*RRA zpx", "SEI imp", "ADC aby", "*NOP imp",
  "*RRA aby", "*NOP abx", "ADC abx", "ROR abx", "*RRA abx", "*NOP imm", "STA izx",
  "*NOP imm", "*SAX izx", "STY zp", "STA zp", "STX zp", "*SAX zp", "DEY imp", "*NOP imm",
  "TXA imp", "*ANE imm", "STY abs", "STA abs", "STX abs", "*SAX abs", "BCC rel",
  "STA izy", "*JAM imp", "*SHA izy", "STY zpx", "STA zpx", "STX zpy", "*SAX zpy",
  "TYA imp", "STA aby", "TXS imp", "*TAS aby", "*SHY abx", "STA abx", "*SHX aby",
  "*SHA aby", "LDY imm", "LDA izx", "LDX imm", "*LAX izx", "LDY zp", "LDA zp", "LDX zp",
  "*LAX zp", "TAY imp", "LDA imm", "TAX imp", "*LXA imm", "LDY abs", "LDA abs", "LDX abs",
  "*LAX abs", "BCS rel", "LDA izy", "*JAM imp", "*LAX izy", "LDY zpx", "LDA zpx",
  "LDX zpy", "*LAX zpy", "CLV imp", "LDA aby", "TSX imp", "*LAS aby", "LDY abx",
  "LDA abx", "LDX aby", "*LAX aby", "CPY imm", "CMP izx", "*NOP imm", "*DCP izx",
  "CPY zp", "CMP zp", "DEC zp", "*DCP zp", "INY imp", "CMP imm", "DEX imp", "*AXS imm",
  "CPY abs", "CMP abs", "DEC abs", "*DCP abs", "BNE rel", "CMP izy", "*JAM imp",
  "*DCP izy", "*NOP zpx", "CMP zpx", "DEC zpx", "*DCP zpx", "CLD imp", "CMP aby",
  "*NOP imp", "*DCP aby", "*NOP abx", "CMP abx", "DEC abx", "*DCP abx", "CPX imm",
  "SBC izx", "*NOP imm", "*ISB izx", "CPX zp", "SBC zp", "INC zp", "*ISB zp", "INX imp",
  "SBC imm", "NOP imp", "*SBC imm", "CPX abs", "SBC abs", "INC abs", "*ISB abs",
  "BEQ rel", "SBC izy", "*JAM imp", "*ISB izy", "*NOP zpx", "SBC zpx", "INC zpx",
  "*ISB zpx", "SED imp", "SBC aby", "*NOP imp", "*ISB aby", "*NOP abx", "SBC abx",
  "INC abx", "*ISB abx",
]

///|
pub struct OpcodeInfo {
  mnemonic : String
  mode : Mode
  official : Bool
}

///|
pub fn opcode_info(opcode : Int32) -> OpcodeInfo {
  let entry = opcode_table[opcode & 0xFF]
  let official = !entry.has_prefix("*")
  let start = if official { 0 } else { 1 }
  let mnemonic = entry.exact_view(start~, end=start + 3).to_owned()
  let mode = match entry.exact_view(start=start + 4).to_owned() {
    "imp" => Imp
    "acc" => Acc
    "imm" => Imm
    "zp" => Zp
    "zpx" => Zpx
    "zpy" => Zpy
    "abs" => Abs
    "abx" => Abx
    "aby" => Aby
    "ind" => Ind
    "izx" => Izx
    "izy" => Izy
    _ => Rel
  }
  { mnemonic, mode, official, }
}

///|
let hex_digits = "0123456789ABCDEF"

///|
pub fn hex2(v : Int32) -> String {
  let s = StringBuilder()
  s.write_char(hex_digits[(v >> 4) & 0xF].unsafe_to_char())
  s.write_char(hex_digits[v & 0xF].unsafe_to_char())
  s.to_string()
}

///|
pub fn hex4(v : Int32) -> String {
  hex2((v >> 8) & 0xFF) + hex2(v & 0xFF)
}

///|
fn pad_right(s : String, width : Int32) -> String {
  if s.length() >= width {
    s
  } else {
    s + " ".repeat(width - s.length())
  }
}

///|
fn pad_left(s : String, width : Int32) -> String {
  if s.length() >= width {
    s
  } else {
    " ".repeat(width - s.length()) + s
  }
}

///|
/// Formats the operand of the instruction at `pc` the way nestest.log does,
/// including the effective address and current memory value annotations.
fn[B : CpuBus] Cpu::format_operand(
  self : Cpu[B],
  pc : Int32,
  info : OpcodeInfo,
) -> String {
  let bus = self.bus
  let b1 = bus.peek((pc + 1) & 0xFFFF)
  let b2 = bus.peek((pc + 2) & 0xFFFF)
  let word = b1 | (b2 << 8)
  let is_jump = info.mnemonic == "JMP" || info.mnemonic == "JSR"
  let value = fn(addr : Int32) { " = " + hex2(bus.peek(addr & 0xFFFF)) }
  match info.mode {
    Imp => ""
    Acc => "A"
    Imm => "#$" + hex2(b1)
    Zp => "$" + hex2(b1) + value(b1)
    Zpx => {
      let a = (b1 + self.x) & 0xFF
      "$" + hex2(b1) + ",X @ " + hex2(a) + value(a)
    }
    Zpy => {
      let a = (b1 + self.y) & 0xFF
      "$" + hex2(b1) + ",Y @ " + hex2(a) + value(a)
    }
    Abs =>
      if is_jump {
        "$" + hex4(word)
      } else {
        "$" + hex4(word) + value(word)
      }
    Abx => {
      let a = (word + self.x) & 0xFFFF
      "$" + hex4(word) + ",X @ " + hex4(a) + value(a)
    }
    Aby => {
      let a = (word + self.y) & 0xFFFF
      "$" + hex4(word) + ",Y @ " + hex4(a) + value(a)
    }
    Ind => {
      let lo = bus.peek(word)
      let hi = bus.peek((word & 0xFF00) | ((word + 1) & 0xFF))
      "($" + hex4(word) + ") = " + hex4(lo | (hi << 8))
    }
    Izx => {
      let p = (b1 + self.x) & 0xFF
      let a = bus.peek(p) | (bus.peek((p + 1) & 0xFF) << 8)
      "($" + hex2(b1) + ",X) @ " + hex2(p) + " = " + hex4(a) + value(a)
    }
    Izy => {
      let base = bus.peek(b1) | (bus.peek((b1 + 1) & 0xFF) << 8)
      let a = (base + self.y) & 0xFFFF
      "($" + hex2(b1) + "),Y = " + hex4(base) + " @ " + hex4(a) + value(a)
    }
    Rel => {
      let off = if b1 >= 0x80 { b1 - 0x100 } else { b1 }
      "$" + hex4((pc + 2 + off) & 0xFFFF)
    }
  }
}

///|
/// Disassembles the instruction at `pc` (mnemonic and operand only).
pub fn[B : CpuBus] Cpu::disassemble(self : Cpu[B], pc : Int32) -> String {
  let info = opcode_info(self.bus.peek(pc))
  let operand = self.format_operand(pc, info)
  let name = if info.official { info.mnemonic } else { "*" + info.mnemonic }
  if operand == "" {
    name
  } else {
    name + " " + operand
  }
}

///|
/// One line in the nestest.log format, describing the state *before* the
/// instruction at PC executes. `ppu` is (scanline, dot) when known.
pub fn[B : CpuBus] Cpu::trace_line(
  self : Cpu[B],
  ppu : (Int32, Int32),
) -> String {
  let pc = self.pc
  let info = opcode_info(self.bus.peek(pc))
  let bytes = StringBuilder()
  for i in 0..<info.mode.length() {
    bytes.write_string(hex2(self.bus.peek((pc + i) & 0xFFFF)))
    bytes.write_char(' ')
  }
  let marker = if info.official { " " } else { "*" }
  let operand = self.format_operand(pc, info)
  let (scanline, dot) = ppu
  hex4(pc) +
  "  " +
  pad_right(bytes.to_string(), 9) +
  marker +
  info.mnemonic +
  " " +
  pad_right(operand, 28) +
  "A:" +
  hex2(self.a) +
  " X:" +
  hex2(self.x) +
  " Y:" +
  hex2(self.y) +
  " P:" +
  hex2(self.p) +
  " SP:" +
  hex2(self.sp) +
  " PPU:" +
  pad_left(scanline.to_string(), 3) +
  "," +
  pad_left(dot.to_string(), 3) +
  " CYC:" +
  self.cycles.to_string()
}
