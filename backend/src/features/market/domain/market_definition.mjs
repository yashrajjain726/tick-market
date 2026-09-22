// Versioned contract: integer cents and 1e-8 asset units, two supported intervals.
export const INTERVALS = Object.freeze({ '1m': 60000, '5m': 300000 });
export const MARKET_DEFAULTS = Object.freeze({
  symbol: 'BTC-USD', name: 'Bitcoin', baseAsset: 'BTC', quoteAsset: 'USD',
  quoteSign: '$', badge: '₿', initialPrice: 6742000, bookLevels: 20,
});
export const FEED = Object.freeze({
  stepMs: 100, retainedCandles: 500, retainedTrades: 40, historyLimit: 120,
  summaryBuckets: 360, summaryWindow: '6h', bookEveryTicks: 2, summaryEveryTicks: 10,
});
export function describeMarket(settings) {
  const { symbol, name, baseAsset, quoteAsset, quoteSign, badge } = settings;
  return { symbol, name, baseAsset, quoteAsset, quoteSign, badge,
    priceScale: 100, quantityScale: 100000000, intervals: Object.keys(INTERVALS),
    summaryWindow: FEED.summaryWindow };
}

// Deterministic simulator coefficients, deliberately separate from live values.
export const SIMULATION = Object.freeze({
  longWaveAmplitude: 18000, longWavePeriod: 8000, shortWaveAmplitude: 9000,
  shortWavePeriod: 1800, noiseRange: 401, noiseMidpoint: 200, meanReversion: 0.004,
  minimumPrice: 10000, minimumQuantity: 10000, quantityRange: 1800000,
  bookPriceIncrement: 100, bookSpread: 200, bookStep: 200,
  bookMinimumQuantity: 500000, bookBidCycle: 15000000, bookAskCycle: 13000000,
});
