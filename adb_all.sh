#!/bin/bash
export BLUE=$(tput setaf 4 :-"" 2>/dev/null)
export RESET=$(tput sgr0 :-"" 2>/dev/null)

DEVICES=$(adb devices | grep -v devices | grep device | cut -f 1)
for device in $DEVICES; do
    deviceManufacturer=$(adb -s "$device" shell getprop ro.product.vendor.manufacturer)
    deviceModel=$(adb -s "$device" shell getprop ro.product.model)
    deviceSdk=$(adb -s "$device" shell getprop ro.product.build.version.sdk)
    deviceApi=$(adb -s "$device" shell getprop ro.product.build.version.release)
    echo "$deviceManufacturer $deviceModel Sdk: $deviceSdk Api: $deviceApi"
    echo "$device $@"
    adb -s "$device" $@
    printf "$BLUE"; printf '%.s─' $(seq 1 $(tput cols)); echo "$RESET";
done