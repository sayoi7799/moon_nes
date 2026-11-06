// Picture regression tests: run a ROM for a fixed number of frames and pin
// the FNV-1a hash of the framebuffer. If rendering changes on purpose,
// refresh the snapshots with `moon test --update` and check the pictures.

///|
fn hash_after(path : String, frames : Int32) -> String raise {
  guard load(path) is Some(nes) else { return "skipped" }
  for _ in 0..<frames {
    nes.run_frame()
  }
  nes.frame_hash().to_string()
}

///|
test "frame hash: Holy Mapperel NROM" {
  inspect(
    hash_after("holy-mapperel/M0_P32K_C8K_V.nes", 600),
    content="1376399685",
  )
}

///|
test "frame hash: Holy Mapperel MMC1 SUROM" {
  inspect(
    hash_after("holy-mapperel/M1_P512K_CR8K_S8K.nes", 600),
    content="2108481759",
  )
}

///|
test "frame hash: Holy Mapperel UxROM" {
  inspect(hash_after("holy-mapperel/M2_P128K_V.nes", 600), content="67181957")
}

///|
test "frame hash: Holy Mapperel CNROM" {
  inspect(
    hash_after("holy-mapperel/M3_P32K_C32K_H.nes", 600),
    content="3931891999",
  )
}

///|
test "frame hash: sprite 0 hit screen" {
  let h = hash_after(
    "downloaded/sprite_hit_tests_2005.10.05/02.alignment.nes", 120,
  )
  if h != "skipped" {
    inspect(h, content="2897043949")
  }
}

///|
test "frame hash: instr_test text console" {
  let h = hash_after("downloaded/instr_test-v5/rom_singles/01-basics.nes", 120)
  if h != "skipped" {
    inspect(h, content="4095487394")
  }
}
