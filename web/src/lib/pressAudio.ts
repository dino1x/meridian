// Procedural Letterpress & Rubber-Stamp Web Audio Synthesizer for Roost Almanac

class AlmanacPressAudio {
  private ctx: AudioContext | null = null;
  public enabled = true;

  private ensureContext(): AudioContext | null {
    if (!this.enabled || typeof window === 'undefined') return null;
    if (!this.ctx) {
      const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      if (AudioCtx) this.ctx = new AudioCtx();
    }
    if (this.ctx && this.ctx.state === 'suspended') {
      this.ctx.resume().catch(() => {});
    }
    return this.ctx;
  }

  // Mechanical platen press type-slug clack
  public typeClack(): void {
    const ctx = this.ensureContext();
    if (!ctx) return;
    const now = ctx.currentTime;

    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'triangle';
    osc.frequency.setValueAtTime(210, now);
    osc.frequency.exponentialRampToValueAtTime(65, now + 0.045);

    gain.gain.setValueAtTime(0.14, now);
    gain.gain.exponentialRampToValueAtTime(0.001, now + 0.05);

    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(now);
    osc.stop(now + 0.055);
  }

  // Heavy rubber-stamp platen thud for CHICKEN IN / CHICKEN OUT
  public rubberStamp(isChickenIn: boolean): void {
    const ctx = this.ensureContext();
    if (!ctx) return;
    const now = ctx.currentTime;

    // Low platen thud
    const sub = ctx.createOscillator();
    const subGain = ctx.createGain();
    sub.type = 'sine';
    sub.frequency.setValueAtTime(isChickenIn ? 135 : 98, now);
    sub.frequency.exponentialRampToValueAtTime(34, now + 0.16);
    subGain.gain.setValueAtTime(0.28, now);
    subGain.gain.exponentialRampToValueAtTime(0.001, now + 0.17);
    sub.connect(subGain);
    subGain.connect(ctx.destination);
    sub.start(now);
    sub.stop(now + 0.18);

    // Brass bell overtone on Chicken In
    if (isChickenIn) {
      const bell = ctx.createOscillator();
      const bellGain = ctx.createGain();
      bell.type = 'sine';
      bell.frequency.setValueAtTime(660, now + 0.03);
      bell.frequency.exponentialRampToValueAtTime(880, now + 0.24);
      bellGain.gain.setValueAtTime(0.09, now + 0.03);
      bellGain.gain.exponentialRampToValueAtTime(0.001, now + 0.28);
      bell.connect(bellGain);
      bellGain.connect(ctx.destination);
      bell.start(now + 0.03);
      bell.stop(now + 0.29);
    }
  }
}

export const pressAudio = new AlmanacPressAudio();
