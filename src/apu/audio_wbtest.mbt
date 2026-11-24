///|
test "one second of cycles gives one second of samples" {
  let r = Resampler::new(48000.0)
  for _ in 0..<CPU_CLOCK.to_int() {
    r.add(0.0)
  }
  assert_true((r.available - 48000).abs() <= 1)
}

///|
test "the high-pass filter removes a constant level" {
  let r = Resampler::new(48000.0)
  for _ in 0..<(CPU_CLOCK.to_int() / 2) {
    r.add(0.5)
  }
  let out = FixedArray::make(48000, 0.0)
  let n = r.take(out)
  // The step response starts near the input and decays towards 0.
  assert_true(out[10] > 0.4)
  assert_true(out[n - 1].abs() < 0.001)
}

///|
test "take returns samples oldest first and empties the buffer" {
  let r = Resampler::new(1000.0)
  r.lp_alpha = 1.0
  r.hp_alpha = 1.0
  for i in 0..<5 {
    r.emit(i.to_double())
  }
  let out = FixedArray::make(3, 0.0)
  assert_eq(r.take(out), 3)
  assert_eq(out[2], 2.0)
  assert_eq(r.take(out), 2)
  assert_eq(out[1], 4.0)
  assert_eq(r.take(out), 0)
}

///|
test "an unread buffer keeps the latest second" {
  let r = Resampler::new(1000.0)
  for i in 0..<2500 {
    r.emit(i.to_double())
  }
  assert_eq(r.available, r.buffer.length())
}

///|
test "rate 0 turns sampling off" {
  let apu = Apu::new()
  apu.set_sample_rate(0.0)
  for _ in 0..<100000 {
    apu.step()
  }
  assert_eq(apu.samples_available(), 0)
}
