#!/bin/sh

pkg=$1
serial=$2

if [ -z "$pkg" ]; then
    echo "Usage: sh app_size.sh <package.name> [device_serial]"
    exit 1
fi

# Handle device selection based on whether a serial was provided
if [ -n "$serial" ]; then
    # Verify the provided serial is actually connected
    if ! adb devices | grep -w "device" | grep -q "^$serial"; then
        echo "❌ Device with serial '$serial' is not connected or authorized."
        exit 1
    fi
    target_device="$serial"
    echo "✅ Using specified device: $target_device"
else
    # No serial provided, check connected devices
    devices=$(adb devices | grep -w "device" | awk '{print $1}')
    
    if [ -z "$devices" ]; then
        device_count=0
    else
        device_count=$(echo "$devices" | wc -w)
    fi

    if [ "$device_count" -eq 0 ]; then
        echo "❌ No ADB devices connected or authorized."
        exit 1
    elif [ "$device_count" -eq 1 ]; then
        target_device=$(echo "$devices" | awk '{print $1}')
        echo "✅ Using only connected device: $target_device"
    else
        echo "📱 Multiple devices detected. Please select one:"
        i=1
        for dev in $devices; do
            # Fetch the device model to make selection easier
            model=$(adb -s "$dev" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
            echo "  $i) $dev ($model)"
            i=$((i + 1))
        done
        printf "Select device (1-%d): " "$((i - 1))"
        read -r choice
        
        # Get the selected device ID
        target_device=$(echo "$devices" | awk -v c="$choice" 'NR==c {print $1}')
        if [ -z "$target_device" ]; then
            echo "❌ Invalid selection."
            exit 1
        fi
        echo "✅ Selected device: $target_device"
    fi
fi

echo ""
echo "[1/4] Locating $pkg..."
paths=$(adb -s "$target_device" shell pm path "$pkg" | grep 'package:' | sed 's/package://' | tr -d '\r')

if [ -z "$paths" ]; then
    echo "❌ Package '$pkg' is not installed or cannot be found on device $target_device."
    exit 1
fi

echo "[2/4] Measuring APK size on the partition..."
app_size_bytes=0
for path in $paths; do
    # Using standard ls -l to avoid 'stat' compatibility issues on custom Android builds
    raw_size=$(adb -s "$target_device" shell ls -l "$path" 2>/dev/null | awk '{print $5}' | tr -d '\r')
    
    # Ensure it's a valid number to prevent shell math crashes
    clean_size=$(echo "$raw_size" | awk '/^[0-9]+$/{print $1; exit} {print 0}')
    app_size_bytes=$((app_size_bytes + clean_size))
done

echo "[3/4] Querying system for Data/Cache sizes..."
# Switched back to adb shell (exec-out can hang on Windows/macOS sometimes)
raw_stats=$(adb -s "$target_device" shell dumpsys diskstats 2>/dev/null | tr -d '\r')

echo "[4/4] Parsing results..."

data_cache=$(echo "$raw_stats" | awk -v pkg="$pkg" '
/Package Names:/ { sub(/.*Package Names: \[/, ""); sub(/\].*/, ""); split($0, pkgs, ","); for(i=1; i<=length(pkgs); i++) { gsub(/^[ \t]+|[ \t]+$/, "", pkgs[i]); if(pkgs[i] == pkg) { idx = i; break } } }
/App Data Sizes:/ { sub(/.*App Data Sizes: \[/, ""); sub(/\].*/, ""); split($0, dsize, ",") }
/Cache Sizes:/ { sub(/.*Cache Sizes: \[/, ""); sub(/\].*/, ""); split($0, csize, ",") }
END {
    if(idx > 0 && dsize[idx] != "") {
        print dsize[idx] ":" csize[idx]
    } else {
        print "0:0"
    }
}')

dsize=$(echo "$data_cache" | cut -d: -f1)
csize=$(echo "$data_cache" | cut -d: -f2)

# Math helper for megabytes
calc_mb() {
    echo | awk -v bytes="$1" '{ printf "%8.2f", bytes / 1048576 }'
}

app_mb=$(calc_mb "$app_size_bytes")
data_mb=$(calc_mb "$dsize")
cache_mb=$(calc_mb "$csize")
total_bytes=$((app_size_bytes + dsize + csize))
total_mb=$(calc_mb "$total_bytes")

# Identify app type
if echo "$paths" | grep -qE "^/system|^/product|^/vendor"; then
    app_type="(System/Priv App)"
else
    app_type="(User App)"
fi

printf "\n📦 \033[1;34m%s\033[0m %s\n" "$pkg" "$app_type"
printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "📱 \033[1;32mApp Size:\033[0m   %s MB\n" "$app_mb"
printf "📂 \033[1;33mData Size:\033[0m   %s MB\n" "$data_mb"
printf "🗑️  \033[1;36mCache Size:\033[0m  %s MB\n" "$cache_mb"
printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "📊 \033[1;35mTotal Size:\033[0m  %s MB\n\n" "$total_mb"