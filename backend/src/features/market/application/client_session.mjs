import { INTERVALS } from '../domain/market_definition.mjs';
import { DEFAULT_DELIVERY } from '../domain/delivery_config.mjs';
import { DeliveryPolicy } from '../domain/delivery_policy.mjs';
import { ChartDelivery } from '../domain/chart_delivery.mjs';

/** Application port: channel.send(event) -> boolean; channel.close(code, reason).
 * No HTTP, WebSocket, JSON, process environment, or real timers in this class. */
export class ClientSession {
  constructor({ market, channel, now, debug, policy = DEFAULT_DELIVERY }) {
    this.config = policy;
    this.market = market;
    this.channel = channel;
    this.debug = debug;
    this.policy = new DeliveryPolicy(now, policy);
    this.delivery = new ChartDelivery();
    this.interval = Object.keys(INTERVALS)[0];
    this.revision = 0;
    this.subscribed = false;
    this.connectedAt = now;
    this.lastStatus = -Infinity;
    this.lastTier = '';
    this.sentAt = [];
    this.lastHeard = now;
    this.skipBook = false;
    this.lastReport = -Infinity;
  }

  status(now, force = false) {
    const tier = this.policy.tier;
    if (!force && now - this.lastStatus < this.config.statusIntervalMs && tier === this.lastTier) return;
    this.lastTier = tier;
    this.lastStatus = now;
    this.sentAt = this.sentAt.filter(t => now - t < this.config.rateWindowMs);
    this.channel.send({ type: 'status', tier, targetHz: 1000 / this.policy.period,
      effectiveHz: this.sentAt.length / Math.max(1, Math.min(this.config.rateWindowMs / 1000, (now - this.connectedAt) / 1000)),
      override: this.policy.override,
      reason: this.policy.override ? 'Manual demonstration' : this.policy.reason });
  }

  receive(command, now) {
    this.lastHeard = now;
    if (command.type === 'subscribe') {
      if (!Object.hasOwn(INTERVALS, command.interval) || !Number.isSafeInteger(command.revision) || command.revision < 1) {
        throw new Error('Invalid subscription');
      }
      this.interval = command.interval;
      this.revision = command.revision;
      this.subscribed = true;
      this.delivery = new ChartDelivery();
      const active = this.market.candles[this.interval].at(-1);
      if (active) this.delivery.collect(active);
      this.channel.send({ type: 'subscribed', interval: this.interval, revision: this.revision });
      this.channel.send({ type: 'trades', streamId: this.market.streamId,
        trades: this.market.recent, summary: this.market.summary });
      this.status(now, true);
    } else if (command.type === 'ping') {
      if (!Number.isSafeInteger(command.nonce)) throw new Error('Invalid nonce');
      this.channel.send({ type: 'pong', nonce: command.nonce });
    } else if (command.type === 'metrics') {
      if (![command.rtt, command.jitter].every(n => typeof n === 'number' && Number.isFinite(n) && n >= 0 && n <= this.config.maxMetricMs)) {
        throw new Error('Invalid metrics');
      }
      if (now - this.lastReport >= this.config.reportIntervalMs) {
        this.policy.report(command.rtt, command.jitter, now);
        this.lastReport = now;
      }
      this.status(now, true);
    } else if (command.type === 'override' && this.debug) {
      this.policy.force(command.tier === 'auto' ? null : command.tier);
      this.status(now, true);
    } else if (command.type === 'debug' && this.debug) {
      if (command.action === 'skip_book') this.skipBook = true;
      else if (command.action === 'disconnect') this.channel.close(4000, 'Demonstration disconnect');
      else throw new Error('Unknown debug action');
    } else throw new Error('Unknown command');
  }

  publish({ trade, book, summary }, now) {
    if (now - this.lastHeard > this.config.heartbeatTimeoutMs) {
      this.channel.close(4001, 'Heartbeat timeout');
      return;
    }
    this.policy.tick(now);
    if (!this.subscribed) return;
    if (book) {
      if (this.skipBook) this.skipBook = false;
      else this.channel.send({ type: 'book', ...book });
    }
    this.channel.send({ type: 'trades', streamId: this.market.streamId, trades: [trade],
      ...(summary ? { summary } : {}) });
    this.delivery.collect(this.market.candles[this.interval].at(-1));
    const candles = this.delivery.flush(now, this.policy.period);
    if (candles && this.channel.send({ type: 'candles', streamId: this.market.streamId,
      interval: this.interval, revision: this.revision, candles })) this.sentAt.push(now);
    this.status(now);
  }
}
