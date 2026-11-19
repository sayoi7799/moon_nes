///|
/// The README shows main.mbt as the minimal usage example. Keeping the two
/// identical means the README code is always code that compiles.
test "README usage example matches main.mbt" {
  let readme = @fs.read_file_to_string("README.md")
  let main = @fs.read_file_to_string("src/examples/basic/main.mbt")
  let block = "```moonbit\n" + main + "```\n"
  if readme.find(block) is None {
    fail("README.md must contain src/examples/basic/main.mbt verbatim")
  }
}

///|
test "the example's API calls give a full frame" {
  let nes = @nes.Nes::load_rom(@demo.demo_rom())
  nes.set_buttons(0, @nes.BUTTON_START)
  nes.run_frame()
  assert_eq(nes.frame_buffer().length(), @nes.SCREEN_WIDTH * @nes.SCREEN_HEIGHT)
}
