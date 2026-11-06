///|
test "nestest.log matches on the full console, PPU column included" {
  let dir = "test-roms/downloaded/other/"
  if !@fs.path_exists(dir + "nestest.nes") {
    println("skip: nestest.nes missing, run scripts/fetch-test-roms.sh")
    return
  }
  let report = @nes.run_nestest(
    @fs.read_file_to_bytes(dir + "nestest.nes"),
    @fs.read_file_to_string(dir + "nestest.log"),
  )
  if report.first_mismatch is Some((line, expected, actual)) {
    fail("line \{line}\n  expected: \{expected}\n  actual:   \{actual}")
  }
  assert_eq(report.matched, 8991)
  assert_eq(report.error_official, 0)
  assert_eq(report.error_unofficial, 0)
}
