#!/bin/bash

export WHISKY_WINE_DIR="$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin"
export WHISKY_WINE="$WHISKY_WINE_DIR/wine64"
export WINESERVER="$WHISKY_WINE_DIR/wineserver"
export WINEPREFIX="$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles/317F6830-0FEB-4FC7-B091-95A86312ABB3"
export WINEDEBUG=-all

# Ensure wineserver is running persistently (timeout 0 = never auto-shutdown)
# use it only when do a lot of compiles and do not want to wait.... use pkill -f wineserver to stop it when done
# "$WINESERVER" -p

INPUT="$1"
FILE="${INPUT//\//\\}"
echo "Compiling: $FILE"

"$WHISKY_WINE" "C:\Program Files\MetaTrader 5\terminal64.exe"