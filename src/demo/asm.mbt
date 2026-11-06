// A tiny 6502 assembler: enough to build the demo ROM from MoonBit code.
// Instructions are emitted as raw opcodes; labels are resolved on `link`.

///|
priv enum Fixup {
  /// 8-bit signed branch offset at this position.
  Relative(Int32, String)
  /// 16-bit little-endian address at this position.
  Absolute(Int32, String)
}

///|
pub struct Asm {
  priv origin : Int32
  priv code : Array[Int32]
  priv labels : Map[String, Int32]
  priv fixups : Array[Fixup]
}

///|
pub suberror AsmError {
  UndefinedLabel(String)
  BranchOutOfRange(String)
}

///|
pub fn AsmError::message(self : AsmError) -> String {
  match self {
    UndefinedLabel(name) => "undefined label \{name}"
    BranchOutOfRange(name) => "branch to \{name} is out of range"
  }
}

///|
pub fn Asm::new(origin : Int32) -> Asm {
  { origin, code: [], labels: {}, fixups: [], }
}

///|
/// Address of the next emitted byte.
pub fn Asm::pc(self : Asm) -> Int32 {
  self.origin + self.code.length()
}

///|
pub fn Asm::label(self : Asm, name : String) -> Unit {
  self.labels[name] = self.pc()
}

///|
pub fn Asm::bytes(self : Asm, data : ArrayView[Int32]) -> Unit {
  for b in data {
    self.code.push(b & 0xFF)
  }
}

///|
/// An instruction without operand (implied or accumulator mode).
pub fn Asm::op(self : Asm, opcode : Int32) -> Unit {
  self.code.push(opcode)
}

///|
/// An instruction with a one-byte operand (immediate or zero page).
pub fn Asm::op8(self : Asm, opcode : Int32, operand : Int32) -> Unit {
  self.bytes([opcode, operand])
}

///|
/// An instruction with a two-byte operand (absolute modes).
pub fn Asm::op16(self : Asm, opcode : Int32, addr : Int32) -> Unit {
  self.bytes([opcode, addr & 0xFF, (addr >> 8) & 0xFF])
}

///|
/// An absolute-mode instruction whose address is a label.
pub fn Asm::op_label(self : Asm, opcode : Int32, target : String) -> Unit {
  self.code.push(opcode)
  self.fixups.push(Absolute(self.code.length(), target))
  self.bytes([0, 0])
}

///|
/// A conditional branch to a label.
pub fn Asm::branch(self : Asm, opcode : Int32, target : String) -> Unit {
  self.code.push(opcode)
  self.fixups.push(Relative(self.code.length(), target))
  self.code.push(0)
}

///|
fn Asm::resolve(self : Asm, name : String) -> Int32 raise AsmError {
  match self.labels.get(name) {
    Some(addr) => addr
    None => raise UndefinedLabel(name)
  }
}

///|
/// Resolves all labels and returns the machine code.
pub fn Asm::link(self : Asm) -> Array[Int32] raise AsmError {
  for fixup in self.fixups {
    match fixup {
      Relative(at, name) => {
        let offset = self.resolve(name) - (self.origin + at + 1)
        if offset < -128 || offset > 127 {
          raise BranchOutOfRange(name)
        }
        self.code[at] = offset & 0xFF
      }
      Absolute(at, name) => {
        let addr = self.resolve(name)
        self.code[at] = addr & 0xFF
        self.code[at + 1] = (addr >> 8) & 0xFF
      }
    }
  }
  self.code
}

///|
/// Address of a label defined so far.
pub fn Asm::address_of(self : Asm, name : String) -> Int32 raise AsmError {
  self.resolve(name)
}
