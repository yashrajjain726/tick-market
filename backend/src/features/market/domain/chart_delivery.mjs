/** Latest complete value per bucket, including a just-closed candle at rollover. */
export class ChartDelivery {
  constructor() { this.pending = new Map(); this.nextDue = 0; this.lastPeriod = 0; }
  collect(candle) { this.pending.set(candle.start, { ...candle }); }
  flush(now, period) {
    if (period < this.lastPeriod) this.nextDue = Math.min(this.nextDue, now);
    this.lastPeriod = period;
    if (now < this.nextDue || this.pending.size === 0) return null;
    const values = [...this.pending.values()].sort((a, b) => a.start - b.start);
    this.pending.clear();
    this.nextDue += (Math.floor((now - this.nextDue) / period) + 1) * period;
    return values;
  }
}
