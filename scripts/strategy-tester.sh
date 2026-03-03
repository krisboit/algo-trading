#!/bin/bash

# Strategy Tester Script for MetaTrader 5
# Usage: ./strategy-tester.sh <ini-file>
# Example: ./strategy-tester.sh BB-Strategy.XAUUSD.M5.2025.ini

export WHISKY_WINE_DIR="$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin"
export WHISKY_WINE="$WHISKY_WINE_DIR/wine64"
export WINESERVER="$WHISKY_WINE_DIR/wineserver"
export WINEPREFIX="$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles/317F6830-0FEB-4FC7-B091-95A86312ABB3"
export WINEDEBUG=-all

# MT5 paths
MT5_PATH="$WINEPREFIX/drive_c/Program Files/MetaTrader 5"
MT5_CONFIG="$MT5_PATH/Config"
MT5_TESTER="$MT5_PATH/Tester"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if INI file argument is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: No INI file specified${NC}"
    echo ""
    echo "Usage: $0 <ini-file>"
    echo ""
    echo "Examples:"
    echo "  $0 BB-Strategy.XAUUSD.M5.2025.ini"
    echo "  $0 /path/to/your/config.ini"
    echo ""
    echo "Available INI files in Profiles/Tester:"
    
    # Get the script directory and find MQL5 folder
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    MQL5_DIR="$(dirname "$SCRIPT_DIR")/MQL5"
    TESTER_DIR="$MQL5_DIR/Profiles/Tester"
    
    if [ -d "$TESTER_DIR" ]; then
        ls -1 "$TESTER_DIR"/*.ini 2>/dev/null | xargs -n1 basename 2>/dev/null | head -20
    fi
    exit 1
fi

INI_INPUT="$1"

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MQL5_DIR="$(dirname "$SCRIPT_DIR")/MQL5"
TESTER_DIR="$MQL5_DIR/Profiles/Tester"

# Resolve INI file path
if [ -f "$INI_INPUT" ]; then
    # Absolute or relative path provided
    INI_FILE="$(cd "$(dirname "$INI_INPUT")" && pwd)/$(basename "$INI_INPUT")"
elif [ -f "$TESTER_DIR/$INI_INPUT" ]; then
    # File name only, look in Tester folder
    INI_FILE="$TESTER_DIR/$INI_INPUT"
else
    echo -e "${RED}Error: INI file not found: $INI_INPUT${NC}"
    echo ""
    echo "Searched in:"
    echo "  - Current directory"
    echo "  - $TESTER_DIR"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  MetaTrader 5 Strategy Tester${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}INI File:${NC} $(basename "$INI_FILE")"
echo ""

# Extract info from INI file for display
if command -v iconv &> /dev/null; then
    # INI is UTF-16LE, convert and extract info
    INI_CONTENT=$(iconv -f UTF-16LE -t UTF-8 "$INI_FILE" 2>/dev/null)
    
    EXPERT=$(echo "$INI_CONTENT" | grep "^Expert=" | cut -d= -f2 | tr -d '\r')
    SYMBOL=$(echo "$INI_CONTENT" | grep "^Symbol=" | cut -d= -f2 | tr -d '\r')
    PERIOD=$(echo "$INI_CONTENT" | grep "^Period=" | cut -d= -f2 | tr -d '\r')
    FROM_DATE=$(echo "$INI_CONTENT" | grep "^FromDate=" | cut -d= -f2 | tr -d '\r')
    TO_DATE=$(echo "$INI_CONTENT" | grep "^ToDate=" | cut -d= -f2 | tr -d '\r')
    OPTIMIZATION=$(echo "$INI_CONTENT" | grep "^Optimization=" | cut -d= -f2 | tr -d '\r')
    SHUTDOWN=$(echo "$INI_CONTENT" | grep "^ShutdownTerminal=" | cut -d= -f2 | tr -d '\r')
    
    if [ -n "$SYMBOL" ]; then
        echo -e "${YELLOW}Test Configuration:${NC}"
        echo "  Expert: $EXPERT"
        echo "  Symbol: $SYMBOL"
        echo "  Period: $PERIOD"
        echo "  Date Range: $FROM_DATE to $TO_DATE"
        case "$OPTIMIZATION" in
            0) echo "  Mode: Single Test" ;;
            1) echo "  Mode: Slow Complete Optimization" ;;
            2) echo "  Mode: Fast Genetic Optimization" ;;
            3) echo "  Mode: All Symbols in Market Watch" ;;
            *) echo "  Mode: Unknown ($OPTIMIZATION)" ;;
        esac
        if [ "$SHUTDOWN" = "1" ]; then
            echo "  Auto-shutdown: Yes"
        else
            echo "  Auto-shutdown: No"
        fi
        echo ""
    fi
fi

# Copy INI file to MT5 Tester folder (MT5 looks for tester configs there)
DEST_INI="$MT5_TESTER/$(basename "$INI_FILE")"
echo -e "${YELLOW}Copying INI to MT5 Tester folder...${NC}"
cp "$INI_FILE" "$DEST_INI"

if [ ! -f "$DEST_INI" ]; then
    echo -e "${RED}Error: Failed to copy INI file${NC}"
    exit 1
fi

# Windows path for the INI file
WIN_INI_PATH="C:\\Program Files\\MetaTrader 5\\Tester\\$(basename "$INI_FILE")"
echo -e "${GREEN}Windows Path:${NC} $WIN_INI_PATH"
echo ""

echo -e "${YELLOW}Starting Strategy Tester...${NC}"
if [ "$SHUTDOWN" = "1" ]; then
    echo -e "${YELLOW}(Terminal will close automatically when testing is complete)${NC}"
fi
echo ""

# Start MetaTrader 5 terminal with the tester config
# Using /config: parameter with the INI file path
"$WHISKY_WINE" "C:\\Program Files\\MetaTrader 5\\terminal64.exe" "/config:$WIN_INI_PATH"

# Wait for terminal to exit
WINE_EXIT_CODE=$?

echo ""
if [ $WINE_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}Strategy testing completed!${NC}"
else
    echo -e "${YELLOW}Terminal exited with code: $WINE_EXIT_CODE${NC}"
fi

# Clean up - remove the copied INI file
rm -f "$DEST_INI" 2>/dev/null

# Check tester agent sandboxes for exported JSON files
# Strategy Tester agents write to their own MQL5/Files, not the terminal's
AGENTS_DIR="$MT5_PATH/Tester"
FOUND_JSON=0
for AGENT_DIR in "$AGENTS_DIR"/Agent-*/MQL5/Files; do
    if [ -d "$AGENT_DIR" ]; then
        # Find JSON files modified in the last 5 minutes
        RECENT_JSON=$(find "$AGENT_DIR" -name "*.json" -type f -newer "$0" -mmin -5 2>/dev/null | sort -t/ -k1 | tail -5)
        if [ -n "$RECENT_JSON" ]; then
            while IFS= read -r JSON_FILE; do
                BASENAME=$(basename "$JSON_FILE")
                DEST="$MQL5_DIR/Files/$BASENAME"
                cp "$JSON_FILE" "$DEST"
                FOUND_JSON=1
                echo ""
                echo -e "${GREEN}Strategy export found:${NC}"
                echo "  $DEST"
                FILE_SIZE=$(ls -lh "$DEST" 2>/dev/null | awk '{print $5}')
                echo "  Size: $FILE_SIZE"
            done <<< "$RECENT_JSON"
        fi
    fi
done

if [ $FOUND_JSON -eq 0 ]; then
    # Fallback: check main MQL5/Files
    LATEST_JSON=$(ls -t "$MQL5_DIR/Files"/*.json 2>/dev/null | head -1)
    if [ -n "$LATEST_JSON" ]; then
        echo ""
        echo -e "${GREEN}Strategy export:${NC}"
        echo "  $LATEST_JSON"
    fi
fi

# Also check MT5's tester results folder
TESTER_RESULTS="$MT5_TESTER/logs"
if [ -d "$TESTER_RESULTS" ]; then
    LATEST_XML=$(ls -t "$TESTER_RESULTS"/*.xml 2>/dev/null | head -1)
    if [ -n "$LATEST_XML" ]; then
        echo ""
        echo -e "${GREEN}MT5 Tester Report:${NC}"
        echo "  $LATEST_XML"
    fi
fi

echo ""
echo -e "${BLUE}Done.${NC}"
