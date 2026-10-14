# Gomez Alpha Bot

**GOMEZ ALPHA BOT v1.50** is a MetaTrader 5 Expert Advisor for multi-method EURUSD market analysis and transparent trade-plan reporting.

## Project structure

```text
Gomez-Alpha-Bot/
├── README.md
└── src/
    └── Gomez_Alpha_Bot.mq5
```

## Analysis framework

- **Multi-timeframe trend:** H1 EMA 50/200 alignment and last closed H1 price relative to EMA 200.
- **M15 setup:** EMA 50/200 alignment and closed price relative to EMA 50.
- **Momentum:** RSI and MACD agreement.
- **Trend strength:** ADX with +DI/-DI directional comparison.
- **Volatility and range context:** ATR and Bollinger Bands.
- **Price action:** basic bullish/bearish engulfing and pin-bar checks on closed candles.
- **Market structure:** confirmed swing-high/swing-low pivots, nearest support/resistance and a recent-extreme fallback when a pivot is unavailable.
- **Confluence score:** weighted directional evidence with a configurable minimum score. Scores are heuristic agreement measures, not statistically calibrated probabilities.
- **Trade-plan references:** closed-candle entry reference, ATR-based illustrative stop-loss and target, reward/risk calculation, nearby structure room and spread context.
- **Chart overlay:** draws nearest support/resistance levels and illustrative entry/stop-loss/take-profit lines when a BUY/SELL plan passes the filters. These are visual references only.
- **Trend dashboard (v1.50):** displays BUY/SELL/WAIT, H1 and M15 trend states, breakout/retest context, confluence scores, RSI, ADX, support/resistance, spread, and the reason for the decision.
- **Setup context:** flags closed-candle momentum breakout and EMA-retest candidates for context only; these labels do not independently trigger a signal.
- **Structure-aware risk references:** uses support/resistance with an ATR buffer when positioning illustrative stops, then checks the resulting reward/risk and nearby target room.
- **Decision:** BUY, SELL or WAIT. WAIT is retained whenever core trend/momentum/structure conditions conflict, current bid/ask or point data are unavailable, the spread exceeds the configured threshold, or the illustrative reward/risk fails the minimum.
- **Readiness retry:** if indicator history is still loading at the start of a new M15 candle, the bot waits and retries on later ticks instead of immediately marking that candle as processed.

## Default setup

- Symbol: EURUSD (adjust for broker suffixes/prefixes)
- Signal timeframe: M15
- Trend timeframe: H1
- EMA: 50 / 200
- RSI: 14
- MACD: 12 / 26 / 9
- ADX: 14
- ATR: 14
- Bollinger Bands: 20 periods, 2 deviations

Settings are configurable through the Expert Advisor inputs.

## Safety scope

**ANALYSIS ONLY — NO ORDERS.** The EA source does not place, modify, or close trades. It does not use martingale, grid trading, averaging down, or forced entries. Entry, stop-loss and take-profit values are analytical references only and are not sent to a broker.

## Validation status

Version 1.30 improved readiness handling and fail-safe market-data checks. Version 1.40 added chart-level visualisation. Version 1.50 adds a trend dashboard, breakout/retest context, and structure-aware illustrative risk levels. **It has not yet been compiled or tested in MetaEditor in this workflow.** Indicator buffer handling, pivot detection, score logic, broker symbol compatibility, and all compiler messages must still be checked in MetaEditor. Then use Strategy Tester and a demo account to evaluate signal timing, edge cases, false positives, and historical performance.

The confluence score is a rule-based heuristic, not a probability that a trade will win. Historical or demo results cannot guarantee future performance. Do not use the EA as the sole basis for a financial decision.

## Next milestones

1. Compile in MetaEditor and resolve errors/warnings, including chart-object API usage and dashboard text rendering.
2. Validate indicator buffers, swing-structure calculations, trend states, setup labels, and drawn support/resistance/entry/SL/TP levels visually against charts.
3. Test WAIT conditions, spread handling, reward/risk filtering and signal timing in Strategy Tester.
4. Review results over varied market regimes before considering further features.
