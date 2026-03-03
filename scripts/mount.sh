#!/bin/bash

# Get the directory where this script is located
# SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
 SCRIPT_DIR="$(pwd)"

# Whisky bottles location
BOTTLES_FOLDER="$HOME/Library/Containers/com.isaacmarovitz.Whisky/Bottles"

for BOTTLE in "$BOTTLES_FOLDER"/*; do
    # Skip if not a directory or is .DS_Store
    [ -d "$BOTTLE" ] || continue
    
    BOTTLE_NAME=$(basename "$BOTTLE")
    MT5_PATH="$BOTTLE/drive_c/Program Files/MetaTrader 5"
    
    # Check if MetaTrader 5 exists in this bottle
    if [ ! -d "$MT5_PATH" ]; then
        echo "Skipping $BOTTLE_NAME: No MetaTrader 5 installation found"
        continue
    fi
    
    echo "Found MetaTrader 5 in bottle: $BOTTLE_NAME"
    
    LINK_PATH="$MT5_PATH/MQL5"
    
    # Remove existing MQL5 (symlink or directory)
    if [ -L "$LINK_PATH" ]; then
        echo "Removing existing symlink: $LINK_PATH"
        rm "$LINK_PATH"
    elif [ -d "$LINK_PATH" ]; then
        echo "Warning: $LINK_PATH is a directory. Backing up to MQL5.bak"
        mv "$LINK_PATH" "${LINK_PATH}.bak"
    fi
    
    # Create symlink
    echo "Creating symlink: $LINK_PATH -> $SCRIPT_DIR"
    ln -s "$SCRIPT_DIR" "$LINK_PATH"
    
    if [ -L "$LINK_PATH" ]; then
        echo "Success!"
    else
        echo "Error: Failed to create symlink"
    fi
done

echo "Done."