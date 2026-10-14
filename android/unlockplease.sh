#!/bin/bash

for ((i=1000;i<=999999;i++)); do
    echo $i
    response=$(adb shell locksettings clear --old $i)
    echo "$response"
    sleep 5
done

