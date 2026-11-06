///|
/// Parses a decimal number, or returns None.
fn parse_count(s : String) -> Int32? {
  if s.is_empty() {
    return None
  }
  let mut n = 0
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
/// Runs a ROM for a number of frames and prints the first nametable as
/// text. Usage: moon run src/cmd/screen -- rom.nes [frames]
fn main {
  let args = @env.args()
  let last = args[args.length() - 1]
  let (path, frames) = match parse_count(last) {
    Some(n) => (args[args.length() - 2], n)
    None => (last, 300)
  }
  let nes = @nes.Nes::load_rom(@fs.read_file_to_bytes(path)) catch {
    e => abort("cannot load \{path}: \{e}")
  }
  for _ in 0..<frames {
    nes.run_frame()
  }
  println(nes.screen_text())
  println("frame hash: \{nes.frame_hash()}")
}
