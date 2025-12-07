#!/bin/bash
#
###############################################################################
# This script applies a fix to prevent STAPM (Skin Temperature Aware Power
# Management) from prematurely throttling the laptop clocks during load.
# As described in the linked forum thread below, the processor can think that
# the skin temperature is too high and throttle, even when the core temps are
# alright. This script runs the ryzenadj tool to modify some of the power
# profile settings and temporarily disable STAPM from throttling, but as far
# as I'm aware needs to be re-run every time the laptop is put under load
#
# https://github.com/FlyGoat/RyzenAdj?tab=readme-ov-file
# https://community.frame.work/t/solved-radeon-780m-thermal-throttling-to-800mhz-until-entire-laptop-chassis-cools-off/58576

sudo ryzenadj --tctl-temp=100 --apu-skin-temp=50 --stapm-limit=28000 --vrm-current=180000 --vrmmax-current=180000 --slow-limit=28000 --fast-limit=35000 --vrmsoc-current=180000 --vrmsocmax-current=180000 --vrmgfx-current=18000
