#!/bin/bash

# Run all strategy optimization backtests
# Usage: ./scripts/run-optimizations.sh [strategy-filter] [symbol-filter]
# Examples:
#   ./scripts/run-optimizations.sh                          # Run ALL
#   ./scripts/run-optimizations.sh SessionBreakout          # Run only SessionBreakout
#   ./scripts/run-optimizations.sh SessionBreakout XAUUSD   # Run SessionBreakout on XAUUSD only
#   ./scripts/run-optimizations.sh "" BTCUSD                # Run all strategies on BTCUSD

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TESTER_DIR="$PROJECT_DIR/MQL5/Profiles/Tester"

STRATEGY_FILTER="${1:-}"
SYMBOL_FILTER="${2:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Collect matching .ini files
INI_FILES=()
for ini in "$TESTER_DIR"/*.ini; do
    [ -f "$ini" ] || continue
    basename=$(basename "$ini")

    # Skip the example strategy
    [[ "$basename" == Example* ]] && continue

    # Apply filters
    if [ -n "$STRATEGY_FILTER" ] && [[ "$basename" != ${STRATEGY_FILTER}* ]]; then
        continue
    fi
    if [ -n "$SYMBOL_FILTER" ] && [[ "$basename" != *${SYMBOL_FILTER}* ]]; then
        continue
    fi

    INI_FILES+=("$ini")
done

TOTAL=${#INI_FILES[@]}

if [ $TOTAL -eq 0 ]; then
    echo -e "${RED}No matching .ini files found.${NC}"
    echo "Strategy filter: '${STRATEGY_FILTER:-<none>}'"
    echo "Symbol filter: '${SYMBOL_FILTER:-<none>}'"
    exit 1
fi

echo -e "${BOLD}${BLUE}============================================${NC}"
echo -e "${BOLD}${BLUE}  Strategy Optimization Batch Runner${NC}"
echo -e "${BOLD}${BLUE}============================================${NC}"
echo ""
echo -e "${CYAN}Total runs: ${TOTAL}${NC}"
if [ -n "$STRATEGY_FILTER" ]; then
    echo -e "${CYAN}Strategy filter: ${STRATEGY_FILTER}${NC}"
fi
if [ -n "$SYMBOL_FILTER" ]; then
    echo -e "${CYAN}Symbol filter: ${SYMBOL_FILTER}${NC}"
fi
echo ""

# Summary of what will run
echo -e "${YELLOW}Queue:${NC}"
for ini in "${INI_FILES[@]}"; do
    echo "  $(basename "$ini")"
done
echo ""

read -p "Press Enter to start (Ctrl+C to cancel)..."
echo ""

# Run each
CURRENT=0
PASSED=0
FAILED=0
START_TIME=$(date +%s)

for ini in "${INI_FILES[@]}"; do
    CURRENT=$((CURRENT + 1))
    BASENAME=$(basename "$ini")

    echo -e "${BOLD}${BLUE}[${CURRENT}/${TOTAL}] ${BASENAME}${NC}"

    RUN_START=$(date +%s)

    "$SCRIPT_DIR/strategy-tester.sh" "$BASENAME" 2>&1

    RUN_EXIT=$?
    RUN_END=$(date +%s)
    RUN_DURATION=$((RUN_END - RUN_START))

    if [ $RUN_EXIT -eq 0 ]; then
        PASSED=$((PASSED + 1))
        echo -e "${GREEN}  Completed in ${RUN_DURATION}s${NC}"
    else
        FAILED=$((FAILED + 1))
        echo -e "${RED}  Failed (exit code ${RUN_EXIT}) in ${RUN_DURATION}s${NC}"
    fi

    echo ""
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_DURATION / 60))
SECONDS=$((TOTAL_DURATION % 60))

echo -e "${BOLD}${BLUE}============================================${NC}"
echo -e "${BOLD}${BLUE}  Batch Complete${NC}"
echo -e "${BOLD}${BLUE}============================================${NC}"
echo ""
echo -e "  ${GREEN}Passed: ${PASSED}${NC}"
echo -e "  ${RED}Failed: ${FAILED}${NC}"
echo -e "  Total time: ${MINUTES}m ${SECONDS}s"
echo ""

# List exported JSON files
echo -e "${YELLOW}Exported JSON files:${NC}"
find "$PROJECT_DIR/MQL5/Files" -name "*.json" -newer "$0" -mmin -$((TOTAL_DURATION / 60 + 5)) 2>/dev/null | while read f; do
    SIZE=$(ls -lh "$f" 2>/dev/null | awk '{print $5}')
    echo "  $(basename "$f") ($SIZE)"
done
echo ""
