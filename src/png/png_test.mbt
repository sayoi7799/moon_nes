///|
test "crc32 and adler32 match their reference values" {
  // The standard check value of CRC-32 and the RFC 1950 example.
  assert_eq(@png.crc32(b"123456789"), 0xCBF43926U)
  assert_eq(@png.adler32(b"Wikipedia"), 0x11E60398U)
}

///|
test "PNG signature, IHDR and IEND" {
  let png = @png.encode_rgb(2, 1, [0xFF0000, 0x00FF00])
  assert_eq(png[0:8].to_owned(), b"\x89PNG\r\n\x1a\n")
  // IHDR: length 13, "IHDR", width 2, height 1, depth 8, color type 2.
  assert_eq(
    png[8:29].to_owned(),
    b"\x00\x00\x00\x0dIHDR\x00\x00\x00\x02\x00\x00\x00\x01\x08\x02\x00\x00\x00",
  )
  // The file ends with an empty IEND chunk and its CRC.
  assert_eq(
    png[png.length() - 12:].to_owned(),
    b"\x00\x00\x00\x00IEND\xae\x42\x60\x82",
  )
}

///|
test "image data uses previous-pixel and row-above matches" {
  // Two identical rows of red, red, red, blue. Python's zlib.decompress
  // turns these 17 bytes back into the 26 bytes of filtered rows.
  let png = @png.encode_rgb(4, 2, [
    0xFF0000, 0xFF0000, 0xFF0000, 0x0000FF, 0xFF0000, 0xFF0000, 0xFF0000, 0x0000FF,
  ])
  assert_eq(png[33:41].to_owned(), b"\x00\x00\x00\x11IDAT")
  assert_eq(
    png[41:58].to_owned(),
    b"\x78\x01\x63\xf8\xcf\x00\x45\x0c\x0c\xff\x51\x38\x00\x6b\xae\x07\xf9",
  )
}

///|
test "a solid-color frame compresses to a small file" {
  let w = 256
  let h = 240
  let png = @png.encode_rgb(w, h, FixedArray::make(w * h, 0x123456))
  // Uncompressed, the rows alone would be (256 * 3 + 1) * 240 = 184560 bytes.
  assert_true(png.length() < 2000)
}
