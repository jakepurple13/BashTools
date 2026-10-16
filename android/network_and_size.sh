#!/bin/bash

DEVICE_SERIAL=""
SORT_BY="apk"

# Parse arguments for flags
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
        --sort)
            if [[ "$2" != "apk" && "$2" != "wifi" && "$2" != "mobile" ]]; then
                echo "Error: Invalid sort option '$2'. Must be 'apk', 'wifi', or 'mobile'."
                exit 1
            fi
            SORT_BY="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 [-s <serial>] [--sort apk|wifi|mobile] <package_name_1> ..."
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
    echo "Usage: $0 [-s <serial>] [--sort apk|wifi|mobile] <package_name_1> [package_name_2] ..."
    echo "Example: $0 --sort wifi com.android.chrome com.google.android.youtube"
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

# Cache the network stats output ONCE to massively speed up the loop processing
echo "Caching device network statistics (this may take a moment)..."
netstats_dump=$($ADB shell dumpsys netstats detail 2>/dev/null | tr -d '\r')

echo ""
echo "Fetching data for $total_packages package(s)..."

total_bytes=0
total_wifi=0
total_mob=0
results=""
current_package=0

# 1. Gather all data first with a progress bar
for pkg in "$@"; do
    current_package=$((current_package + 1))
    percent=$((current_package * 100 / total_packages))
    
    # Calculate progress bar width (40 chars total)
    bar_width=40
    filled_width=$((percent * bar_width / 100))
    empty_width=$((bar_width - filled_width))
    
    # Build the bar strings
    bar=""
    for ((i=0; i<filled_width; i++)); do bar="${bar}#"; done
    empty_bar=""
    for ((i=0; i<empty_width; i++)); do empty_bar="${empty_bar}-"; done
    
    # Print the progress bar
    printf "\r\033[K[%s%s] %d%% (%d/%d) | Checking: %s" "$bar" "$empty_bar" "$percent" "$current_package" "$total_packages" "$pkg"

    # Fetch all APK paths (natively handles Split APKs)
    paths=$($ADB shell pm path "$pkg" 2>/dev/null | sed 's/^package://' | tr -d '\r')
    
    if [ -z "$paths" ]; then
        # Use -1 as the size so "Not installed" apps sort to the very bottom
        results="${results}-1 ${pkg} 0 0\n"
        continue
    fi
    
    pkg_bytes=0
    # Iterate over every file associated with the package and tally the bytes
    for file_path in $paths; do
        size=$($ADB shell stat -c "%s" "$file_path" 2>/dev/null | tr -d '\r')
        if [[ "$size" =~ ^[0-9]+$ ]]; then
            pkg_bytes=$((pkg_bytes + size))
        fi
    done
    
    # Get UID to cross-reference network stats
    uid=$($ADB shell dumpsys package "$pkg" | grep -m 1 "userId=" | awk -F'=' '{print $2}' | awk '{print $1}')
    
    wifi_bytes=0
    mob_bytes=0

    # Parse network data from the cached dump using awk
    if [ -n "$uid" ]; then
        read -r wifi_bytes mob_bytes <<< $(echo "$netstats_dump" | awk -v uid="$uid" '
        BEGIN {
            curr_type = "WIFI"; curr_uid = "";
            wifi=0; mob=0;
        }
        {
            if ($0 ~ /type=WIFI/ || $0 ~ /iface=wlan/) { curr_type = "WIFI" }
            else if ($0 ~ /type=MOBILE/ || $0 ~ /iface=rmnet/ || $0 ~ /iface=ccmni/ || $0 ~ /iface=mobile/) { curr_type = "MOBILE" }

            for(i=1; i<=NF; i++) {
                if ($i ~ /^uid=/) {
                    split($i, uarr, "="); curr_uid = uarr[2]; gsub(/[^0-9]/, "", curr_uid);
                }
            }

            if (curr_uid == uid) {
                rx = 0; tx = 0;
                for(i=1; i<=NF; i++) {
                    if ($i ~ /^rxBytes=/) { split($i, arr, "="); rx = arr[2]; gsub(/[^0-9]/, "", rx); }
                    else if ($i ~ /^txBytes=/) { split($i, arr, "="); tx = arr[2]; gsub(/[^0-9]/, "", tx); }
                    else if ($i ~ /^rb=/) { split($i, arr, "="); rx = arr[2]; gsub(/[^0-9]/, "", rx); }
                    else if ($i ~ /^tb=/) { split($i, arr, "="); tx = arr[2]; gsub(/[^0-9]/, "", tx); }
                }
                if (rx > 0 || tx > 0) {
                    if (curr_type == "WIFI") { wifi += (rx + tx) }
                    else { mob += (rx + tx) }
                }
            }
        }
        END {
            print wifi+0, mob+0
        }
        ')
    fi

    # Fallback to zero if extraction failed
    wifi_bytes=${wifi_bytes:-0}
    mob_bytes=${mob_bytes:-0}

    # Append to results list (Format: size pkg wifi mob)
    results="${results}${pkg_bytes} ${pkg} ${wifi_bytes} ${mob_bytes}\n"
    
    # Add to totals
    total_bytes=$((total_bytes + pkg_bytes))
    total_wifi=$((total_wifi + wifi_bytes))
    total_mob=$((total_mob + mob_bytes))
done

# Print a newline to lock in the 100% progress bar
echo ""
echo ""

# 2. Get Device Total Storage
storage_1k=$($ADB shell df /data 2>/dev/null | awk 'NR==2 {print $2}' | tr -d '\r')
if [[ "$storage_1k" =~ ^[0-9]+$ ]]; then
    device_storage_bytes=$((storage_1k * 1024))
    formatted_device_storage=$(format_bytes "$device_storage_bytes")
else
    formatted_device_storage="Unknown"
fi

# 3. Configure the sort command based on user preference
if [ "$SORT_BY" = "wifi" ]; then
    # Sort by col 3 (Wi-Fi), fallback to col 1 (APK Size)
    SORT_CMD="sort -k3,3nr -k1,1nr"
    sort_label="Wi-Fi Data"
elif [ "$SORT_BY" = "mobile" ]; then
    # Sort by col 4 (Mobile), fallback to col 1 (APK Size)
    SORT_CMD="sort -k4,4nr -k1,1nr"
    sort_label="Mobile Data"
else
    # Default: Sort by col 1 (APK Size)
    SORT_CMD="sort -k1,1nr"
    sort_label="APK Size"
fi

# 4. Print Header
echo "====================================================================================="
printf "%-40s | %-10s | %-10s | %-11s\n" "Android Package" "APK Size" "Wi-Fi Data" "Mobile Data"
echo "====================================================================================="

# 5. Execute Sort and Print Data
printf "%b" "$results" | $SORT_CMD | while read -r size pkg wifi mob; do
    if [ -z "$pkg" ]; then continue; fi # Skip empty lines
    
    if [ "$size" -eq -1 ]; then
        printf "%-40s | %-10s | %-10s | %-11s\n" "$pkg" "Not Inst." "-" "-"
    else
        printf "%-40s | %-10s | %-10s | %-11s\n" "$pkg" "$(format_bytes "$size")" "$(format_bytes "$wifi")" "$(format_bytes "$mob")"
    fi
done

# 6. Print Footer
echo "====================================================================================="
printf "%-40s | %-10s | %-10s | %-11s\n" "TOTAL SELECTED" "$(format_bytes "$total_bytes")" "$(format_bytes "$total_wifi")" "$(format_bytes "$total_mob")"
printf "%-40s | %-10s | %-10s | %-11s\n" "DEVICE STORAGE (/data)" "$formatted_device_storage" "-" "-"
echo "====================================================================================="

echo ""
echo "Sorted By: $sort_label"
echo "Note: APK Size measures the base and split APKs. User Data and App Cache are excluded without root."