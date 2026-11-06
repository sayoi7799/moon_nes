///|
/// Measures emulation speed: runs a ROM headless for 600 frames.
/// Usage: moon run src/cmd/bench [--target js|wasm-gc|native] -- rom.nes
fn main {
  let args = @env.args()
  let path = args[args.length() - 1]
  let nes = @nes.Nes::load_rom(@fs.read_file_to_bytes(path)) catch {
    e => abort("cannot load \{path}: \{e}")
  }
  // Warm up (JIT, caches) before timing.
  for _ in 0..<60 {
    nes.run_frame()
  }
  let frames = 600
  let start = @env.now()
  for _ in 0..<frames {
    nes.run_frame()
  }
  let ms = (@env.now() - start).to_int()
  let fps = frames * 1000 / (if ms == 0 { 1 } else { ms })
  println("\{frames} frames in \{ms} ms = \{fps} fps")
}
