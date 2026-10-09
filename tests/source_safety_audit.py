#!/usr/bin/env python3
"""Lightweight static safety checks for Gomez Alpha Bot.

This is NOT an MQL5 compiler and does not prove that the EA is profitable or
that every runtime behaviour is correct. It checks a few important source
invariants until the project can be compiled and tested in MetaEditor.
"""
from pathlib import Path
import re
import sys

SOURCE = Path(__file__).resolve().parents[1] / "src" / "Gomez_Alpha_Bot.mq5"


def main() -> int:
    if not SOURCE.is_file():
        print(f"FAIL: source file not found: {SOURCE}")
        return 1

    code = SOURCE.read_text(encoding="utf-8")
    checks = {
        "source declares strict mode": r"(?m)^#property\s+strict\s*$",
        "source has a version": r'(?m)^#property\s+version\s+"[0-9.]+"\s*$',
        "analysis-only safety label exists": r"ANALYSIS ONLY",
        "WAIT signal is defined": r"\bSIGNAL_WAIT\b",
        "initialization handler exists": r"\bint\s+OnInit\s*\(",
        "tick handler exists": r"\bvoid\s+OnTick\s*\(",
        "cleanup handler exists": r"\bvoid\s+OnDeinit\s*\(",
        "indicator readiness retry is present": r"will retry on later ticks",
        "missing market tick fails safe": r"Current bid/ask or symbol point unavailable",
        "missing indicator data is handled safely": r"WAIT \| Price or indicator data unavailable",
        "missing structure data is handled safely": r"WAIT \| Reliable structure levels unavailable",
        "analysis uses closed M15 candle": r"iClose\(InpSymbol,InpSignalTimeframe,1\)",
        "analysis uses closed H1 candle": r"iClose\(InpSymbol,InpTrendTimeframe,1\)",
        "BUY requires H1 and M15 bullish confirmation": r"if\(h1Bullish\s*&&\s*m15Bullish\s*&&\s*momentumBullish",
        "SELL requires H1 and M15 bearish confirmation": r"if\(h1Bearish\s*&&\s*m15Bearish\s*&&\s*momentumBearish",
        "excessive spread forces WAIT": r"spreadPoints\s*>\s*InpMaximumSpreadPoints[\s\S]{0,180}signal\s*=\s*SIGNAL_WAIT",
        "insufficient reward/risk forces WAIT": r"rewardRisk\s*<\s*InpMinimumRewardRisk[\s\S]{0,180}signal\s*=\s*SIGNAL_WAIT",
        "WAIT is the default signal": r"SIGNAL_DIRECTION signal\s*=\s*SIGNAL_WAIT",
    }

    failed = False
    for label, pattern in checks.items():
        passed = re.search(pattern, code) is not None
        print(f"{'PASS' if passed else 'FAIL'}: {label}")
        failed |= not passed

    # Reject common MQL5 trade-execution APIs. Strip comments first so that
    # documentation text alone does not trigger a false positive.
    without_comments = re.sub(r"/\*.*?\*/", "", code, flags=re.S)
    without_comments = re.sub(r"(?m)//.*$", "", without_comments)
    forbidden = {
        "OrderSend": r"\bOrderSend\s*\(",
        "MqlTradeRequest": r"\bMqlTradeRequest\b",
        "CTrade": r"\bCTrade\b",
        "OrderCheck": r"\bOrderCheck\s*\(",
        "trade object order/position methods": r"\.\s*(?:Buy|Sell|BuyLimit|SellLimit|BuyStop|SellStop|PositionOpen|PositionClose|PositionModify|OrderOpen|OrderModify|OrderDelete)\s*\(",
    }
    for label, pattern in forbidden.items():
        found = re.search(pattern, without_comments) is not None
        print(f"{'FAIL' if found else 'PASS'}: no {label} execution API")
        failed |= found

    if failed:
        print("\nStatic audit FAILED. Review the source and rerun the checks.")
        return 1

    print("\nStatic audit PASSED. This is not a substitute for MetaEditor compilation.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
