import { DEFAULT_DELIVERY } from './delivery_config.mjs';
export const PERIOD = DEFAULT_DELIVERY.periods;
const rank = ['full', 'degraded', 'minimal'];

/** One policy per connection; all times are monotonic milliseconds. */
export class DeliveryPolicy {
  constructor(now = 0, config = DEFAULT_DELIVERY) {
    this.config = config;
    this.automatic = 'full';
    this.override = null;
    this.lastReport = now;
    this.lastChange = now - config.dwellMs;
    this.count = 0;
    this.candidate = null;
    this.reason = 'Measuring connection';
  }
  get tier() { return this.override ?? this.automatic; }
  get period() { return this.config.periods[this.tier]; }
  force(value) {
    if (value !== null && !Object.hasOwn(PERIOD, value)) throw new Error('Unknown tier');
    this.override = value;
  }
  report(rtt, jitter, now) {
    if (![rtt, jitter].every(n => Number.isFinite(n) && n >= 0 && n <= this.config.maxMetricMs)) return;
    this.lastReport = now;
    const severe = rtt > this.config.minimalRtt || jitter > this.config.minimalJitter;
    const poor = rtt > this.config.degradedRtt || jitter > this.config.degradedJitter;
    const healthy = rtt < this.config.fullRecoveryRtt && jitter < this.config.fullRecoveryJitter;
    const recovering = rtt < this.config.degradedRecoveryRtt && jitter < this.config.degradedRecoveryJitter;
    const target = this.automatic === 'full' ? (severe ? 'minimal' : poor ? 'degraded' : 'full')
      : this.automatic === 'degraded' ? (severe ? 'minimal' : healthy ? 'full' : 'degraded')
      : recovering ? 'degraded' : 'minimal';
    if (target === this.automatic) { this.candidate = null; this.count = 0; return; }
    if (this.candidate !== target) { this.candidate = target; this.count = 1; } else this.count++;
    const worse = rank.indexOf(target) > rank.indexOf(this.automatic);
    if (this.count >= (worse ? this.config.downgradeReports : this.config.upgradeReports) && now - this.lastChange >= this.config.dwellMs) {
      this.automatic = target; this.lastChange = now; this.candidate = null; this.count = 0;
      this.reason = worse ? 'Sustained latency or jitter' : 'Connection recovered';
    }
  }
  tick(now) {
    if (now - this.lastReport >= this.config.missingReportsMs && this.automatic !== 'minimal') {
      this.automatic = 'minimal'; this.lastChange = now; this.candidate = null; this.count = 0;
      this.reason = `No latency report for ${this.config.missingReportsMs / 1000} seconds`;
    }
  }
}
