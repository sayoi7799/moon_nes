// Browser front end. The emulator runs entirely in MoonBit; this package
// only adapts it to the page through a handful of JS FFI functions.
// The page glue (web/index.html) owns the canvas, the 60 Hz loop and the
// file picker, and calls into the functions registered on `moonNes`.

///|
let console : Ref[@nes.Nes?] = { val: None, }

///|
let held_buttons : Ref[Int32] = { val: 0, }

///|
/// Keyboard layout: arrows = D-pad, X = A, Z = B, Enter = Start,
/// Shift = Select. Returns 0 for keys that are not mapped.
fn button_for_key(code : String) -> Int32 {
  match code {
    "ArrowUp" => @nes.BUTTON_UP
    "ArrowDown" => @nes.BUTTON_DOWN
    "ArrowLeft" => @nes.BUTTON_LEFT
    "ArrowRight" => @nes.BUTTON_RIGHT
    "KeyX" | "KeyK" => @nes.BUTTON_A
    "KeyZ" | "KeyJ" => @nes.BUTTON_B
    "Enter" => @nes.BUTTON_START
    "ShiftLeft" | "ShiftRight" => @nes.BUTTON_SELECT
    _ => 0
  }
}

///|
/// Loads a ROM image. Returns "" on success or a readable error message.
fn load(data : Bytes) -> String {
  try {
    let nes = @nes.Nes::load_rom(data)
    nes.set_buttons(0, held_buttons.val)
    console.val = Some(nes)
    ""
  } catch {
    e => e.message()
  }
}

///|
/// A short description of the loaded cartridge for the status line.
fn describe() -> String {
  guard console.val is Some(nes) else { return "no ROM loaded" }
  let c = nes.cartridge
  let chr = if c.chr_is_ram { "CHR RAM" } else { "CHR ROM" }
  let format = if c.is_nes2 { "NES 2.0" } else { "iNES" }
  "\{format}, mapper \{c.mapper_id}, PRG \{c.prg_rom.length() / 1024} KiB, " +
  "\{chr} \{c.chr.length() / 1024} KiB, \{c.mirroring.to_string()} mirroring"
}

///|
/// Runs one frame and writes it as RGBA into `out` (the canvas ImageData).
fn frame(out : FixedArray[Byte]) -> Unit {
  guard console.val is Some(nes) else { return }
  nes.run_frame()
  nes.write_rgba(out)
}

///|
/// Key press or release. Returns true if the key is mapped to a button.
fn key(code : String, down : Bool) -> Bool {
  let b = button_for_key(code)
  if b == 0 {
    return false
  }
  held_buttons.val = if down {
    held_buttons.val | b
  } else {
    held_buttons.val & b.lnot()
  }
  if console.val is Some(nes) {
    nes.set_buttons(0, held_buttons.val)
  }
  true
}

///|
fn reset() -> Unit {
  if console.val is Some(nes) {
    nes.reset()
  }
}

///|
extern "js" fn register(
  load : (Bytes) -> String,
  demo : () -> String,
  describe : () -> String,
  frame : (FixedArray[Byte]) -> Unit,
  key : (String, Bool) -> Bool,
  reset : () -> Unit,
) -> Unit =
  #|(load, demo, describe, frame, key, reset) => {
  #|  globalThis.moonNes = { load, demo, describe, frame, key, reset };
  #|  globalThis.dispatchEvent(new Event("moon-nes-ready"));
  #|}

///|
fn main {
  register(load, () => load(@demo.demo_rom()), describe, frame, key, reset)
}
