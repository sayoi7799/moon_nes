///|
fn main {
  // Any iNES file works here, for example bytes read from disk with
  // moonbitlang/x/fs. The demo ROM is built into the library.
  let rom = @demo.demo_rom()
  let nes = @nes.Nes::load_rom(rom) catch {
    err => {
      println("cannot load ROM: \{err.message()}")
      return
    }
  }
  // Player 1 holds Start during the next frame.
  nes.set_buttons(0, @nes.BUTTON_START)
  nes.run_frame()
  // 256x240 pixels, each an NES color index; pixel_rgb turns it into 0xRRGGBB.
  let frame = nes.frame_buffer()
  let rgb = @nes.pixel_rgb(frame[0])
  println("\{frame.length()} pixels, first pixel RGB \{rgb}")
}
