# Gomez Alpha Bot

GOMEZ ALPHA BOT is an MT5 Expert Advisor project for EURUSD market analysis.

## Project structure

```text
Gomez-Alpha-Bot/
├── README.md
└── src/
    └── Gomez_Alpha_Bot.mq5
```

## Initial strategy specification

- **Symbol:** EURUSD by default (broker symbol can be configured in inputs).
- **Signal timeframe:** M15, evaluated on a newly opened candle using the previous closed candle.
- **Trend timeframe:** H1.
- **Indicators:** EMA 50/200, RSI, MACD and ATR.
- **Market context:** recent support and resistance levels.
- **Signal output:** BUY, SELL or WAIT. WAIT is the default when conditions are not aligned or data is unavailable.
- **Risk references:** illustrative ATR-based stop-loss and take-profit levels for analysis only.

## Safety scope

**Analysis-only.** The initial EA source does not send, modify or close trading orders. It is not configured for live execution and does not use martingale, grid trading, averaging down, or forced trades.

This is an initial implementation and must be compiled in MetaEditor and tested on historical data and a demo account before relying on its signals. It does not guarantee profits or replace independent risk management.

## Next development steps

1. Compile and resolve any MetaEditor errors or warnings.
2. Verify swing-structure and support/resistance calculations.
3. Add clear signal logging and test against historical EURUSD data.
4. Keep order execution disabled unless a separate, explicitly reviewed specification changes the analysis-only requirement.
