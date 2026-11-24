// A minimal PNG encoder for screenshots: 8-bit RGB, no filtering, and the
// image data in one deflate block with the fixed Huffman code, using only
// "same as the previous pixel" and "same as the row above" matches. That
// is far simpler than a general compressor and still shrinks NES frames,
// which are mostly runs of a few colors, to a small fraction.
// Reference: RFC 2083 (PNG), RFC 1950 (zlib), RFC 1951 (deflate)

///|
let crc_table : FixedArray[UInt32] = FixedArray::makei(256, n => {
  let mut c = n.reinterpret_as_uint()
  for _ in 0..<8 {
    c = if (c & 1) != 0 { 0xEDB88320U ^ (c >> 1) } else { c >> 1 }
  }
  c
})

///|
/// CRC-32 as used by PNG chunks (and zip, gzip).
pub fn crc32(data : BytesView) -> UInt32 {
  let mut c = 0xFFFFFFFFU
  for b in data {
    c = crc_table[((c ^ b.to_uint()) & 0xFF).reinterpret_as_int()] ^ (c >> 8)
  }
  c ^ 0xFFFFFFFFU
}

///|
/// Adler-32, the checksum at the end of a zlib stream.
pub fn adler32(data : BytesView) -> UInt32 {
  let mut a = 1U
  let mut b = 0U
  for x in data {
    a = (a + x.to_uint()) % 65521U
    b = (b + a) % 65521U
  }
  (b << 16) | a
}

///|
fn write_u32(buf : Buffer, v : UInt32) -> Unit {
  buf.write_byte((v >> 24).to_byte())
  buf.write_byte((v >> 16).to_byte())
  buf.write_byte((v >> 8).to_byte())
  buf.write_byte(v.to_byte())
}

///|
fn write_chunk(buf : Buffer, kind : String, data : Bytes) -> Unit {
  write_u32(buf, data.length().reinterpret_as_uint())
  let body = Buffer(capacity=data.length() + 4)
  for c in kind {
    body.write_byte(c.to_int().to_byte())
  }
  body.write_bytes(data)
  let typed = body.to_bytes()
  buf.write_bytes(typed)
  write_u32(buf, crc32(typed))
}

///|
/// Writes bits into bytes least significant bit first, as deflate does.
priv struct BitWriter {
  out : Buffer
  mut acc : Int32
  mut count : Int32
}

///|
fn BitWriter::bits(self : BitWriter, value : Int32, n : Int32) -> Unit {
  self.acc = self.acc | (value << self.count)
  self.count += n
  while self.count >= 8 {
    self.out.write_byte(self.acc.to_byte())
    self.acc = self.acc >> 8
    self.count -= 8
  }
}

///|
/// Huffman codes are sent most significant bit first.
fn BitWriter::code(self : BitWriter, code : Int32, n : Int32) -> Unit {
  let mut reversed = 0
  for i in 0..<n {
    reversed = (reversed << 1) | ((code >> i) & 1)
  }
  self.bits(reversed, n)
}

///|
fn BitWriter::flush(self : BitWriter) -> Unit {
  if self.count > 0 {
    self.out.write_byte(self.acc.to_byte())
    self.acc = 0
    self.count = 0
  }
}

///|
/// Literal/length symbol in the fixed Huffman code (RFC 1951 3.2.6).
fn BitWriter::symbol(self : BitWriter, sym : Int32) -> Unit {
  if sym < 144 {
    self.code(0x30 + sym, 8)
  } else if sym < 256 {
    self.code(0x190 + sym - 144, 9)
  } else if sym < 280 {
    self.code(sym - 256, 7)
  } else {
    self.code(0xC0 + sym - 280, 8)
  }
}

///|
let length_base : FixedArray[Int32] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83,
  99, 115, 131, 163, 195, 227, 258,
]

///|
let length_extra : FixedArray[Int32] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5,
  5, 0,
]

///|
let dist_base : FixedArray[Int32] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
  1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
]

///|
let dist_extra : FixedArray[Int32] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
  12, 12, 13, 13,
]

///|
fn BitWriter::length_distance(
  self : BitWriter,
  length : Int32,
  distance : Int32,
) -> Unit {
  let mut i = length_base.length() - 1
  while length_base[i] > length {
    i -= 1
  }
  self.symbol(257 + i)
  self.bits(length - length_base[i], length_extra[i])
  let mut d = dist_base.length() - 1
  while dist_base[d] > distance {
    d -= 1
  }
  self.code(d, 5)
  self.bits(distance - dist_base[d], dist_extra[d])
}

///|
/// A zlib stream of `data` in one fixed-Huffman deflate block. Matches are
/// only looked for at the given distances: for image rows that is the
/// previous pixel and the row above, which is where screenshots repeat.
fn zlib_fixed(data : Bytes, distances : Array[Int32]) -> Bytes {
  let out = Buffer(capacity=data.length() / 4 + 64)
  // CMF/FLG: deflate with a 32 KiB window, no dictionary, check bits.
  out.write_byte(b'\x78')
  out.write_byte(b'\x01')
  let w = { out, acc: 0, count: 0, }
  w.bits(1, 1) // final block
  w.bits(1, 2) // fixed Huffman codes
  let n = data.length()
  let mut i = 0
  while i < n {
    let mut best_len = 0
    let mut best_dist = 0
    for d in distances {
      if d > i || d > 32768 {
        continue
      }
      let mut len = 0
      while len < 258 && i + len < n && data[i + len] == data[i + len - d] {
        len += 1
      }
      if len > best_len {
        best_len = len
        best_dist = d
      }
    }
    if best_len >= 3 {
      w.length_distance(best_len, best_dist)
      i += best_len
    } else {
      w.symbol(data[i].to_int())
      i += 1
    }
  }
  w.symbol(256) // end of block
  w.flush()
  write_u32(out, adler32(data))
  out.to_bytes()
}

///|
/// Encodes a `width` x `height` image given as 0xRRGGBB pixels, row by row.
pub fn encode_rgb(
  width : Int32,
  height : Int32,
  pixels : FixedArray[Int32],
) -> Bytes {
  let raw = Buffer(capacity=(width * 3 + 1) * height)
  for y in 0..<height {
    raw.write_byte(b'\x00') // filter type: none
    for x in 0..<width {
      let p = pixels[y * width + x]
      raw.write_byte((p >> 16).to_byte())
      raw.write_byte((p >> 8).to_byte())
      raw.write_byte(p.to_byte())
    }
  }
  let ihdr = Buffer(capacity=13)
  write_u32(ihdr, width.reinterpret_as_uint())
  write_u32(ihdr, height.reinterpret_as_uint())
  // Bit depth 8, color type 2 (RGB), deflate, no filter, no interlace.
  for b in [8, 2, 0, 0, 0] {
    ihdr.write_byte(b.to_byte())
  }
  let out = Buffer()
  out.write_bytes(b"\x89PNG\r\n\x1a\n")
  write_chunk(out, "IHDR", ihdr.to_bytes())
  write_chunk(out, "IDAT", zlib_fixed(raw.to_bytes(), [3, width * 3 + 1]))
  write_chunk(out, "IEND", b"")
  out.to_bytes()
}
