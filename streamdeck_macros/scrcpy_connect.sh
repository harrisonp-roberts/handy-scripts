#!/bin/bash
notify-send "starting scpy"
adb devices

if ! adb devices 2> /dev/null; then
    notify-send "failed to detect adb device"
    exit
else
    scrcpy 2> /dev/null &
fi