///|
/// Parses a positive decimal number, or returns None.
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
/// Runs a ROM for some frames and saves the picture as a PNG, scaled up by
/// an integer factor. `demo` uses the built-in demo ROM.
/// Usage: moon run src/cmd/snapshot -- (rom.nes | demo) frames out.png [scale]
/// The README screenshot is: moon run src/cmd/snapshot -- demo 120 docs/screenshot.png 2
fn main {
  let args = @env.args()
  let n = args.length()
  let (source, frames, out, scale) = if n >= 5 &&
    parse_count(args[n - 1]) is Some(s) &&
    parse_count(args[n - 3]) is Some(f) {
    (args[n - 4], f, args[n - 2], s)
  } else if n >= 4 && parse_count(args[n - 2]) is Some(f) {
    (args[n - 3], f, args[n - 1], 1)
  } else {
    abort("usage: snapshot (rom.nes | demo) frames out.png [scale]")
  }
  let rom = if source == "demo" {
    @demo.demo_rom()
  } else {
    @fs.read_file_to_bytes(source) catch {
      _ => abort("cannot read \{source}")
    }
  }
  let nes = @nes.Nes::load_rom(rom) catch {
    e => abort("cannot load \{source}: \{e.message()}")
  }
  nes.set_sample_rate(0.0)
  for _ in 0..<frames {
    nes.run_frame()
  }
  let frame = nes.frame_buffer()
  let w = @nes.SCREEN_WIDTH * scale
  let h = @nes.SCREEN_HEIGHT * scale
  let pixels = FixedArray::makei(w * h, i => {
    let x = i % w / scale
    let y = i / w / scale
    @nes.pixel_rgb(frame[y * @nes.SCREEN_WIDTH + x])
  })
  @fs.write_bytes_to_file(out, @png.encode_rgb(w, h, pixels)) catch {
    _ => abort("cannot write \{out}")
  }
  println("wrote \{out} (\{w}x\{h}, frame \{frames})")
}
