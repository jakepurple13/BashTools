#!/bin/bash

DEVICE_SERIAL=""

# Parse arguments for the optional -s flag
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--serial)
            if [ -z "$2" ]; then
                echo "Error: Missing serial number after $1"
                exit 1
            fi
            DEVICE_SERIAL="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            break # The rest of the arguments are package names
            ;;
    esac
done

# Ensure at least one package name is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 [-s <serial>] <package_name_1> [package_name_2] ..."
    echo "Example: $0 -s emulator-5554 com.android.chrome com.google.android.youtube"
    exit 1
fi

# Check if adb is installed
if ! command -v adb &> /dev/null; then
    echo "Error: adb is not installed or not in your PATH."
    exit 1
fi

# Handle device selection if no serial was provided
if [ -z "$DEVICE_SERIAL" ]; then
    # Get a list of connected and authorized devices
    # (Safe for Bash 3.2 / macOS and avoids process substitution)
    devices=($(adb devices | awk 'NR>1 && $2=="device" {print $1}'))
    
    device_count=${#devices[@]}

    if [ "$device_count" -eq 0 ]; then
        echo "Error: No authorized Android devices connected."
        exit 1
    elif [ "$device_count" -eq 1 ]; then
        DEVICE_SERIAL="${devices[0]}"
        echo "Only one device detected. Using: $DEVICE_SERIAL"
    else
        echo "Multiple devices detected. Please select one:"
        # Use select to create an interactive menu
        select dev in "${devices[@]}"; do
            if [ -n "$dev" ]; then
                DEVICE_SERIAL="$dev"
                echo "Selected device: $DEVICE_SERIAL"
                break
            else
                echo "Invalid selection. Please choose a number from the list."
            fi
        done
    fi
fi

# Define the ADB command with the specific serial
ADB="adb -s $DEVICE_SERIAL"

# Verify the target device is reachable
if ! $ADB get-state &> /dev/null; then
    echo "Error: Device '$DEVICE_SERIAL' is not connected or unauthorized."
    exit 1
fi

# Function to convert bytes to human-readable format (KB, MB, GB)
format_bytes() {
    local bytes=$1
    if [[ ! "$bytes" =~ ^[0-9]+$ ]] || [ "$bytes" -eq 0 ]; then
        echo "0 B"
        return
    fi
    awk -v b="$bytes" 'BEGIN {
        split("B KB MB GB TB", u);
        i = 1;
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf (i==1 ? "%d %s" : "%.2f %s"), b, u[i]
    }'
}

echo ""
echo "==================================================================="
printf "%-45s | %-15s\n" "Android Package" "APK Size"
echo "==================================================================="

total_bytes=0

# Iterate through every package name passed as an argument
for pkg in "$@"; do
    # Fetch all APK paths (natively handles Split APKs)
    paths=$($ADB shell pm path "$pkg" 2>/dev/null | sed 's/^package://' | tr -d '\r')
    
    if [ -z "$paths" ]; then
        printf "%-45s | %-15s\n" "$pkg" "Not installed"
        continue
    fi
    
    pkg_bytes=0
    # Iterate over every file associated with the package and tally the bytes
    for file_path in $paths; do
        # 'stat -c %s' uses Android's native shell to get the exact file size
        size=$($ADB shell stat -c "%s" "$file_path" 2>/dev/null | tr -d '\r')
        
        if [[ "$size" =~ ^[0-9]+$ ]]; then
            pkg_bytes=$((pkg_bytes + size))
        fi
    done
    
    formatted_size=$(format_bytes "$pkg_bytes")
    printf "%-45s | %-15s\n" "$pkg" "$formatted_size"
    
    total_bytes=$((total_bytes + pkg_bytes))
done

echo "==================================================================="
printf "%-45s | %-15s\n" "TOTAL SIZE" "$(format_bytes "$total_bytes")"
echo "==================================================================="

echo ""
echo "Note: This measures the installation size of the base and split APKs. User Data and App Cache are excluded because fetching them requires a rooted device."