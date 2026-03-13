#!/bin/bash

# Run optimizations one by one. Delete lines as they complete.
# Kill all Wine processes between each run to prevent hangs.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

kill_wine() {
    pkill -f "terminal64.exe" 2>/dev/null
    pkill -f "metatester64.exe" 2>/dev/null
    pkill -f "MetaEditor64.exe" 2>/dev/null
    pkill -f "explorer.exe" 2>/dev/null
    pkill -f "conhost.exe" 2>/dev/null
    sleep 2
    pkill -9 -f "terminal64.exe" 2>/dev/null
    pkill -9 -f "metatester64.exe" 2>/dev/null
    pkill -f "wineserver" 2>/dev/null
    sleep 1
}

run() {
    echo ""
    echo "=========================================="
    echo "  $1"
    echo "=========================================="
    kill_wine
    "$SCRIPT_DIR/strategy-tester.sh" "$1"
}

# --- Already completed (remove the # to re-run) ---
# --- Remaining ---
run EMACrossoverPullback.BTCUSD.M15.H1.ini
run EMACrossoverPullback.BTCUSD.M15.H4.ini
run EMACrossoverPullback.BTCUSD.M5.H1.ini
run EMACrossoverPullback.BTCUSD.M5.H4.ini
run EMACrossoverPullback.DJ30.M15.H1.ini
run EMACrossoverPullback.DJ30.M15.H4.ini
run EMACrossoverPullback.DJ30.M5.H1.ini
run EMACrossoverPullback.DJ30.M5.H4.ini
run EMACrossoverPullback.NAS100.M15.H1.ini
run EMACrossoverPullback.NAS100.M15.H4.ini
run EMACrossoverPullback.NAS100.M5.H1.ini
run EMACrossoverPullback.NAS100.M5.H4.ini
run EMACrossoverPullback.XAUUSD.M15.H1.ini
run EMACrossoverPullback.XAUUSD.M15.H4.ini
run EMACrossoverPullback.XAUUSD.M5.H1.ini
run EMACrossoverPullback.XAUUSD.M5.H4.ini
run MeanReversionBBRSI.BTCUSD.M15.ini
run MeanReversionBBRSI.BTCUSD.M5.ini
run MeanReversionBBRSI.DJ30.M15.ini
run MeanReversionBBRSI.DJ30.M5.ini
run MeanReversionBBRSI.NAS100.M15.ini
run MeanReversionBBRSI.NAS100.M5.ini
run MeanReversionBBRSI.XAUUSD.M15.ini
run MeanReversionBBRSI.XAUUSD.M5.ini
run MomentumBreakout.BTCUSD.M15.ini
run MomentumBreakout.BTCUSD.M5.ini
run MomentumBreakout.DJ30.M15.ini
run MomentumBreakout.DJ30.M5.ini
run MomentumBreakout.NAS100.M15.ini
run MomentumBreakout.NAS100.M5.ini
run MomentumBreakout.XAUUSD.M15.ini
run MomentumBreakout.XAUUSD.M5.ini
run OrderBlockFVG.BTCUSD.M15.H1.ini
run OrderBlockFVG.BTCUSD.M15.H4.ini
run OrderBlockFVG.BTCUSD.M5.H1.ini
run OrderBlockFVG.BTCUSD.M5.H4.ini
run OrderBlockFVG.DJ30.M15.H1.ini
run OrderBlockFVG.DJ30.M15.H4.ini
run OrderBlockFVG.DJ30.M5.H1.ini
run OrderBlockFVG.DJ30.M5.H4.ini
run OrderBlockFVG.NAS100.M15.H1.ini
run OrderBlockFVG.NAS100.M15.H4.ini
run OrderBlockFVG.NAS100.M5.H1.ini
run OrderBlockFVG.NAS100.M5.H4.ini
run OrderBlockFVG.XAUUSD.M15.H1.ini
run OrderBlockFVG.XAUUSD.M15.H4.ini
run OrderBlockFVG.XAUUSD.M5.H1.ini
run OrderBlockFVG.XAUUSD.M5.H4.ini
run SessionBreakout.BTCUSD.M15.ini
run SessionBreakout.BTCUSD.M5.ini
run SessionBreakout.DJ30.M15.ini
run SessionBreakout.DJ30.M5.ini
run SessionBreakout.NAS100.M15.ini
run SessionBreakout.NAS100.M5.ini
run SessionBreakout.XAUUSD.M15.ini
run SessionBreakout.XAUUSD.M5.ini

echo ""
echo "All done!"
