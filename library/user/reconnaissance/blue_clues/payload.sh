#!/bin/sh
# Title: Blue Clues
# Author: Brandon Starkweather

# --- 1. LOG SETUP ---
CURRENT_DIR=$(pwd)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${CURRENT_DIR}/blueclues_${TIMESTAMP}.txt"
touch "$LOG_FILE"

# --- 2. HARDWARE CONTROL ---
set_global_color() {
    # $1=R, $2=G, $3=B
    for dir in up down left right; do
        if [ -f "/sys/class/leds/${dir}-led-red/brightness" ]; then
            echo "$1" > "/sys/class/leds/${dir}-led-red/brightness"
            echo "$2" > "/sys/class/leds/${dir}-led-green/brightness"
            echo "$3" > "/sys/class/leds/${dir}-led-blue/brightness"
        fi
    done
}

set_led() {
    # 0=OFF, 1=RED (Found), 2=GREEN (Idle), 3=BLUE (Scanning)
    case "$1" in
        1) set_global_color 255 0 0 ;;
        2) set_global_color 0 255 0 ;;
        3) set_global_color 0 0 255 ;;
        0) set_global_color 0 0 0 ;;
    esac
}

do_vibe() {
    if [ -f "/sys/class/leds/buzzer/brightness" ]; then
        echo "255" > /sys/class/leds/buzzer/brightness
        sleep 0.2
        echo "0" > /sys/class/leds/buzzer/brightness
    fi
}

cleanup() {
    set_led 0
    rm /tmp/bt_scan.txt 2>/dev/null
}
trap cleanup EXIT

# --- 3. INIT ---
for led in /sys/class/leds/*; do
    if [ -f "$led/trigger" ]; then echo "none" > "$led/trigger"; fi
done
set_led 0

if ! command -v hcitool >/dev/null; then
    PROMPT "ERROR: hcitool missing."
    exit 1
fi

hciconfig hci0 up >/dev/null 2>&1

# --- 4. INTRO ---
PROMPT "BLUE CLUES v1

WORKFLOW:
1. Scan area for devices.
2. Review findings.
3. Repeat or Save Log.

All data is auto-saved.
Press OK to Begin."

# --- 5. MAIN LOOP ---
while true; do
    # A. READY / SCAN PROMPT
    set_led 2 # Green
    PROMPT "READY TO SCAN

Scan takes 10-15 seconds.

Press OK to Start."
    
    # B. SCANNING
    set_led 3 # Blue
    # Provide visual feedback on screen while working
    # (Since we can't update the prompt dynamically in sh easily, we just wait)
    hcitool scan > /tmp/bt_scan.txt
    
    # C. PROCESS & LOG
    RAW_DATA=$(tail -n +2 /tmp/bt_scan.txt)
    COUNT=$(echo "$RAW_DATA" | grep -c ":")
    
    if [ -n "$RAW_DATA" ]; then
        echo "$RAW_DATA" >> "$LOG_FILE"
    fi
    
    # D. DISPLAY RESULTS
    if [ "$COUNT" -gt 0 ]; then
        set_led 1 # Red
        do_vibe
        
        DISPLAY_DATA=$(echo "$RAW_DATA" | awk '{$1=""; print $0}')
        
        PROMPT "FOUND: $COUNT NEW
$DISPLAY_DATA

(Saved to Log)
Press OK for Menu."
    else
        set_led 2 # Green
        PROMPT "NO DEVICES FOUND.

(Try moving location)
Press OK for Menu."
    fi
    
    set_led 0
    
    # E. DECISION MENU
    ACTION=$(NUMBER_PICKER "1:Scan 2:Save" 1)
    
    if [ "$ACTION" -eq 2 ]; then
        break
    fi
    # If 1, loop repeats...
done

# --- 6. SESSION SUMMARY ---
set_led 2 # Green
if [ -s "$LOG_FILE" ]; then
    UNIQUE=$(sort -u "$LOG_FILE" | grep -c ":")
    # Show only the filename, not full path if it's too long, or use basename
    FILENAME=$(basename "$LOG_FILE")
    
    PROMPT "SESSION SAVED

Unique Devices: $UNIQUE
File: $FILENAME"
else
    PROMPT "SESSION ENDED
    
No devices found.
Log file empty."
    rm "$LOG_FILE" 2>/dev/null
fi

exit 0