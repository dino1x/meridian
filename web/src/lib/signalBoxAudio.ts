// Mechanical Solari Split-Flap & Interlocking Signal Lever Web Audio

class SignalBoxAudio {
  private ctx: AudioContext | null = null;
  public enabled = true;

  private ensure(): AudioContext | null {
    if (!this.enabled || typeof window === 'undefined') return null;
    if (!this.ctx) {
      const Ctx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      if (Ctx) this.ctx = new Ctx();
    }
    if (this.ctx && this.ctx.state === 'suspended') {
      this.ctx.resume().catch(() => {});
    }
    return this.ctx;
  }

  public splitFlapClatter(): void {
    const ctx = this.ensure();
    if (!ctx) return;
    const now = ctx.currentTime;
    for (let i = 0; i < 4; i++) {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'square';
      osc.frequency.setValueAtTime(320 + i * 90, now + i * 0.028);
      osc.frequency.exponentialRampToValueAtTime(110, now + i * 0.028 + 0.02);
      gain.gain.setValueAtTime(0.06, now + i * 0.028);
      gain.gain.exponentialRampToValueAtTime(0.001, now + i * 0.028 + 0.022);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(now + i * 0.028);
      osc.stop(now + i * 0.028 + 0.025);
    }
  }

  public throwInterlockLever(isSlash: boolean): void {
    const ctx = this.ensure();
    if (!ctx) return;
    const now = ctx.currentTime;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = isSlash ? 'sawtooth' : 'triangle';
    osc.frequency.setValueAtTime(isSlash ? 180 : 260, now);
    osc.frequency.exponentialRampToValueAtTime(isSlash ? 440 : 520, now + 0.14);
    gain.gain.setValueAtTime(0.16, now);
    gain.gain.exponentialRampToValueAtTime(0.001, now + 0.16);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(now);
    osc.stop(now + 0.17);
  }
}

export const signalAudio = new SignalBoxAudio();
