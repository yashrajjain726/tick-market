export const DEFAULT_DELIVERY = Object.freeze({
  periods: Object.freeze({ full: 100, degraded: 500, minimal: 2000 }),
  degradedRtt: 250, degradedJitter: 80, minimalRtt: 700, minimalJitter: 200,
  fullRecoveryRtt: 180, fullRecoveryJitter: 50, degradedRecoveryRtt: 550,
  degradedRecoveryJitter: 140, downgradeReports: 2, upgradeReports: 4,
  dwellMs: 5000, missingReportsMs: 15000, reportIntervalMs: 1000,
  heartbeatTimeoutMs: 30000, statusIntervalMs: 1000, rateWindowMs: 5000,
  maxMetricMs: 60000,
});
// Domain relationships remain independent of configuration parsing libraries.
export function deliverySettingsConsistent(settings) {
  const p = settings.periods;
  return p.full <= p.degraded && p.degraded <= p.minimal &&
    settings.fullRecoveryRtt < settings.degradedRtt && settings.degradedRtt < settings.minimalRtt &&
    settings.fullRecoveryJitter < settings.degradedJitter && settings.degradedJitter < settings.minimalJitter &&
    settings.degradedRecoveryRtt < settings.minimalRtt && settings.degradedRecoveryJitter < settings.minimalJitter &&
    settings.missingReportsMs > settings.reportIntervalMs && settings.heartbeatTimeoutMs > settings.missingReportsMs;
}
