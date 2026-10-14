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

total_packages=$#

# Ensure at least one package name is provided
if [ $total_packages -eq 0 ]; then
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

total_bytes=0
results=""
current_package=0

echo ""
echo "Fetching data for $total_packages package(s)..."

# 1. Gather all data first with a progress bar
for pkg in "$@"; do
    current_package=$((current_package + 1))
    percent=$((current_package * 100 / total_packages))
    
    # Calculate progress bar width (40 chars total)
    bar_width=40
    filled_width=$((percent * bar_width / 100))
    empty_width=$((bar_width - filled_width))
    
    # Build the bar strings (using standard bash loops to be universally compatible)
    bar=""
    for ((i=0; i<filled_width; i++)); do bar="${bar}#"; done
    empty_bar=""
    for ((i=0; i<empty_width; i++)); do empty_bar="${empty_bar}-"; done
    
    # Print the progress bar. 
    # \r resets to the start of the line. \033[K clears the rest of the line so shorter package names don't leave artifacts.
    printf "\r\033[K[%s%s] %d%% (%d/%d) | Checking: %s" "$bar" "$empty_bar" "$percent" "$current_package" "$total_packages" "$pkg"

    # Fetch all APK paths (natively handles Split APKs)
    paths=$($ADB shell pm path "$pkg" 2>/dev/null | sed 's/^package://' | tr -d '\r')
    
    if [ -z "$paths" ]; then
        # Use -1 as the size so "Not installed" apps sort to the very bottom
        results="${results}-1 ${pkg}\n"
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
    
    results="${results}${pkg_bytes} ${pkg}\n"
    total_bytes=$((total_bytes + pkg_bytes))
done

# Print a newline to lock in the 100% progress bar
echo ""
echo ""

# 2. Print Header
echo "==================================================================="
printf "%-45s | %-15s\n" "Android Package" "APK Size"
echo "==================================================================="

# 3. Sort the raw bytes numerically (descending) and print
printf "%b" "$results" | sort -nr | while read -r size pkg; do
    if [ -z "$pkg" ]; then continue; fi # Skip empty lines
    
    if [ "$size" -eq -1 ]; then
        printf "%-45s | %-15s\n" "$pkg" "Not installed"
    else
        formatted_size=$(format_bytes "$size")
        printf "%-45s | %-15s\n" "$pkg" "$formatted_size"
    fi
done

# 4. Print Footer
echo "==================================================================="
printf "%-45s | %-15s\n" "TOTAL SIZE" "$(format_bytes "$total_bytes")"
echo "==================================================================="

echo ""
echo "Note: This measures the installation size of the base and split APKs. User Data and App Cache are excluded because fetching them requires a rooted device."