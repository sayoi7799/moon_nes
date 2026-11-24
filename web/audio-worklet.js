// Plays the samples the emulator posts every frame. The page keeps this
// buffer near a target fill level by nudging the emulator's sample rate,
// so the worklet only has to buffer and report how full it is.
class MoonNesAudio extends AudioWorkletProcessor {
  constructor() {
    super();
    // About 0.34 s at 48 kHz; far more than the page ever keeps queued.
    this.buffer = new Float32Array(16384);
    this.read = 0;
    this.write = 0;
    this.count = 0;
    this.last = 0;
    this.blocks = 0;
    this.port.onmessage = (e) => this.push(e.data);
  }

  push(samples) {
    for (let i = 0; i < samples.length; i++) {
      if (this.count === this.buffer.length) {
        // Full: drop the oldest sample.
        this.read = (this.read + 1) % this.buffer.length;
        this.count--;
      }
      this.buffer[this.write] = samples[i];
      this.write = (this.write + 1) % this.buffer.length;
      this.count++;
    }
  }

  process(inputs, outputs) {
    const out = outputs[0][0];
    for (let i = 0; i < out.length; i++) {
      if (this.count > 0) {
        this.last = this.buffer[this.read];
        this.read = (this.read + 1) % this.buffer.length;
        this.count--;
      }
      // On underrun, hold the last level instead of jumping to 0 (a click).
      out[i] = this.last;
    }
    // Report the fill level about every 21 ms (8 blocks of 128 frames).
    if (++this.blocks % 8 === 0) this.port.postMessage(this.count);
    return true;
  }
}

registerProcessor("moon-nes-audio", MoonNesAudio);
