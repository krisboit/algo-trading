#!/bin/bash

export WHISKY_WINE_DIR="$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin"
export WHISKY_WINE="$WHISKY_WINE_DIR/wine64"
export WINESERVER="$WHISKY_WINE_DIR/wineserver"
export WINEPREFIX="$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles/317F6830-0FEB-4FC7-B091-95A86312ABB3"
export WINEDEBUG=-all

# Ensure wineserver is running persistently (timeout 0 = never auto-shutdown)
# use it only when do a lot of compiles and do not want to wait.... use pkill -f wineserver to stop it when done
# "$WINESERVER" -p

# MetaEditor resolves /compile: paths relative to CWD, which Wine maps to the MT5 install dir.
# We must run from the MQL5 directory so that paths like "Experts\SessionBreakout.mq5" resolve correctly.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MQL5_DIR="$(dirname "$SCRIPT_DIR")/MQL5"
cd "$MQL5_DIR" || { echo "Error: MQL5 directory not found at $MQL5_DIR"; exit 1; }

INPUT="$1"
FILE="${INPUT//\//\\}"
echo "Compiling: $FILE"

"$WHISKY_WINE" "C:\Program Files\MetaTrader 5\MetaEditor64.exe" /compile:"$FILE" /log:compile.log

# Colors
RED='\033[0;31m'
YELLOW='\033[0;33m'
GRAY='\033[0;90m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Convert from UTF-16 to UTF-8, filter and colorize output
iconv -f UTF-16 -t UTF-8 compile.log 2>/dev/null | grep -v "information: generating code" | sed 's|C:\\Program Files\\MetaTrader 5\\MQL5\\||g' | sed 's|\\|/|g' | while IFS= read -r line; do
    
    if [[ "$line" == *": error"* ]] || [[ "$line" == *"errors,"* && "$line" != "Result: 0 errors"* ]]; then
        echo -e "${RED}${line}${NC}"
    elif [[ "$line" == *": warning"* ]] || [[ "$line" == *"warnings,"* ]]; then
        echo -e "${YELLOW}${line}${NC}"
    elif [[ "$line" == *": information:"* ]]; then
        echo -e "${GRAY}${line}${NC}"
    elif [[ "$line" == "Result: 0 errors, 0 warnings"* ]]; then
        echo -e "${GREEN}${line}${NC}"
    elif [[ "$line" == "Result:"* ]]; then
        echo -e "${YELLOW}${line}${NC}"
    else
        echo -e "${GRAY}${line}${NC}"
    fi
done
rm -rf compile.log
