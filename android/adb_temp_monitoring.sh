#!/bin/bash

# Configuration: Set overheating thresholds in Celsius
CPU_THRESHOLD=45
BATT_THRESHOLD=40

# --- Device Validation Logic ---
# Get list of online serial numbers (ignores header and empty lines)
DEVICES=($(adb devices | awk 'NR>1 {print $1}'))
NUM_DEVICES=${#DEVICES[@]}

# Case 1: An argument was provided
if [ ! -z "$1" ]; then
    DEVICE_ID="$1"
    # Verify the provided device is actually connected
    if [[ ! " ${DEVICES[@]} " =~ " ${DEVICE_ID} " ]]; then
        echo "Error: Device '$DEVICE_ID' is not connected."
        echo "Available devices:"
        adb devices
        exit 1
    fi
# Case 2: No argument, but exactly one device is connected
elif [ "$NUM_DEVICES" -eq 1 ]; then
    DEVICE_ID="${DEVICES[0]}"
# Case 3: No argument, but multiple devices are connected (Error out)
elif [ "$NUM_DEVICES" -gt 1 ]; then
    echo "Error: Multiple devices connected, but no target device specified."
    echo "Please specify a device ID from the list below as an argument."
    echo "Usage: $0 <device_serial>"
    echo "------------------------------------------------------------"
    adb devices
    exit 1
# Case 4: No devices connected at all
else
    echo "Error: No devices found. Please plug in a device with USB debugging enabled."
    exit 1
fi

# Define the targeted adb command prefix
ADB_CMD="adb -s $DEVICE_ID"

echo "Target Device : $DEVICE_ID"
echo "Press [CTRL+C] to stop monitoring."
echo "---------------------------------"

while true; do
    # 1. Fetch CPU Temperature
    CPU_RAW=$($ADB_CMD shell "dumpsys thermalservice" | grep -A 2 -i "mName=CPU" | grep -oE "mValue=[0-9.]+" | head -n 1 | cut -d'=' -f2)
    if [ -z "$CPU_RAW" ]; then
        CPU_RAW=$($ADB_CMD shell "dumpsys hardware_properties" | grep -i "Cpu temperatures" | grep -oE "[0-9.]+" | head -n 1)
    fi

    # 2. Fetch Battery Temperature
    BATT_RAW=$($ADB_CMD shell "dumpsys battery" | grep -i "temperature" | grep -oE "[0-9]+")
    if [ ! -z "$BATT_RAW" ]; then
        BATT_CELSIUS=$(echo "scale=1; $BATT_RAW / 10" | bc)
    fi

    # 3. Format and Color-Code CPU Output
    if [ -z "$CPU_RAW" ]; then
        CPU_OUT="CPU: ERR"
    else
        CPU_INT=$(printf "%.0f" "$CPU_RAW")
        if [ "$CPU_INT" -ge "$CPU_THRESHOLD" ]; then
            CPU_OUT="CPU: \033[1;31m${CPU_RAW}°C [HOT!]\033[0m"
        else
            CPU_OUT="CPU: \033[1;32m${CPU_RAW}°C [OK]\033[0m"
        fi
    fi

    # 4. Format and Color-Code Battery Output
    if [ -z "$BATT_RAW" ]; then
        BATT_OUT="BATT: ERR"
    else
        BATT_INT=$((BATT_RAW / 10))
        if [ "$BATT_INT" -ge "$BATT_THRESHOLD" ]; then
            BATT_OUT="BATT: \033[1;31m${BATT_CELSIUS}°C [HOT!]\033[0m"
        else
            BATT_OUT="BATT: \033[1;32m${BATT_CELSIUS}°C [OK]\033[0m"
        fi
    fi

    # Print both metrics on the exact same terminal line
    echo -ne "$CPU_OUT  |  $BATT_OUT               \r"

    sleep 1
done
