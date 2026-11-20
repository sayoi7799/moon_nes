///|
test "envelope starts at 15 and decays once per period+1 quarter frames" {
  let env = Envelope::new()
  env.write(0x02)
  env.start = true
  env.clock()
  assert_eq(env.output(), 15)
  env.clock()
  env.clock()
  assert_eq(env.output(), 15)
  env.clock()
  assert_eq(env.output(), 14)
  // Constant volume outputs the period bits directly.
  env.write(0x17)
  assert_eq(env.output(), 7)
}

///|
test "envelope loops back to 15 only with the loop flag" {
  let env = Envelope::new()
  env.write(0x00)
  env.start = true
  for _ in 0..<16 {
    env.clock()
  }
  assert_eq(env.output(), 0)
  env.clock()
  assert_eq(env.output(), 0)
  env.write(0x20)
  env.clock()
  assert_eq(env.output(), 15)
}

///|
test "sweep negation differs between pulse 1 and pulse 2" {
  let p1 = Pulse::new(true)
  let p2 = Pulse::new(false)
  for p in [p1, p2] {
    p.write(2, 0x00)
    p.write(3, 0x01) // period $100
    p.write(1, 0x89) // enabled, period 0, negate, shift 1
  }
  assert_eq(p1.sweep_target(), 0x7F)
  assert_eq(p2.sweep_target(), 0x80)
  p1.clock_sweep()
  assert_eq(p1.period, 0x7F)
}

///|
test "sweep overflow and short periods mute the pulse" {
  let p = Pulse::new(false)
  p.write(0, 0x3F) // 75% duty bits ignored here, constant volume 15
  p.write(2, 0x00)
  p.write(3, 0x06) // period $600
  p.write(1, 0x01) // sweep disabled, shift 1 -> target $900
  assert_true(p.muted())
  p.write(1, 0x08) // negate: target below period
  assert_false(p.muted())
  p.write(2, 0x07)
  p.write(3, 0x00) // period 7
  assert_true(p.muted())
}

///|
test "pulse duty cycles are 1/8, 2/8, 4/8 and 6/8 high" {
  for duty in 0..<4 {
    let p = Pulse::new(true)
    p.write(0, (duty << 6) | 0x1F)
    p.write(2, 0x10)
    p.write(3, 0x00)
    let mut high = 0
    for _ in 0..<8 {
      if p.output(1) > 0 {
        high += 1
      }
      for _ in 0..<=0x10 {
        p.clock_timer()
      }
    }
    assert_eq(high, [1, 2, 4, 6][duty])
  }
}

///|
test "triangle walks 15..0 then 0..15 while both counters are non-zero" {
  let t = Triangle::new()
  t.write(0, 0x7F)
  t.write(2, 0x02)
  t.write(3, 0x00)
  t.clock_linear()
  let levels = []
  for _ in 0..<32 {
    levels.push(t.output())
    for _ in 0..<3 {
      t.clock_timer(1)
    }
  }
  assert_eq(levels[0], 15)
  assert_eq(levels[15], 0)
  assert_eq(levels[16], 0)
  assert_eq(levels[31], 15)
  // Length 0 holds the level instead of dropping to 0.
  let held = t.output()
  for _ in 0..<30 {
    t.clock_timer(0)
  }
  assert_eq(t.output(), held)
}

///|
test "noise LFSR has period 32767, or 93 in short mode from power-on" {
  let n = Noise::new()
  n.write(2, 0x00) // period 4 CPU cycles
  let start = n.shift
  let mut steps = 0
  while true {
    for _ in 0..<4 {
      n.clock_timer()
    }
    steps += 1
    if n.shift == start {
      break
    }
  }
  assert_eq(steps, 32767)
  n.write(2, 0x80)
  steps = 0
  while true {
    for _ in 0..<4 {
      n.clock_timer()
    }
    steps += 1
    if n.shift == start {
      break
    }
  }
  assert_eq(steps, 93)
}

///|
test "quarter frames clock envelopes at cycle 7457" {
  let apu = Apu::new()
  apu.write(0x4015, 0x01)
  apu.write(0x4000, 0x80) // duty 50%, envelope period 0
  apu.write(0x4002, 0x00)
  apu.write(0x4003, 0x09) // period $100, length loaded
  for _ in 0..<7456 {
    apu.step()
  }
  assert_eq(apu.pulse1.envelope.output(), 0)
  apu.step()
  assert_eq(apu.pulse1.envelope.output(), 15)
  for _ in 0..<(14913 - 7457) {
    apu.step()
  }
  assert_eq(apu.pulse1.envelope.output(), 14)
}

///|
test "mixer is silent at rest and follows the table at full volume" {
  assert_eq(pulse_table[0], 0.0)
  assert_true((pulse_table[30] - 0.2575).abs() < 0.001)
  assert_true((tnd_table[202] - 0.7425).abs() < 0.001)
  let apu = Apu::new()
  // The triangle starts at step 0, level 15, even when silent.
  assert_eq(apu.output(), tnd_table[45])
}
