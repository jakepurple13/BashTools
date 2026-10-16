#!/bin/bash

# Ensure ADB is available
if ! command -v adb &> /dev/null; then
    echo "Error: adb is not installed or not in your PATH."
    exit 1
fi

# Get list of connected devices
devices=($(adb devices | grep -v "List" | grep "device$" | awk '{print $1}'))

# Handle device selection
if [ ${#devices[@]} -eq 0 ]; then
    echo "Error: No ADB devices connected."
    exit 1
elif [ ${#devices[@]} -eq 1 ]; then
    device="${devices[0]}"
    echo "Using the only connected device: $device"
else
    echo "Multiple devices detected. Please select one:"
    select device in "${devices[@]}"; do
        if [ -n "$device" ]; then
            echo "Selected device: $device"
            break
        else
            echo "Invalid selection. Try again."
        fi
    done
fi

# Prompt for package name
echo ""
read -p "Enter the app package name (e.g., com.google.android.youtube): " package_name

if [ -z "$package_name" ]; then
    echo "Error: Package name cannot be empty."
    exit 1
fi

# Fetch the UID
echo "Looking up UID for $package_name..."
uid=$(adb -s "$device" shell dumpsys package "$package_name" | grep -m 1 "userId=" | awk -F'=' '{print $2}' | awk '{print $1}')

if [ -z "$uid" ]; then
    echo "Error: Could not find UID. Is the app installed on this device?"
    exit 1
fi

echo "Fetching and calculating network usage for $package_name (UID: $uid)..."

# Pass the ENTIRE dumpsys output into awk to track multiline states
adb -s "$device" shell dumpsys netstats detail | awk -v uid="$uid" -v pkg="$package_name" '
# Function to format bytes into human-readable sizes
function format_bytes(b) {
    if (b == 0 || b == "") return "0 B";
    if (b >= 1073741824) return sprintf("%.2f GB", b/1073741824);
    if (b >= 1048576) return sprintf("%.2f MB", b/1048576);
    if (b >= 1024) return sprintf("%.2f KB", b/1024);
    return b " B";
}

BEGIN {
    curr_type = "WIFI"; # Default fallback
    curr_uid = "";
    curr_set = "DEFAULT";
    wifi_fg_rx=0; wifi_fg_tx=0; wifi_bg_rx=0; wifi_bg_tx=0;
    mob_fg_rx=0; mob_fg_tx=0; mob_bg_rx=0; mob_bg_tx=0;
}
{
    # Track the current network interface type
    if ($0 ~ /type=WIFI/ || $0 ~ /iface=wlan/) { curr_type = "WIFI" }
    else if ($0 ~ /type=MOBILE/ || $0 ~ /iface=rmnet/ || $0 ~ /iface=ccmni/ || $0 ~ /iface=mobile/) { curr_type = "MOBILE" }

    # Update current UID and Set (Foreground/Background) if they appear on this line
    for(i=1; i<=NF; i++) {
        if ($i ~ /^uid=/) {
            split($i, uarr, "=");
            curr_uid = uarr[2];
            gsub(/[^0-9]/, "", curr_uid); # Clean up any trailing commas/brackets
        }
        if ($i ~ /^set=/) {
            split($i, sarr, "=");
            curr_set = sarr[2];
            gsub(/[^A-Z_]/, "", curr_set);
        }
    }

    # If we are currently inside a block of data for our target UID, collect the bytes
    if (curr_uid == uid) {
        is_bg = (curr_set == "BACKGROUND" || curr_set == "DEFAULT_BACKGROUND") ? 1 : 0;
        rx = 0; tx = 0;
        
        # Loop through fields dynamically to find bytes
        for(i=1; i<=NF; i++) {
            if ($i ~ /^rxBytes=/) { split($i, arr, "="); rx = arr[2]; gsub(/[^0-9]/, "", rx); }
            else if ($i ~ /^txBytes=/) { split($i, arr, "="); tx = arr[2]; gsub(/[^0-9]/, "", tx); }
            else if ($i ~ /^rb=/) { split($i, arr, "="); rx = arr[2]; gsub(/[^0-9]/, "", rx); }
            else if ($i ~ /^tb=/) { split($i, arr, "="); tx = arr[2]; gsub(/[^0-9]/, "", tx); }
        }

        # Add to the correct bucket based on network type and foreground/background state
        if (rx > 0 || tx > 0) {
            if (curr_type == "WIFI") {
                if (is_bg) { wifi_bg_rx += rx; wifi_bg_tx += tx; }
                else { wifi_fg_rx += rx; wifi_fg_tx += tx; }
            } else {
                if (is_bg) { mob_bg_rx += rx; mob_bg_tx += tx; }
                else { mob_fg_rx += rx; mob_fg_tx += tx; }
            }
        }
    }
}
END {
    # Calculate rows
    w_fg_tot = wifi_fg_rx + wifi_fg_tx;
    w_bg_tot = wifi_bg_rx + wifi_bg_tx;
    m_fg_tot = mob_fg_rx + mob_fg_tx;
    m_bg_tot = mob_bg_rx + mob_bg_tx;
    
    # Calculate blocks
    wifi_tot = w_fg_tot + w_bg_tot;
    mob_tot = m_fg_tot + m_bg_tot;
    grand_tot = wifi_tot + mob_tot;

    printf "\n📊 Network Usage Summary: %s\n", pkg;
    printf "=======================================================================\n";
    printf "%-10s | %-11s | %-11s | %-11s | %-11s\n", "Network", "State", "Downloaded", "Uploaded", "Total";
    printf "-----------------------------------------------------------------------\n";
    printf "%-10s | %-11s | %-11s | %-11s | %-11s\n", "Wi-Fi", "Foreground", format_bytes(wifi_fg_rx), format_bytes(wifi_fg_tx), format_bytes(w_fg_tot);
    printf "%-10s | %-11s | %-11s | %-11s | %-11s\n", "Wi-Fi", "Background", format_bytes(wifi_bg_rx), format_bytes(wifi_bg_tx), format_bytes(w_bg_tot);
    printf "%-10s | %-11s | %-11s | %-11s | %-11s\n", "Mobile", "Foreground", format_bytes(mob_fg_rx), format_bytes(mob_fg_tx), format_bytes(m_fg_tot);
    printf "%-10s | %-11s | %-11s | %-11s | %-11s\n", "Mobile", "Background", format_bytes(mob_bg_rx), format_bytes(mob_bg_tx), format_bytes(m_bg_tot);
    printf "-----------------------------------------------------------------------\n";
    printf "Wi-Fi Total:  %s\n", format_bytes(wifi_tot);
    printf "Mobile Total: %s\n", format_bytes(mob_tot);
    printf "=======================================================================\n";
    printf "Total Combined Data: %s\n\n", format_bytes(grand_tot);
}'