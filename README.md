# Gomez Alpha Bot

**GOMEZ ALPHA BOT** is an MetaTrader 5 Expert Advisor project for structured EURUSD market analysis. The current source version is **1.10**.

## Project structure

```text
Gomez-Alpha-Bot/
├── README.md
└── src/
    └── Gomez_Alpha_Bot.mq5
```

## Strategy framework

- **Default market:** EURUSD. Configure the exact broker symbol if it uses a suffix or prefix.
- **Signal timeframe:** M15; evaluate the previous fully closed candle when a new M15 candle begins.
- **Trend timeframe:** H1; EMA 50/200 alignment and the last closed H1 price relative to EMA 200.
- **Momentum:** RSI and MACD confirmation on the signal timeframe.
- **Volatility:** ATR for context and illustrative risk-reference levels.
- **Structure:** confirmed swing-high and swing-low pivots with configurable lookback and swing strength; recent extremes are used as a fallback context reference if a pivot is missing on one side.
- **Output:** BUY, SELL or WAIT. WAIT remains the default unless the configured checks align.
- **Reporting:** chart comment and Experts log with the signal, timeframe, closed-candle time, indicator values, structure levels and assessment reason.

## Safety scope

**ANALYSIS ONLY — NO ORDERS.** The EA source contains no order placement, modification, or closing calls. It does not use martingale, grid trading, averaging down, or forced entries. Stop-loss and take-profit values are illustrative ATR-based references only; they are not submitted to a broker.

## Validation status

Version 1.10 improves input validation, indicator readiness checks, signal explanations, H1 price confirmation, and swing-based structure detection. **It has not yet been compiled or tested in MetaEditor in this repository workflow.** Review the source, compile it in MetaEditor, resolve compiler messages, then validate behavior in the Strategy Tester and on a demo account. Do not rely on uncompiled or untested signals for trading decisions.

No strategy can guarantee profits. Historical and demo testing do not ensure future performance.

## Next milestones

1. Compile in MetaEditor and resolve all errors and warnings.
2. Verify confirmed swing pivots and support/resistance on historical charts.
3. Test data readiness, signal timing, and WAIT behavior in Strategy Tester.
4. Review signal quality and false positives before considering any further development.
